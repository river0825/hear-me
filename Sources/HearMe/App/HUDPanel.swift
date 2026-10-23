import AppKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var pipeline: Pipeline

    private var dotColor: Color {
        switch pipeline.state {
        case .idle: return .gray
        case .listening: return .red
        case .polishing: return .orange
        case .done: return .green
        case .error: return .yellow
        }
    }

    private var headline: String {
        switch pipeline.state {
        case .idle: return ""
        case .listening(let mode): return mode == .command ? "說出要對選取文字做什麼…" : "聽寫中…"
        case .polishing: return "整理中…"
        case .done: return "已貼上"
        case .error(let m): return m
        }
    }

    private var body_text: String {
        switch pipeline.state {
        case .listening, .polishing:
            let s = pipeline.finalText + pipeline.volatileText
            return s.isEmpty ? "" : String(s.suffix(90))
        case .done(let t): return String(t.prefix(120))
        default: return ""
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(dotColor).frame(width: 10, height: 10).padding(.top, 5)
                .modifier(PulseIfListening(active: pipeline.isListening))
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(.system(size: 13, weight: .semibold))
                if !body_text.isEmpty {
                    Text(body_text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }
}

struct PulseIfListening: ViewModifier {
    let active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(active ? (on ? 0.35 : 1) : 1)
            .animation(active ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { on = true }
    }
}

/// Small floating, non-activating panel near the bottom of the active screen.
@MainActor
final class HUDPanel {
    private let panel: NSPanel
    private let hosting: NSHostingView<HUDView>

    init(pipeline: Pipeline) {
        hosting = NSHostingView(rootView: HUDView(pipeline: pipeline))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
    }

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.minY + 56
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func relayout() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let origin = panel.frame.origin
        let midX = panel.frame.midX
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: midX - size.width / 2, y: origin.y))
    }

    func hide() { panel.orderOut(nil) }
}
