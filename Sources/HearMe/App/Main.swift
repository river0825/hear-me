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
        HearMe --transcribe <audio> [--locale zh_TW] [--locale2 en_US] [--dict 詞,詞] [--polish] [--tone general|formal|casual|verbatim] [--lang same|english|japanese|traditionalChinese] [--app 名稱]
        HearMe --polish-text "<逐字稿>" [--tone …] [--lang …] [--dict …] [--app …]
        HearMe --command "<選取文字>" --say "<指令>"
        HearMe --simulate-live <audio> [--polish] [--verbose]   把音檔當麥克風串流走即時路徑
        HearMe --learn "辨識錯的=正確的"                     記住一個更正（之後逐字稿先替換，也告訴整理模型）
        HearMe --learn-diff "<上次貼上的>" "<改對的>"          從兩段文字的差異學更正
        HearMe --corrections                               列出記住的更正
        HearMe --doctor                                   列出權限與模型狀態
        HearMe --check-update                             問 GitHub 最新 Release，跟目前版本比
        HearMe --update --target <HearMe.app>             下載最新 Release、核對 sha256 與簽章後換掉 <HearMe.app>
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
        var locale = value("--locale", in: args) ?? "zh_TW"
        let locale2 = value("--locale2", in: args)
        let dict = (value("--dict", in: args) ?? "").split(separator: ",").map(String.init)
        let tone = Tone(rawValue: value("--tone", in: args) ?? "") ?? .general
        let lang = OutputLanguage(rawValue: value("--lang", in: args) ?? "") ?? .same
        let app = value("--app", in: args)

        let store = CorrectionStore.shared
        let devTerms = args.contains("--no-dev-vocab") ? [] : DevVocabulary.terms
        func applyCorrections(_ raw: String) -> String {
            var (fixed, used) = store.apply(raw)
            if !used.isEmpty { print("corrections applied: " + used.map { "\($0.wrong)→\($0.right)" }.joined(separator: ", ")) }
            let (repaired, fixes) = TextRules.repairAsciiWords(fixed, terms: dict + devTerms + store.rightSides)
            if !fixes.isEmpty { print("words repaired: " + fixes.map { "\($0.0)→\($0.1)" }.joined(separator: ", ")) }
            fixed = TextRules.spaceBetweenHanAndLatin(repaired)
            if fixed != raw { print("after rules:"); print(fixed) }
            return fixed
        }
        func polishAndPrint(raw: String) async {
            let t = Date()
            let (out, used) = await Polisher.polish(PolishRequest(raw: raw, tone: tone, outputLanguage: lang, dictionary: dict, appName: app, speechLocale: locale, corrections: store.items))
            print("polished (\(used ? "on-device model" : "rules"), \(String(format: "%.2f", Date().timeIntervalSince(t)))s, tone=\(tone.rawValue), lang=\(lang.rawValue)):")
            print(out)
        }

        // Keep the main run loop alive so main-queue callbacks (UI updates) can run while we wait.
        var code: Int32 = 0
        var finished = false
        Task {
            defer { finished = true }
            do {
                if let pair = value("--learn", in: args) {
                    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { print("格式：--learn \"錯的=對的\""); code = 2; return }
                    let ok = store.learn(wrong: parts[0], right: parts[1])
                    print(ok ? "learned: \(parts[0]) → \(parts[1])" : "rejected (too short or identical): \(parts[0])")
                    if !ok { code = 1 }
                } else if let i = args.firstIndex(of: "--learn-diff"), i + 2 < args.count {
                    let reps = TextDiff.replacements(old: args[i + 1], new: args[i + 2])
                    for r in reps { print("diff: \(r.wrong) → \(r.right) \(store.learn(wrong: r.wrong, right: r.right) ? "(learned)" : "(rejected)")") }
                    if reps.isEmpty { print("no learnable replacement") }
                } else if args.contains("--corrections") {
                    for c in store.items { print("\(c.wrong) → \(c.right)  ×\(c.count)") }
                    print("(\(store.items.count) corrections in \(store.url.path))")
                } else if args.contains("--check-update") {
                    let latest = try await Updater.fetchLatest()
                    let current = Updater.currentVersion
                    print("current:", current?.description ?? "dev (not an app bundle)")
                    print("latest:", latest.tag, latest.zipURL.absoluteString, "sha256:", latest.shaURL != nil)
                    if let current { print(current < latest.version ? "update available" : "up to date") }
                } else if args.contains("--update") {
                    guard let targetPath = value("--target", in: args) else { print("用法：--update --target <HearMe.app>"); code = 2; return }
                    let target = URL(fileURLWithPath: targetPath)
                    let installedVersion = (NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
                    let latest = try await Updater.fetchLatest()
                    print("target:", target.path, "version:", installedVersion?.description ?? "?", "latest:", latest.tag)
                    if let installedVersion, !(installedVersion < latest.version), !args.contains("--force") { print("up to date"); return }
                    let t = Date()
                    try await Updater.install(latest, over: target) { print("  \($0)") }
                    let after = NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String ?? "?"
                    print("installed \(latest.tag) → Info.plist says \(after) (\(String(format: "%.1f", Date().timeIntervalSince(t)))s)")
                } else if args.contains("--doctor") {
                    print("macOS:", ProcessInfo.processInfo.operatingSystemVersionString)
                    print("accessibility:", Permissions.accessibilityTrusted(prompt: false))
                    print("microphone:", Permissions.microphoneStatus, "input device:", AudioCapture.hasInputDevice())
                    print("on-device model:", Polisher.availability)
                    print("speech locales installed:", await SpeechLocaleProbe.installed())
                    print("history:", History.shared.url.path)
                    print("log:", Log.fileURL.path)
                } else if let path = value("--transcribe", in: args) {
                    let t = Date()
                    let outcome = try await Transcriber.transcribeFile(URL(fileURLWithPath: path), localeId: locale, secondaryLocaleId: locale2, contextualStrings: dict + store.rightSides)
                    var raw = outcome.text
                    if outcome.alternatives.count > 1 {
                        for a in outcome.alternatives { print("  [\(a.localeId)] confidence \(String(format: "%.2f", a.confidence)): \(a.text)") }
                    }
                    locale = outcome.localeId
                    print("transcript (\(locale), \(String(format: "%.2f", Date().timeIntervalSince(t)))s):")
                    print(raw)
                    raw = applyCorrections(raw)
                    if args.contains("--polish") { await polishAndPrint(raw: raw) }
                } else if let path = value("--simulate-live", in: args) {
                    // Push a file through the live (microphone) path in mic-sized chunks.
                    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
                    let t = Transcriber()
                    var updates = 0
                    t.onUpdate = { f, v in updates += 1; if Log.verbose { print("  update #\(updates): [\(f)] + [\(v)]") } }
                    let t0 = Date()
                    try await t.start(localeId: locale, secondaryLocaleId: locale2, contextualStrings: dict)
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
                    let outcome = await withTimeout(8) { await t.finish() }
                    print("fed \(fed) chunks, \(updates) live updates, finish took \(String(format: "%.2f", Date().timeIntervalSince(t1)))s\(outcome == nil ? " (TIMEOUT)" : "")")
                    if let o = outcome, o.alternatives.count > 1 {
                        for a in o.alternatives { print("  [\(a.localeId)] confidence \(String(format: "%.2f", a.confidence)): \(a.text)") }
                        locale = o.localeId
                    }
                    print("transcript (\(locale)):")
                    print(outcome?.text ?? t.currentText)
                    let fixed = applyCorrections(outcome?.text ?? t.currentText)
                    if args.contains("--polish") { await polishAndPrint(raw: fixed) }
                } else if let raw = value("--polish-text", in: args) {
                    print("raw:")
                    print(raw)
                    await polishAndPrint(raw: applyCorrections(raw))
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
