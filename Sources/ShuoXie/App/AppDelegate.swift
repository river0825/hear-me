import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared
    private(set) var pipeline: Pipeline!
    private var statusItem: NSStatusItem!
    private var hud: HUDPanel!
    private let hotkey = HotkeyMonitor()
    private var ptt = PushToTalkMachine()
    private let settingsWindow = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var hideTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        pipeline = Pipeline(settings: settings)
        hud = HUDPanel(pipeline: pipeline)
        setupStatusItem()
        bindPipeline()
        setupHotkey()
        warmUp()
        if ProcessInfo.processInfo.environment["SHUOXIE_DEMO"] == "1" {
            // Used to screenshot the HUD on a machine without a microphone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in pipeline.start(mode: .dictate) }
        }
    }

    // MARK: status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        rebuildMenu()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let (name, tint): (String, NSColor?) = {
            switch pipeline.state {
            case .idle: return ("mic", nil)
            case .listening: return ("mic.fill", .systemRed)
            case .polishing: return ("sparkles", .systemOrange)
            case .done: return ("checkmark.circle", .systemGreen)
            case .error: return ("exclamationmark.triangle", .systemYellow)
            }
        }()
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "說寫")
        image?.isTemplate = tint == nil
        button.image = image
        button.contentTintColor = tint
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let stateItem = NSMenuItem(title: stateLabel(), action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem(title: pipeline.isListening ? "停止聽寫" : "開始聽寫（按住 \(settings.hotkey.label) 也可以）", action: #selector(toggleDictation), keyEquivalent: ""))
        menu.addItem(.separator())

        let polish = NSMenuItem(title: "用 AI 整理", action: #selector(togglePolish), keyEquivalent: "")
        polish.state = settings.polishEnabled ? .on : .off
        menu.addItem(polish)

        let toneMenu = NSMenu()
        for tone in Tone.allCases {
            let item = NSMenuItem(title: tone.label, action: #selector(pickTone(_:)), keyEquivalent: "")
            item.representedObject = tone.rawValue
            item.state = settings.defaultTone == tone ? .on : .off
            toneMenu.addItem(item)
        }
        let toneItem = NSMenuItem(title: "預設語氣", action: nil, keyEquivalent: "")
        toneItem.submenu = toneMenu
        menu.addItem(toneItem)

        let langMenu = NSMenu()
        for lang in OutputLanguage.allCases {
            let item = NSMenuItem(title: lang.label, action: #selector(pickOutputLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.rawValue
            item.state = settings.outputLanguage == lang ? .on : .off
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "輸出語言", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(.separator())

        let recent = History.shared.recent(5)
        if !recent.isEmpty {
            let recentMenu = NSMenu()
            for e in recent {
                let title = String(e.output.replacingOccurrences(of: "\n", with: " ").prefix(48))
                let item = NSMenuItem(title: title, action: #selector(copyHistory(_:)), keyEquivalent: "")
                item.representedObject = e.output
                item.toolTip = "原始逐字稿：\(e.raw)"
                recentMenu.addItem(item)
            }
            let recentItem = NSMenuItem(title: "最近（點一下複製）", action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }

        menu.addItem(NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "檢查權限…", action: #selector(checkPermissions), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束說寫", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func stateLabel() -> String {
        switch pipeline.state {
        case .idle: return "說寫：待命"
        case .listening: return "說寫：聽寫中"
        case .polishing: return "說寫：整理中"
        case .done: return "說寫：已貼上"
        case .error(let m): return "說寫：\(m)"
        }
    }

    // MARK: bindings

    private func bindPipeline() {
        pipeline.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self else { return }
            self.updateIcon()
            self.rebuildMenu()
            self.hideTimer?.invalidate()
            switch state {
            case .idle:
                self.hud.hide()
                self.ptt.reset()
            case .listening, .polishing:
                self.hud.show()
            case .done, .error:
                self.hud.relayout()
                self.hud.show()
            }
        }.store(in: &cancellables)
        pipeline.$volatileText.merge(with: pipeline.$finalText).receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.hud.relayout()
        }.store(in: &cancellables)
        settings.$hotkey.receive(on: DispatchQueue.main).sink { [weak self] choice in
            self?.hotkey.choice = choice
            self?.rebuildMenu()
        }.store(in: &cancellables)
        settings.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }.store(in: &cancellables)
    }

    private func setupHotkey() {
        hotkey.choice = settings.hotkey
        hotkey.onPress = { [weak self] shift in
            guard let self else { return }
            switch ptt.press(at: Date().timeIntervalSinceReferenceDate) {
            case .start: pipeline.start(mode: shift ? .command : .dictate)
            case .stop: pipeline.stop()
            case .none: break
            }
        }
        hotkey.onRelease = { [weak self] in
            guard let self else { return }
            if ptt.release(at: Date().timeIntervalSinceReferenceDate) == .stop { pipeline.stop() }
        }
        if !Permissions.accessibilityTrusted(prompt: true) {
            Log.warn("Accessibility not granted yet; hotkey and paste will not work until it is.")
        }
        if !hotkey.start() {
            Log.warn("Could not install the hotkey monitor.")
        }
    }

    /// Download the speech model for the chosen language ahead of time so the first dictation is not slow.
    private func warmUp() {
        let locale = settings.speechLocale
        Task.detached {
            do { _ = try await Transcriber.makeModule(localeId: locale, progressive: true) }
            catch { Log.warn("warm-up failed: \(error)") }
        }
    }

    // MARK: actions

    @objc private func toggleDictation() {
        if pipeline.isListening { ptt.reset(); pipeline.stop() } else { ptt.reset(); pipeline.start(mode: .dictate) }
    }
    @objc private func togglePolish() { settings.polishEnabled.toggle() }
    @objc private func pickTone(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let t = Tone(rawValue: raw) { settings.defaultTone = t }
    }
    @objc private func pickOutputLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let l = OutputLanguage(rawValue: raw) { settings.outputLanguage = l }
    }
    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    @objc private func openSettings() { settingsWindow.show(settings: settings) }

    @objc private func checkPermissions() {
        let ax = Permissions.accessibilityTrusted(prompt: false)
        let lines = [
            "輔助使用（快捷鍵與貼上）：\(ax ? "已允許" : "未允許")",
            "麥克風：\(Permissions.microphoneStatus)\(AudioCapture.hasInputDevice() ? "" : "（這台電腦沒有輸入裝置）")",
            "裝置端整理模型：\(Polisher.availability)",
            "辨識語言：\(settings.speechLocale)",
        ]
        let alert = NSAlert()
        alert.messageText = "說寫 權限檢查"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        if !ax { alert.addButton(withTitle: "打開輔助使用設定") }
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn { Permissions.openAccessibilitySettings() }
    }
}
