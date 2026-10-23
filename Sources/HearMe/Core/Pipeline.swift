import AppKit
import Foundation

enum PipelineState: Equatable {
    case idle
    case listening(mode: DictationMode)
    case polishing
    case done(String)
    case error(String)
}

enum DictationMode: String { case dictate, command }

/// Orchestrates one dictation: hotkey → mic → transcriber → polisher → paste → history.
@MainActor
final class Pipeline: ObservableObject {
    @Published private(set) var state: PipelineState = .idle
    @Published private(set) var finalText = ""
    @Published private(set) var volatileText = ""

    private let settings: Settings
    private let capture = AudioCapture()
    private var transcriber: Transcriber?
    private var startedAt: Date?
    private var targetApp: NSRunningApplication?
    private var selectedText: String?
    private var mode: DictationMode = .dictate
    private var stopping = false
    private var startTask: Task<Void, Never>?
    private var startFinished = false

    init(settings: Settings) {
        self.settings = settings
    }

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    func start(mode: DictationMode) {
        guard case .idle = state else {
            if case .done = state { state = .idle } else if case .error = state { state = .idle } else { return }
            start(mode: mode)
            return
        }
        self.mode = mode
        targetApp = NSWorkspace.shared.frontmostApplication
        finalText = ""
        volatileText = ""
        selectedText = nil
        state = .listening(mode: mode)
        startFinished = false
        Log.info("start mode=\(mode.rawValue) app=\(targetApp?.bundleIdentifier ?? "-")")
        startTask = Task {
            defer { startFinished = true }
            do {
                if mode == .command {
                    selectedText = await TextInjector.copySelection()
                    if (selectedText ?? "").isEmpty {
                        throw NSError(domain: "HearMe", code: 1, userInfo: [NSLocalizedDescriptionKey: "沒有選取文字。先選一段文字，再按住 ⇧ 加快捷鍵說指令。"])
                    }
                }
                let t = Transcriber()
                t.onUpdate = { [weak self] f, v in
                    self?.finalText = f
                    self?.volatileText = v
                }
                let locale = settings.speechLocale, second = settings.secondaryLocale
                let dict = settings.dictionary + CorrectionStore.shared.rightSides
                let started = await withTimeout(20) { () -> Error? in
                    do { try await t.start(localeId: locale, secondaryLocaleId: second, contextualStrings: dict); return nil } catch { return error }
                }
                guard let started else { throw NSError(domain: "HearMe", code: 10, userInfo: [NSLocalizedDescriptionKey: "語音辨識啟動逾時（20 秒）。語言模型可能還在下載，稍後再試。"]) }
                if let error = started { throw error }
                guard case .listening = state else {
                    // Stopped while we were starting up.
                    await t.cancel()
                    return
                }
                transcriber = t
                let format = try await capture.start { buffer, time in
                    t.feed(buffer, at: time)
                }
                Log.info("capture started: \(format.sampleRate) Hz ch=\(format.channelCount)")
                startedAt = Date()
            } catch {
                await fail(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard case .listening = state, !stopping else {
            Log.info("stop ignored: state=\(state) stopping=\(stopping)")
            return
        }
        stopping = true
        Log.info("stop")
        capture.stop()
        let audioSeconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        state = .polishing
        Task {
            defer { stopping = false }
            // If start-up has not finished yet, give it a moment, then give up on it.
            if !startFinished {
                let done = await withTimeout(3) { [startTask] in await startTask?.value }
                if done == nil { Log.warn("start-up still pending after stop; cancelling") }
            }
            capture.stop()
            let t0 = Date()
            var rawText = ""
            var spokenLocale = settings.speechLocale
            if let t = transcriber {
                let finished = await withTimeout(8) { await t.finish() }
                if let finished {
                    rawText = finished.text
                    spokenLocale = finished.localeId.isEmpty ? spokenLocale : finished.localeId
                } else {
                    Log.warn("finish timed out; using partial text")
                    rawText = t.currentText
                    await t.cancel()
                }
            }
            let transcribeSeconds = Date().timeIntervalSince(t0)
            transcriber = nil
            Log.info("raw (\(String(format: "%.2f", transcribeSeconds))s, audio \(String(format: "%.1f", audioSeconds))s): \(rawText)")
            let (corrected, used) = CorrectionStore.shared.apply(rawText)
            if !used.isEmpty { Log.info("applied corrections: " + used.map { "\($0.wrong)→\($0.right)" }.joined(separator: ", ")) }
            let raw = corrected
            guard !raw.isEmpty else {
                state = .error("沒聽到內容")
                scheduleIdle(after: 1.5)
                return
            }
            let bundleId = targetApp?.bundleIdentifier
            let tone = settings.tone(forBundleId: bundleId)
            let t1 = Date()
            var output: String
            if mode == .command, let selected = selectedText {
                do {
                    output = try await Polisher.applyCommand(selected: selected, instruction: raw, speechLocale: spokenLocale)
                } catch {
                    await fail("指令失敗：\(error.localizedDescription)")
                    return
                }
            } else if settings.polishEnabled {
                (output, _) = await Polisher.polish(PolishRequest(
                    raw: raw, tone: tone, outputLanguage: settings.outputLanguage,
                    dictionary: settings.dictionary, appName: targetApp?.localizedName,
                    speechLocale: spokenLocale, corrections: CorrectionStore.shared.items
                ))
            } else {
                output = TextRules.basicCleanup(raw)
            }
            let polishSeconds = Date().timeIntervalSince(t1)
            guard !output.isEmpty else {
                state = .error("整理後是空的")
                scheduleIdle(after: 1.5)
                return
            }
            // Make sure the original app is in front again before pasting.
            if let app = targetApp, NSWorkspace.shared.frontmostApplication != app {
                app.activate()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            Log.info("output (\(String(format: "%.2f", polishSeconds))s, tone \(tone.rawValue)): \(output)")
            TextInjector.paste(output, restoreClipboard: settings.restoreClipboard)
            History.shared.append(HistoryEntry(
                date: Date(), app: bundleId, mode: mode.rawValue, tone: tone.rawValue,
                raw: raw, output: output, audioSeconds: audioSeconds,
                transcribeSeconds: transcribeSeconds, polishSeconds: polishSeconds
            ))
            state = .done(output)
            scheduleIdle(after: 2.0)
        }
    }

    /// Test/evidence hook: put the pipeline in a given state without any audio.
    func debugSet(state: PipelineState, finalText: String, volatileText: String) {
        self.finalText = finalText
        self.volatileText = volatileText
        self.state = state
    }

    /// Hard reset from any state; used by the menu's 取消 and as the escape hatch.
    func cancel() {
        Log.info("cancel from state=\(state)")
        capture.stop()
        startTask?.cancel()
        let t = transcriber
        transcriber = nil
        stopping = false
        Task { await t?.cancel() }
        state = .idle
    }

    private func fail(_ message: String) async {
        Log.warn("fail: \(message)")
        capture.stop()
        let t = transcriber
        transcriber = nil
        await t?.cancel()
        state = .error(message)
        scheduleIdle(after: 3.0)
    }

    private func scheduleIdle(after seconds: TimeInterval) {
        let snapshot = state
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.state == snapshot else { return }
            self.state = .idle
        }
    }
}
