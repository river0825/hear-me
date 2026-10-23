import Foundation
import Combine

/// Writing tone applied by the polisher. `verbatim` skips the language model entirely.
enum Tone: String, CaseIterable, Codable, Identifiable {
    case general, formal, casual, verbatim
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return "一般"
        case .formal: return "正式"
        case .casual: return "口語"
        case .verbatim: return "照打（只去填充詞，不用 AI）"
        }
    }
    var promptDescription: String {
        switch self {
        case .general: return "自然、清楚，像平常打字的語氣。"
        case .formal: return "正式、有禮貌，適合寄給客戶或主管的信件；稱謂用「您」。"
        case .casual: return "輕鬆口語，像傳訊息給朋友；可以保留語助詞但不要囉嗦。"
        case .verbatim: return "完全照原文。"
        }
    }
}

enum HotkeyChoice: String, CaseIterable, Codable, Identifiable {
    case fn, rightOption, rightCommand
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: return "fn／🌐 鍵"
        case .rightOption: return "右邊 ⌥ Option"
        case .rightCommand: return "右邊 ⌘ Command"
        }
    }
}

enum OutputLanguage: String, CaseIterable, Codable, Identifiable {
    case same, english, japanese, traditionalChinese
    var id: String { rawValue }
    var label: String {
        switch self {
        case .same: return "跟說的一樣"
        case .english: return "翻成英文"
        case .japanese: return "翻成日文"
        case .traditionalChinese: return "翻成台灣正體中文"
        }
    }
    var promptDescription: String? {
        switch self {
        case .same: return nil
        case .english: return "English, phrased the way a native speaker would write it."
        case .japanese: return "自然な日本語。"
        case .traditionalChinese: return "台灣正體中文，用台灣用語。"
        }
    }
}

struct AppToneRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleId: String
    var tone: Tone
}

struct SpeechLocaleOption: Identifiable {
    let id: String
    let label: String
    static let all: [SpeechLocaleOption] = [
        .init(id: "zh_TW", label: "中文（台灣）"),
        .init(id: "zh_CN", label: "中文（中國）"),
        .init(id: "zh_HK", label: "中文（香港）"),
        .init(id: "en_US", label: "English (US)"),
        .init(id: "en_GB", label: "English (UK)"),
        .init(id: "ja_JP", label: "日本語"),
    ]
}

/// Pure lookup so it can be unit-tested without UserDefaults.
enum ToneResolver {
    static func tone(forBundleId bundleId: String?, rules: [AppToneRule], fallback: Tone) -> Tone {
        guard let bundleId else { return fallback }
        if let exact = rules.first(where: { $0.bundleId.caseInsensitiveCompare(bundleId) == .orderedSame }) {
            return exact.tone
        }
        // Allow prefix rules like "com.microsoft." to cover a family of apps.
        if let prefix = rules.first(where: { $0.bundleId.hasSuffix(".") && bundleId.lowercased().hasPrefix($0.bundleId.lowercased()) }) {
            return prefix.tone
        }
        return fallback
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    static let defaultAppTones: [AppToneRule] = [
        .init(bundleId: "com.apple.mail", tone: .formal),
        .init(bundleId: "com.microsoft.Outlook", tone: .formal),
        .init(bundleId: "com.apple.MobileSMS", tone: .casual),
        .init(bundleId: "jp.naver.line.mac", tone: .casual),
        .init(bundleId: "ru.keepcoder.Telegram", tone: .casual),
        .init(bundleId: "com.tinyspeck.slackmacgap", tone: .casual),
        .init(bundleId: "com.hnc.Discord", tone: .casual),
        .init(bundleId: "com.apple.Terminal", tone: .verbatim),
        .init(bundleId: "com.googlecode.iterm2", tone: .verbatim),
        .init(bundleId: "com.microsoft.VSCode", tone: .verbatim),
        .init(bundleId: "com.todesktop.230313mzl4w4u92", tone: .verbatim), // Cursor
        .init(bundleId: "com.apple.dt.Xcode", tone: .verbatim),
    ]

    private let defaults: UserDefaults
    private var saving = false

    @Published var hotkey: HotkeyChoice { didSet { save() } }
    @Published var speechLocale: String { didSet { save() } }
    @Published var polishEnabled: Bool { didSet { save() } }
    @Published var defaultTone: Tone { didSet { save() } }
    @Published var outputLanguage: OutputLanguage { didSet { save() } }
    @Published var restoreClipboard: Bool { didSet { save() } }
    @Published var dictionary: [String] { didSet { save() } }
    @Published var appTones: [AppToneRule] { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkey = HotkeyChoice(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .fn
        speechLocale = defaults.string(forKey: "speechLocale") ?? "zh_TW"
        polishEnabled = defaults.object(forKey: "polishEnabled") as? Bool ?? true
        defaultTone = Tone(rawValue: defaults.string(forKey: "defaultTone") ?? "") ?? .general
        outputLanguage = OutputLanguage(rawValue: defaults.string(forKey: "outputLanguage") ?? "") ?? .same
        restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        dictionary = defaults.stringArray(forKey: "dictionary") ?? []
        if let data = defaults.data(forKey: "appTones"), let rules = try? JSONDecoder().decode([AppToneRule].self, from: data) {
            appTones = rules
        } else {
            appTones = Settings.defaultAppTones
        }
    }

    func tone(forBundleId bundleId: String?) -> Tone {
        ToneResolver.tone(forBundleId: bundleId, rules: appTones, fallback: defaultTone)
    }

    private func save() {
        defaults.set(hotkey.rawValue, forKey: "hotkey")
        defaults.set(speechLocale, forKey: "speechLocale")
        defaults.set(polishEnabled, forKey: "polishEnabled")
        defaults.set(defaultTone.rawValue, forKey: "defaultTone")
        defaults.set(outputLanguage.rawValue, forKey: "outputLanguage")
        defaults.set(restoreClipboard, forKey: "restoreClipboard")
        defaults.set(dictionary, forKey: "dictionary")
        defaults.set(try? JSONEncoder().encode(appTones), forKey: "appTones")
    }
}
