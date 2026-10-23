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
                    if result.isFinal {
                        self.finalText += text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                    let f = self.finalText, v = self.volatileText
                    await MainActor.run { self.onUpdate?(f, v) }
                }
            } catch {
                Log.warn("results stream ended: \(error)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        self.transcriber = module
    }

    func feed(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        guard let converter, let continuation else { return }
        do {
            if let converted = try converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        } catch {
            Log.warn("convert failed: \(error)")
        }
    }

    /// Flush, wait for the last results and return the whole transcript.
    func finish() async -> String {
        continuation?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            Log.warn("finalize failed: \(error)")
            await analyzer?.cancelAndFinishNow()
        }
        await resultsTask?.value
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
    static func info(_ s: String) { if verbose { FileHandle.standardError.write(Data(("[shuoxie] " + s + "\n").utf8)) } }
    static func warn(_ s: String) { FileHandle.standardError.write(Data(("[shuoxie] " + s + "\n").utf8)) }
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
