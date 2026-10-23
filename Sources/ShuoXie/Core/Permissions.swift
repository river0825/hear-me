import AppKit
import AVFoundation
import ApplicationServices

enum Permissions {
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static var microphoneStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "已允許"
        case .denied: return "被拒絕"
        case .restricted: return "受限"
        case .notDetermined: return "尚未詢問"
        @unknown default: return "未知"
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
