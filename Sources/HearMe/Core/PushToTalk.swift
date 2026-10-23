import Foundation

enum PTTAction: Equatable { case start, stop, none }

/// Hold-to-talk with a tap-to-latch escape hatch:
/// - hold the key, speak, release → start / stop
/// - tap the key (shorter than `tapThreshold`) → keeps listening until the next tap
struct PushToTalkMachine {
    var tapThreshold: TimeInterval = 0.35
    private(set) var recording = false
    private(set) var latched = false
    private var pressTime: TimeInterval?

    mutating func press(at t: TimeInterval) -> PTTAction {
        if recording && latched {
            recording = false
            latched = false
            pressTime = nil
            return .stop
        }
        if recording { return .none }
        recording = true
        pressTime = t
        return .start
    }

    mutating func release(at t: TimeInterval) -> PTTAction {
        guard recording, let p = pressTime else { return .none }
        pressTime = nil
        if t - p < tapThreshold {
            latched = true
            return .none
        }
        recording = false
        return .stop
    }

    /// Called when the pipeline stops for another reason (error, menu).
    mutating func reset() {
        recording = false
        latched = false
        pressTime = nil
    }
}
