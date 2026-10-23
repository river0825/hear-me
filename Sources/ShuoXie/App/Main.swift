import AppKit
import Foundation

@main
struct ShuoXieMain {
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
        ShuoXie  (no args)                                 啟動選單列 app
        ShuoXie --transcribe <audio> [--locale zh_TW] [--dict 詞,詞] [--polish] [--tone general|formal|casual|verbatim] [--lang same|english|japanese|traditionalChinese] [--app 名稱]
        ShuoXie --polish-text "<逐字稿>" [--tone …] [--lang …] [--dict …] [--app …]
        ShuoXie --command "<選取文字>" --say "<指令>"
        ShuoXie --doctor                                   列出權限與模型狀態
        ShuoXie --render-ui <dir>                          把 HUD 各狀態與設定頁離屏畫成 PNG
        """
    }

    static func value(_ flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func run(_ args: [String]) -> Int32 {
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

        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task {
            defer { sem.signal() }
            do {
                if args.contains("--doctor") {
                    print("macOS:", ProcessInfo.processInfo.operatingSystemVersionString)
                    print("accessibility:", Permissions.accessibilityTrusted(prompt: false))
                    print("microphone:", Permissions.microphoneStatus, "input device:", AudioCapture.hasInputDevice())
                    print("on-device model:", Polisher.availability)
                    print("speech locales installed:", await SpeechLocaleProbe.installed())
                    print("history:", History.shared.url.path)
                } else if let path = value("--transcribe", in: args) {
                    let t = Date()
                    let raw = try await Transcriber.transcribeFile(URL(fileURLWithPath: path), localeId: locale, contextualStrings: dict)
                    print("transcript (\(locale), \(String(format: "%.2f", Date().timeIntervalSince(t)))s):")
                    print(raw)
                    if args.contains("--polish") { await polishAndPrint(raw: raw) }
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
        sem.wait()
        return code
    }
}

enum SpeechLocaleProbe {
    static func installed() async -> [String] {
        await Speech.SpeechTranscriber.installedLocales.map(\.identifier).sorted()
    }
}
import Speech
