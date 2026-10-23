import AVFoundation
import Speech

enum TranscribeError: LocalizedError {
    case localeUnsupported(String)
    case noAudioFormat
    case modelMissing(String)
    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let l): return "語音辨識不支援 \(l)"
        case .noAudioFormat: return "找不到語音辨識可用的音訊格式"
        case .modelMissing(let l): return "\(l) 的語音模型還沒下載好"
        }
    }
}

/// On-device speech-to-text built on macOS 26's SpeechAnalyzer / SpeechTranscriber.
/// Nothing leaves the machine.
final class Transcriber {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var converter: BufferConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    private(set) var finalText = ""
    private(set) var volatileText = ""
    private(set) var fedBuffers = 0
    /// (finalized so far, current volatile tail)
    var onUpdate: ((String, String) -> Void)?

    static func makeModule(localeId: String, progressive: Bool) async throws -> SpeechTranscriber {
        let wanted = Locale(identifier: localeId)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            throw TranscribeError.localeUnsupported(localeId)
        }
        let module = SpeechTranscriber(locale: locale, preset: progressive ? .progressiveTranscription : .transcription)
        try await ensureAssets(for: module, localeId: localeId)
        return module
    }

    static func ensureAssets(for module: SpeechTranscriber, localeId: String) async throws {
        let status = await AssetInventory.status(forModules: [module])
        if status == .installed { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        if await AssetInventory.status(forModules: [module]) != .installed {
            throw TranscribeError.modelMissing(localeId)
        }
    }

    static func makeContext(contextualStrings: [String]) -> AnalysisContext {
        let ctx = AnalysisContext()
        let terms = contextualStrings.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !terms.isEmpty { ctx.contextualStrings[.general] = terms }
        return ctx
    }

    // MARK: live

    func start(localeId: String, contextualStrings: [String]) async throws {
        finalText = ""
        volatileText = ""
        let module = try await Self.makeModule(localeId: localeId, progressive: true)
        let analyzer = SpeechAnalyzer(
            modules: [module],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
        try await analyzer.setContext(Self.makeContext(contextualStrings: contextualStrings))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscribeError.noAudioFormat
        }
        converter = BufferConverter(targetFormat: format)
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = cont
        resultsTask = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    Log.info("result final=\(result.isFinal) range=\(result.range.start.seconds)-\(result.range.end.seconds) text=\(text)")
                    if result.isFinal {
                        self.finalText += text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                    let f = self.finalText, v = self.volatileText
                    // Never block the results loop on the main actor.
                    DispatchQueue.main.async { self.onUpdate?(f, v) }
                }
                Log.info("results stream ended normally")
            } catch {
                Log.warn("results stream ended: \(error)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        self.transcriber = module
        Log.info("transcriber started (\(localeId), analyzer format \(format.sampleRate) Hz)")
    }

    func feed(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        guard let converter, let continuation else { return }
        do {
            if let converted = try converter.convert(buffer) {
                fedBuffers += 1
                if fedBuffers == 1 { Log.info("first audio buffer: \(buffer.format.sampleRate) Hz ch=\(buffer.format.channelCount) → \(converted.format.sampleRate) Hz") }
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        } catch {
            Log.warn("convert failed: \(error)")
        }
    }

    var currentText: String { (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Flush, wait for the last results and return the whole transcript.
    func finish() async -> String {
        Log.info("transcriber finish: fed \(fedBuffers) buffers, text so far \(currentText.count) chars")
        continuation?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            Log.info("analyzer finished")
        } catch {
            Log.warn("finalize failed: \(error)")
            await analyzer?.cancelAndFinishNow()
        }
        // The results stream does not reliably end after the analyzer finishes (observed on macOS 27),
        // so give it a short grace period for the last final result, then move on with what we have.
        let ended = await withTimeout(1.5) { [resultsTask] in await resultsTask?.value }
        if ended == nil {
            Log.info("results stream still open after finish; using accumulated text")
            resultsTask?.cancel()
        }
        let text = finalText + volatileText
        analyzer = nil
        transcriber = nil
        converter = nil
        continuation = nil
        resultsTask = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        continuation?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        analyzer = nil
        transcriber = nil
        converter = nil
        continuation = nil
        resultsTask = nil
    }

    // MARK: file (used by the CLI test mode)

    static func transcribeFile(_ url: URL, localeId: String, contextualStrings: [String]) async throws -> String {
        let file = try AVAudioFile(forReading: url)
        let module = try await makeModule(localeId: localeId, progressive: false)
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.setContext(makeContext(contextualStrings: contextualStrings))
        let collector = Task<String, Error> {
            var text = ""
            for try await result in module.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Log {
    static var verbose = false
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("HearMe.log")
    }()
    private static let queue = DispatchQueue(label: "hearme.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    static func info(_ s: String) { write(s, stderr: verbose) }
    static func warn(_ s: String) { write(s, stderr: true) }

    private static func write(_ s: String, stderr: Bool) {
        let line = "\(stamp.string(from: Date())) \(s)\n"
        if stderr { FileHandle.standardError.write(Data(("[hearme] " + s + "\n").utf8)) }
        queue.async {
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}

/// Run `op`, giving up after `seconds`. Returns nil on timeout; `op` keeps running in the background
/// (a task group would wait for it, which is exactly the hang we are guarding against).
final class TimeoutOnce<T>: @unchecked Sendable {
    private var cont: CheckedContinuation<T?, Never>?
    private let lock = NSLock()
    init(_ c: CheckedContinuation<T?, Never>) { cont = c }
    func resume(_ v: T?) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: v)
    }
}

func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async -> T) async -> T? {
    return await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
        let once = TimeoutOnce<T>(c)
        Task.detached { once.resume(await op()) }
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            once.resume(nil)
        }
    }
}

/// Converts microphone buffers to the analyzer's preferred format (sample rate / channel count).
final class BufferConverter {
    let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) { self.targetFormat = targetFormat }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        if buffer.format == targetFormat { return buffer }
        if converter == nil || sourceFormat != buffer.format {
            guard let c = AVAudioConverter(from: buffer.format, to: targetFormat) else {
                throw TranscribeError.noAudioFormat
            }
            converter = c
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        if status == .error { throw TranscribeError.noAudioFormat }
        return out.frameLength > 0 ? out : nil
    }
}
