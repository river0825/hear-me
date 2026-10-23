import AppKit
import AVFoundation
import Foundation

@main
struct HearMeMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let dir = CLI.value("--render-ui", in: args) {
            // Needs an NSApplication for AppKit drawing, but never shows a window.
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            do {
                let files = try MainActor.assumeIsolated { try UIRender.render(to: URL(fileURLWithPath: dir), settings: Settings.shared) }
                for f in files { print("wrote", f.path) }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                exit(1)
            }
        }
        if let first = args.first, first.hasPrefix("--") {
            let code = CLI.run(args)
            exit(code)
        }
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.run()
    }
}

/// Headless entry points used for testing the pipeline on a machine without a microphone,
/// and for producing evidence files.
enum CLI {
    static func usage() -> String {
        """
        HearMe  (no args)                                 啟動選單列 app
        HearMe --transcribe <audio> [--locale zh_TW] [--dict 詞,詞] [--polish] [--tone general|formal|casual|verbatim] [--lang same|english|japanese|traditionalChinese] [--app 名稱]
        HearMe --polish-text "<逐字稿>" [--tone …] [--lang …] [--dict …] [--app …]
        HearMe --command "<選取文字>" --say "<指令>"
        HearMe --simulate-live <audio> [--polish] [--verbose]   把音檔當麥克風串流走即時路徑
        HearMe --doctor                                   列出權限與模型狀態
        HearMe --render-ui <dir>                          把 HUD 各狀態與設定頁離屏畫成 PNG
        """
    }

    static func value(_ flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func run(_ args: [String]) -> Int32 {
        setlinebuf(stdout)
        Log.verbose = args.contains("--verbose")
        let locale = value("--locale", in: args) ?? "zh_TW"
        let dict = (value("--dict", in: args) ?? "").split(separator: ",").map(String.init)
        let tone = Tone(rawValue: value("--tone", in: args) ?? "") ?? .general
        let lang = OutputLanguage(rawValue: value("--lang", in: args) ?? "") ?? .same
        let app = value("--app", in: args)

        func polishAndPrint(raw: String) async {
            let t = Date()
            let (out, used) = await Polisher.polish(PolishRequest(raw: raw, tone: tone, outputLanguage: lang, dictionary: dict, appName: app, speechLocale: locale))
            print("polished (\(used ? "on-device model" : "rules"), \(String(format: "%.2f", Date().timeIntervalSince(t)))s, tone=\(tone.rawValue), lang=\(lang.rawValue)):")
            print(out)
        }

        // Keep the main run loop alive so main-queue callbacks (UI updates) can run while we wait.
        var code: Int32 = 0
        var finished = false
        Task {
            defer { finished = true }
            do {
                if args.contains("--doctor") {
                    print("macOS:", ProcessInfo.processInfo.operatingSystemVersionString)
                    print("accessibility:", Permissions.accessibilityTrusted(prompt: false))
                    print("microphone:", Permissions.microphoneStatus, "input device:", AudioCapture.hasInputDevice())
                    print("on-device model:", Polisher.availability)
                    print("speech locales installed:", await SpeechLocaleProbe.installed())
                    print("history:", History.shared.url.path)
                    print("log:", Log.fileURL.path)
                } else if let path = value("--transcribe", in: args) {
                    let t = Date()
                    let raw = try await Transcriber.transcribeFile(URL(fileURLWithPath: path), localeId: locale, contextualStrings: dict)
                    print("transcript (\(locale), \(String(format: "%.2f", Date().timeIntervalSince(t)))s):")
                    print(raw)
                    if args.contains("--polish") { await polishAndPrint(raw: raw) }
                } else if let path = value("--simulate-live", in: args) {
                    // Push a file through the live (microphone) path in mic-sized chunks.
                    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
                    let t = Transcriber()
                    var updates = 0
                    t.onUpdate = { f, v in updates += 1; if Log.verbose { print("  update #\(updates): [\(f)] + [\(v)]") } }
                    let t0 = Date()
                    try await t.start(localeId: locale, contextualStrings: dict)
                    print("live transcriber started in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
                    let chunk: AVAudioFrameCount = 4096
                    var fed = 0
                    while file.framePosition < file.length {
                        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
                        try file.read(into: buf, frameCount: chunk)
                        if buf.frameLength == 0 { break }
                        t.feed(buf, at: nil)
                        fed += 1
                        // Pace roughly like a microphone so volatile results show up as they would live.
                        try? await Task.sleep(nanoseconds: UInt64(Double(buf.frameLength) / file.processingFormat.sampleRate * 0.5 * 1e9))
                    }
                    let t1 = Date()
                    let raw = await withTimeout(8) { await t.finish() }
                    print("fed \(fed) chunks, \(updates) live updates, finish took \(String(format: "%.2f", Date().timeIntervalSince(t1)))s\(raw == nil ? " (TIMEOUT)" : "")")
                    print("transcript:")
                    print(raw ?? t.currentText)
                    if args.contains("--polish") { await polishAndPrint(raw: raw ?? t.currentText) }
                } else if let raw = value("--polish-text", in: args) {
                    print("raw:")
                    print(raw)
                    await polishAndPrint(raw: raw)
                } else if let selected = value("--command", in: args), let say = value("--say", in: args) {
                    let t = Date()
                    let out = try await Polisher.applyCommand(selected: selected, instruction: say, speechLocale: locale)
                    print("result (\(String(format: "%.2f", Date().timeIntervalSince(t)))s):")
                    print(out)
                } else {
                    print(usage())
                    code = 2
                }
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                code = 1
            }
        }
        while !finished {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return code
    }
}

enum SpeechLocaleProbe {
    static func installed() async -> [String] {
        await Speech.SpeechTranscriber.installedLocales.map(\.identifier).sorted()
    }
}
import Speech
