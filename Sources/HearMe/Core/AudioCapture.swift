import AVFoundation

enum CaptureError: LocalizedError {
    case noInputDevice
    case microphoneDenied
    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "這台電腦沒有麥克風輸入裝置"
        case .microphoneDenied: return "沒有麥克風權限（系統設定 → 隱私權與安全性 → 麥克風）"
        }
    }
}

/// Microphone capture via AVAudioEngine; hands raw buffers to the caller.
final class AudioCapture {
    private var engine: AVAudioEngine?

    static func hasInputDevice() -> Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) async throws -> AVAudioFormat {
        guard Self.hasInputDevice() else { throw CaptureError.noInputDevice }
        guard await Self.requestPermission() else { throw CaptureError.microphoneDenied }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInputDevice }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            onBuffer(buffer, time)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        return format
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}
