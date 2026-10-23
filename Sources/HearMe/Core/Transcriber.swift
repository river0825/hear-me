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
/// Nothing leaves the machine. Optionally runs a second language model on the same audio and
/// picks the transcript with the higher confidence ("auto-detect" between two languages).
final class Transcriber {
    /// One language module and what it has produced so far.
    final class Track {
        let localeId: String
        let module: SpeechTranscriber
        var finalText = ""
        var volatileText = ""
        var confidenceSum = 0.0
        var confidenceWeight = 0.0
        var task: Task<Void, Never>?
        init(localeId: String, module: SpeechTranscriber) { self.localeId = localeId; self.module = module }
        var text: String { (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines) }
        var meanConfidence: Double { confidenceWeight > 0 ? confidenceSum / confidenceWeight : 0 }
    }

    struct Outcome { let text: String; let localeId: String; let alternatives: [(localeId: String, text: String, confidence: Double)] }

    private var analyzer: SpeechAnalyzer?
    private var tracks: [Track] = []
    private var converter: BufferConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private(set) var fedBuffers = 0
    /// (finalized so far, current volatile tail) of the primary language, for the live HUD.
    var onUpdate: ((String, String) -> Void)?

    var finalText: String { tracks.first?.finalText ?? "" }
    var volatileText: String { tracks.first?.volatileText ?? "" }
    var currentText: String { tracks.first?.text ?? "" }

