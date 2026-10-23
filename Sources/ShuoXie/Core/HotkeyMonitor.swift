import AppKit
import CoreGraphics

/// Watches modifier-key changes system-wide (fn / right ⌥ / right ⌘) through a CGEvent tap.
/// Needs Accessibility (or Input Monitoring) permission; see `Permissions`.
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false
    private var globalMonitor: Any?

    var choice: HotkeyChoice = .fn
    /// shift: whether ⇧ was held together with the hotkey (command-on-selection mode)
    var onPress: ((_ shift: Bool) -> Void)?
    var onRelease: (() -> Void)?

    private static let rightOptionKey: Int64 = 61
    private static let rightCommandKey: Int64 = 54

    func start() -> Bool {
        if tap != nil || globalMonitor != nil { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let t = monitor.tap { CGEvent.tapEnable(tap: t, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                monitor.handle(flags: event.flags, keyCode: event.getIntegerValueField(.keyboardEventKeycode))
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) {
            self.tap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        // Fallback: NSEvent global monitor (also needs Accessibility, but works without Input Monitoring on some setups).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)), keyCode: Int64(event.keyCode))
        }
        return globalMonitor != nil
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
    }

    func handle(flags: CGEventFlags, keyCode: Int64) {
        let down: Bool
        switch choice {
        case .fn:
            down = flags.contains(.maskSecondaryFn)
        case .rightOption:
            guard keyCode == Self.rightOptionKey else { return }
            down = flags.contains(.maskAlternate)
        case .rightCommand:
            guard keyCode == Self.rightCommandKey else { return }
            down = flags.contains(.maskCommand)
        }
        guard down != isDown else { return }
        isDown = down
        let shift = flags.contains(.maskShift)
        DispatchQueue.main.async { [self] in
            if down { onPress?(shift) } else { onRelease?() }
        }
    }
}
