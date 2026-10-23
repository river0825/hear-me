import AppKit
import SwiftUI

/// "更正上一次聽寫": select the wrong span in the recognized text, type what it should have been.
struct CorrectionView: View {
    @ObservedObject var store: CorrectionStore
    @ObservedObject var settings: Settings
    @State private var rawText: String
    @State private var selection: TextSelection? = nil
    @State private var wrong = ""
    @State private var right = ""
    @State private var addToDictionary = true
    @State private var message = ""

    init(store: CorrectionStore, settings: Settings, lastRaw: String) {
        self.store = store
        self.settings = settings
        _rawText = State(initialValue: lastRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("上一次聽寫辨識出來的原文（在裡面圈選錯的部分）").font(.headline)
            TextEditor(text: $rawText, selection: $selection)
                .font(.system(size: 14))
                .frame(minHeight: 110)
                .onChange(of: selection) { _, new in
                    if let s = new, case .selection(let range) = s.indices, !range.isEmpty {
                        wrong = String(rawText[range])
                    }
                }
            HStack {
                TextField("辨識錯的（圈選會自動帶入）", text: $wrong)
                Text("→")
                TextField("正確的寫法", text: $right)
                Button("記住") { save() }.keyboardShortcut(.defaultAction).disabled(wrong.isEmpty || right.isEmpty)
            }
            Toggle("同時把正確寫法加進個人字典（讓辨識器偏向這個詞）", isOn: $addToDictionary)
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            Divider()
            Text("已記住的更正（之後逐字稿一出來就先替換，也會告訴整理模型）").font(.headline)
            if store.items.isEmpty {
                Text("還沒有。").foregroundStyle(.secondary)
            }
            List {
                ForEach(store.items.sorted { $0.date > $1.date }) { c in
                    HStack {
                        Text(c.wrong).font(.body.monospaced())
                        Text("→").foregroundStyle(.secondary)
                        Text(c.right).font(.body.monospaced())
                        Spacer()
                        Text("×\(c.count)").foregroundStyle(.secondary)
                        Button(role: .destructive) { store.remove(id: c.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 160)
            Text("太短的片段（中文 1 個字、英文 2 個字母以內）不會被記住，因為全域替換會誤傷。圈選時多帶一兩個字，例如「登入業」→「登入頁」。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 560, height: 560)
    }

    private func save() {
        if store.learn(wrong: wrong, right: right) {
            if addToDictionary, !settings.dictionary.contains(right) { settings.dictionary.append(right) }
            message = "記住了：「\(wrong)」→「\(right)」"
            wrong = ""; right = ""
        } else {
            message = "「\(wrong)」太短或跟正確寫法一樣，沒有記。請多圈一兩個字。"
        }
    }
}

@MainActor
final class CorrectionWindowController {
    private var window: NSWindow?

    func show(store: CorrectionStore, settings: Settings, lastRaw: String) {
        let view = CorrectionView(store: store, settings: settings, lastRaw: lastRaw)
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Hear Me 更正上一次聽寫"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
