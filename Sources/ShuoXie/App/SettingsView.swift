import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var dictionaryText: String
    @State private var newBundleId = ""
    @State private var newTone: Tone = .general

    init(settings: Settings) {
        self.settings = settings
        _dictionaryText = State(initialValue: settings.dictionary.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("快捷鍵") {
                Picker("按住說話", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) }
                }
                Text("按住說、放開就貼上；快速點一下會一直聽，再點一下結束。按住 ⇧ 加快捷鍵＝對選取的文字下指令。\n用 fn 鍵時，建議到「系統設定 → 鍵盤 → 按下 🌐 鍵時」改成「不做任何動作」。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("語音") {
                Picker("辨識語言", selection: $settings.speechLocale) {
                    ForEach(SpeechLocaleOption.all) { Text($0.label).tag($0.id) }
                }
                Text("辨識與整理都在這台電腦上完成，不會上傳。第一次用某個語言會先下載模型。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("整理") {
                Toggle("用 AI 整理（去填充詞、改口只留最後、補標點、自動條列）", isOn: $settings.polishEnabled)
                Picker("預設語氣", selection: $settings.defaultTone) {
                    ForEach(Tone.allCases) { Text($0.label).tag($0) }
                }
                Picker("輸出語言", selection: $settings.outputLanguage) {
                    ForEach(OutputLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle("貼上後把剪貼簿還原", isOn: $settings.restoreClipboard)
                LabeledContent("裝置端模型") { Text(Polisher.availability).foregroundStyle(.secondary) }
            }
            Section("個人字典（一行一個：人名、產品、術語）") {
                TextEditor(text: $dictionaryText)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .onChange(of: dictionaryText) { _, new in
                        settings.dictionary = new.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
            }
            Section("每個 app 不同語氣（bundle id → 語氣；結尾是「.」的當成前綴）") {
                ForEach($settings.appTones) { $rule in
                    HStack {
                        TextField("bundle id", text: $rule.bundleId).font(.body.monospaced())
                        Picker("", selection: $rule.tone) { ForEach(Tone.allCases) { Text($0.label).tag($0) } }
                            .labelsHidden().frame(width: 220)
                        Button(role: .destructive) {
                            settings.appTones.removeAll { $0.id == rule.id }
                        } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("新增 bundle id，例如 com.apple.Notes", text: $newBundleId).font(.body.monospaced())
                    Picker("", selection: $newTone) { ForEach(Tone.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: 220)
                    Button {
                        let id = newBundleId.trimmingCharacters(in: .whitespaces)
                        guard !id.isEmpty else { return }
                        settings.appTones.append(AppToneRule(bundleId: id, tone: newTone))
                        newBundleId = ""
                    } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless)
                }
                Button("恢復預設清單") { settings.appTones = Settings.defaultAppTones }
                Text("目前最前面的 app：\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "—")").font(.caption).foregroundStyle(.secondary)
            }
            Section("記錄") {
                LabeledContent("聽寫記錄檔（只存在本機）") {
                    Button("在 Finder 顯示") { NSWorkspace.shared.activateFileViewerSelecting([History.shared.url]) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 720)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: Settings) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            w.title = "說寫 設定"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
