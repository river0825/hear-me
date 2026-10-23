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
        Task {
            do {
                if mode == .command {
                    selectedText = await TextInjector.copySelection()
                    if (selectedText ?? "").isEmpty {
                        throw NSError(domain: "ShuoXie", code: 1, userInfo: [NSLocalizedDescriptionKey: "沒有選取文字。先選一段文字，再按住 ⇧ 加快捷鍵說指令。"])
                    }
                }
                let t = Transcriber()
                t.onUpdate = { [weak self] f, v in
                    self?.finalText = f
                    self?.volatileText = v
                }
                try await t.start(localeId: settings.speechLocale, contextualStrings: settings.dictionary)
                transcriber = t
                _ = try await capture.start { buffer, time in
                    t.feed(buffer, at: time)
                }
                startedAt = Date()
            } catch {
                await fail(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard case .listening = state, !stopping else { return }
        stopping = true
        capture.stop()
        let audioSeconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        state = .polishing
        Task {
            defer { stopping = false }
            let t0 = Date()
            let raw = await transcriber?.finish() ?? ""
            let transcribeSeconds = Date().timeIntervalSince(t0)
            transcriber = nil
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
                    output = try await Polisher.applyCommand(selected: selected, instruction: raw, speechLocale: settings.speechLocale)
                } catch {
                    await fail("指令失敗：\(error.localizedDescription)")
                    return
                }
            } else if settings.polishEnabled {
                (output, _) = await Polisher.polish(PolishRequest(
                    raw: raw, tone: tone, outputLanguage: settings.outputLanguage,
                    dictionary: settings.dictionary, appName: targetApp?.localizedName,
                    speechLocale: settings.speechLocale
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

    func cancel() {
        capture.stop()
        let t = transcriber
        transcriber = nil
        Task { await t?.cancel() }
        state = .idle
    }

    private func fail(_ message: String) async {
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
