import AppKit
import CoreGraphics

/// Puts text into whatever app is in front by pasting it, then restores the clipboard.
enum TextInjector {
    private static let keyV: CGKeyCode = 9
    private static let keyC: CGKeyCode = 8

    struct ClipboardSnapshot {
        let items: [NSPasteboardItem]
        static func take() -> ClipboardSnapshot {
            let items = (NSPasteboard.general.pasteboardItems ?? []).map { item -> NSPasteboardItem in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) { copy.setData(data, forType: type) }
                }
                return copy
            }
            return ClipboardSnapshot(items: items)
        }
        func restore() {
            let pb = NSPasteboard.general
            pb.clearContents()
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }

    static func paste(_ text: String, restoreClipboard: Bool) {
        let snapshot = restoreClipboard ? ClipboardSnapshot.take() : nil
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        postKey(keyV, flags: .maskCommand)
        if let snapshot {
            // Give the target app time to read the pasteboard before we put the old contents back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { snapshot.restore() }
        }
    }

    /// Copy the current selection via ⌘C and return it. Clipboard is restored afterwards.
    static func copySelection() async -> String? {
        let snapshot = ClipboardSnapshot.take()
        let pb = NSPasteboard.general
        pb.clearContents()
        let before = pb.changeCount
        postKey(keyC, flags: .maskCommand)
        var text: String?
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pb.changeCount != before, let s = pb.string(forType: .string) { text = s; break }
        }
        snapshot.restore()
        return text
    }

    static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