    static func makeModule(localeId: String, progressive: Bool) async throws -> SpeechTranscriber {
        let wanted = Locale(identifier: localeId)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            throw TranscribeError.localeUnsupported(localeId)
        }
        let module = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: progressive ? [.volatileResults, .fastResults] : [],
            attributeOptions: [.transcriptionConfidence]
        )
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

    static func confidence(of text: AttributedString) -> (sum: Double, weight: Double) {
        var sum = 0.0, weight = 0.0
        for run in text.runs {
            let n = Double(text[run.range].characters.count)
            if let c = run.transcriptionConfidence { sum += c * n; weight += n }
        }
        return (sum, weight)
    }

    // MARK: live

    func start(localeId: String, secondaryLocaleId: String? = nil, contextualStrings: [String], progressive: Bool = true) async throws {
        var modules: [Track] = [Track(localeId: localeId, module: try await Self.makeModule(localeId: localeId, progressive: progressive))]
        if let second = secondaryLocaleId, !second.isEmpty, second != localeId {
            do {
                modules.append(Track(localeId: second, module: try await Self.makeModule(localeId: second, progressive: progressive)))
            } catch {
                Log.warn("secondary language \(second) unavailable: \(error)")
            }
        }
        let analyzer = SpeechAnalyzer(
            modules: modules.map(\.module),
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
        try await analyzer.setContext(Self.makeContext(contextualStrings: contextualStrings))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules.map(\.module)) else {
            throw TranscribeError.noAudioFormat
        }
        converter = BufferConverter(targetFormat: format)
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = cont
        for (index, track) in modules.enumerated() {
            track.task = Task { [weak self] in
                do {
                    for try await result in track.module.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            track.finalText += text
                            track.volatileText = ""
                            let c = Self.confidence(of: result.text)
                            track.confidenceSum += c.sum; track.confidenceWeight += c.weight
                        } else {
                            track.volatileText = text
                        }
                        Log.info("[\(track.localeId)] final=\(result.isFinal) range=\(result.range.start.seconds)-\(result.range.end.seconds) text=\(text)")
                        if index == 0, let self {
                            let f = track.finalText, v = track.volatileText
                            DispatchQueue.main.async { self.onUpdate?(f, v) }
                        }
                    }
                    Log.info("[\(track.localeId)] results stream ended normally")
                } catch {
                    Log.warn("[\(track.localeId)] results stream ended: \(error)")
                }
            }
        }
        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        self.tracks = modules
        fedBuffers = 0
        Log.info("transcriber started (\(modules.map(\.localeId).joined(separator: "+")), analyzer format \(format.sampleRate) Hz)")
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

    /// Flush, wait briefly for the last results, pick the best language and return everything.
    func finish() async -> Outcome {
        Log.info("transcriber finish: fed \(fedBuffers) buffers, text so far \(currentText.count) chars")
        continuation?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            Log.info("analyzer finished")
        } catch {
            Log.warn("finalize failed: \(error)")
            await analyzer?.cancelAndFinishNow()
        }
        // The results streams do not reliably end after the analyzer finishes (observed on macOS 27),
        // so give them a short grace period for the last final result, then move on with what we have.
        let tasks = tracks.map(\.task)
        let ended = await withTimeout(1.5) { for t in tasks { await t?.value } }
        if ended == nil {
            Log.info("results stream still open after finish; using accumulated text")
            tasks.forEach { $0?.cancel() }
        }
        let outcome = Self.choose(tracks)
        analyzer = nil; tracks = []; converter = nil; continuation = nil
        return outcome
    }

    /// Fraction of letters in `text` that belong to the script this locale is expected to produce.
    /// A zh model transcribing English speech outputs Latin letters with high confidence, so confidence
    /// alone cannot tell the languages apart; the script can.
    static func scriptMatch(_ text: String, localeId: String) -> Double {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let cjk = localeId.hasPrefix("zh") || localeId.hasPrefix("ja") || localeId.hasPrefix("ko")
        let matching = letters.filter { u in
            let v = u.value
            let isHan = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x3040...0x30FF).contains(v) || (0xAC00...0xD7AF).contains(v)
            return cjk ? isHan : !isHan
        }
        return Double(matching.count) / Double(letters.count)
    }

    static func score(text: String, localeId: String, confidence: Double) -> Double {
        confidence * scriptMatch(text, localeId: localeId)
    }

    static func choose(_ tracks: [Track]) -> Outcome {
        let alts = tracks.map { (localeId: $0.localeId, text: $0.text, confidence: $0.meanConfidence) }
        guard let primary = tracks.first else { return Outcome(text: "", localeId: "", alternatives: []) }
        var best = primary
        var bestScore = score(text: primary.text, localeId: primary.localeId, confidence: primary.meanConfidence)
        for t in tracks.dropFirst() where !t.text.isEmpty {
            let sc = score(text: t.text, localeId: t.localeId, confidence: t.meanConfidence)
            // Ties go to the primary language.
            if sc > bestScore + 0.05 || best.text.isEmpty { best = t; bestScore = sc }
        }
        if tracks.count > 1 {
            Log.info("language pick: " + tracks.map { "\($0.localeId) conf=\(String(format: "%.2f", $0.meanConfidence)) script=\(String(format: "%.2f", scriptMatch($0.text, localeId: $0.localeId))) \"\($0.text.prefix(40))\"" }.joined(separator: " | ") + " → \(best.localeId)")
        }
        return Outcome(text: best.text, localeId: best.localeId, alternatives: alts)
    }

    func cancel() async {
        continuation?.finish()
        await analyzer?.cancelAndFinishNow()
        tracks.forEach { $0.task?.cancel() }
        analyzer = nil; tracks = []; converter = nil; continuation = nil
    }

    // MARK: file (CLI test mode): same code path as the microphone, fed from a file.

    static func transcribeFile(_ url: URL, localeId: String, secondaryLocaleId: String? = nil, contextualStrings: [String]) async throws -> Outcome {
        let file = try AVAudioFile(forReading: url)
        let t = Transcriber()
        try await t.start(localeId: localeId, secondaryLocaleId: secondaryLocaleId, contextualStrings: contextualStrings, progressive: false)
        let chunk: AVAudioFrameCount = 4096
        while file.framePosition < file.length {
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
            try file.read(into: buf, frameCount: chunk)
            if buf.frameLength == 0 { break }
            t.feed(buf, at: nil)
        }
        return await t.finish()
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
