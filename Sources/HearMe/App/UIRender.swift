import AppKit
import SwiftUI

/// Renders the HUD states and the settings window to PNG files without putting anything on screen.
/// Used for evidence on machines where screen capture is not permitted.
@MainActor
enum UIRender {
    static func render(to dir: URL, settings: Settings) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [URL] = []
        let pipeline = Pipeline(settings: settings)
        let samples: [(String, PipelineState, String, String)] = [
            ("hud-listening", .listening(mode: .dictate), "這次發版要做三件事第一更新登入頁第二", "修掉那個"),
            ("hud-command", .listening(mode: .command), "幫我翻成英文", ""),
            ("hud-polishing", .polishing, "這次發版要做三件事第一更新登入頁第二修掉那個那個閃退的問題第三寫 release notes", ""),
            ("hud-done", .done("這次發版要做三件事：\n1. 更新登入頁\n2. 修掉閃退的問題\n3. 寫 release notes"), "", ""),
            ("hud-error", .error("這台電腦沒有麥克風輸入裝置"), "", ""),
        ]
        for (name, state, final, volatile) in samples {
            pipeline.debugSet(state: state, finalText: final, volatileText: volatile)
            let view = NSHostingView(rootView: HUDView(pipeline: pipeline))
            written.append(try snapshot(view, to: dir.appendingPathComponent("\(name).png")))
        }
        let settingsView = NSHostingView(rootView: SettingsView(settings: settings))
        written.append(try snapshot(settingsView, to: dir.appendingPathComponent("settings.png")))
        return written
    }

    private static func snapshot(_ view: NSView, to url: URL) throws -> URL {
        view.layoutSubtreeIfNeeded()
        var size = view.fittingSize
        if size.width < 1 || size.height < 1 { size = NSSize(width: 620, height: 720) }
        view.frame = NSRect(origin: .zero, size: size)
        // A window gives the view a backing store and the system appearance; it is never ordered front.
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "HearMe", code: 2, userInfo: [NSLocalizedDescriptionKey: "no bitmap rep"])
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "HearMe", code: 3, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
        }
        try png.write(to: url)
        return url
    }
}
