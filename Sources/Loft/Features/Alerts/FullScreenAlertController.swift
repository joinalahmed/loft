import AppKit
import SwiftUI
import Combine

/// One full-screen, every-display alert style shared by meetings, timers and reminders.
struct FullScreenAlert: Identifiable {
    struct Action: Identifiable {
        enum Style { case primary, secondary, quiet }
        let id = UUID()
        var title: String
        var symbol: String?
        var style: Style = .secondary
        var key: KeyEquivalent?
        var hint: String?            // shown as a small key cap, e.g. "↩", "S", "esc"
        var handler: () -> Void
    }
    let id = UUID()
    var eyebrow: String              // "Work calendar", "Focus session", "Reminders · Personal"
    var accent: Color
    var symbol: String
    var title: String
    var detail: String?
    var footnote: String?
    var countdown: (() -> String)?   // live text at the top right, refreshed every second
    var actions: [Action]
    var autoDismiss: TimeInterval = 90
}

@MainActor
final class FullScreenAlertController: ObservableObject {
    static let shared = FullScreenAlertController()
    @Published private(set) var current: FullScreenAlert?
    private var windows: [NSWindow] = []
    private var autoDismiss: Task<Void, Never>?
    private init() {}

    func show(_ alert: FullScreenAlert) {
        dismiss(animated: false)
        current = alert
        for screen in NSScreen.screens {
            let w = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .mainMenu + 2
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: FullScreenAlertView(alert: alert))
            w.alphaValue = 0
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        // Key status lets ↩ / S / esc work immediately; the panel is non-activating so typing focus is restored on dismiss.
        windows.first?.makeKey()
        autoDismiss?.cancel()
        autoDismiss = Task { [weak self] in
            try? await Task.sleep(for: .seconds(alert.autoDismiss))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func perform(_ action: FullScreenAlert.Action) {
        dismiss()
        action.handler()
    }

    func dismiss(animated: Bool = true) {
        autoDismiss?.cancel()
        let ws = windows
        windows.removeAll()
        current = nil
        guard animated else { ws.forEach { $0.close() }; return }
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.18; ws.forEach { $0.animator().alphaValue = 0 } },
                                            completionHandler: { ws.forEach { $0.close() } })
    }
}

struct FullScreenAlertView: View {
    let alert: FullScreenAlert
    @ObservedObject var ctl = FullScreenAlertController.shared
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            // Full-bleed takeover: the whole display dims to a blurred black and the content
            // scales with the screen, so it cannot be missed and reads from across the room.
            let scale = max(0.85, min(1.6, geo.size.width / 1440))
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.78).ignoresSafeArea()
                RadialGradient(colors: [alert.accent.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.45)
                    .ignoresSafeArea().blendMode(.screen)
                content(scale: scale)
                    .frame(maxWidth: min(geo.size.width * 0.72, 1100))
                    .scaleEffect(appeared ? 1 : 0.96)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { ctl.dismiss() }
            .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true } }
        }
        .preferredColorScheme(.dark)
    }

    private func content(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12 * scale) {
                ZStack {
                    Circle().fill(alert.accent.opacity(0.18)).frame(width: 56 * scale, height: 56 * scale)
                    Image(systemName: alert.symbol).font(.system(size: 24 * scale, weight: .semibold)).foregroundStyle(alert.accent)
                }
                Text(alert.eyebrow).font(.system(size: 18 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                if let countdown = alert.countdown {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(countdown())
                            .font(.system(size: 18 * scale, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(alert.accent)
                            .padding(.horizontal, 14 * scale).frame(height: 34 * scale)
                            .background(alert.accent.opacity(0.14), in: Capsule())
                    }
                }
            }
            .padding(.bottom, 34 * scale)

            Text(alert.title)
                .font(.system(size: 64 * scale, weight: .bold, design: .rounded)).tracking(-1)
                .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.6)
            if let detail = alert.detail {
                Text(detail).font(.system(size: 24 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center).lineLimit(2).padding(.top, 14 * scale)
            }
            if let footnote = alert.footnote {
                Text(footnote).font(.system(size: 15 * scale, design: .monospaced)).foregroundStyle(.white.opacity(0.4)).lineLimit(1).padding(.top, 18 * scale)
            }

            HStack(spacing: 16 * scale) {
                ForEach(alert.actions.filter { $0.style == .quiet }) { a in AlertButton(action: a, accent: alert.accent, scale: scale) }
                ForEach(alert.actions.filter { $0.style != .quiet }) { a in AlertButton(action: a, accent: alert.accent, scale: scale) }
            }
            .padding(.top, 56 * scale)
        }
    }
}

private struct AlertButton: View {
    let action: FullScreenAlert.Action
    let accent: Color
    var scale: CGFloat = 1
    @ObservedObject var ctl = FullScreenAlertController.shared
    @State private var hover = false

    var body: some View {
        let primary = action.style == .primary
        let quiet = action.style == .quiet
        Button { ctl.perform(action) } label: {
            HStack(spacing: 9 * scale) {
                if let s = action.symbol { Image(systemName: s).font(.system(size: 17 * scale, weight: .semibold)) }
                Text(action.title).font(.system(size: 19 * scale, weight: primary ? .semibold : .medium))
                if let hint = action.hint {
                    Text(hint).font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6 * scale).frame(height: 22 * scale)
                        .background((primary ? Color.black : Color.white).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(primary ? .black : .white.opacity(quiet ? 0.65 : 0.92))
            .padding(.horizontal, (primary ? 28 : 22) * scale).frame(height: 56 * scale)
            .background {
                if primary { Capsule().fill(accent).brightness(hover ? 0.08 : 0) }
                else if !quiet || hover { Capsule().fill(.white.opacity(hover ? 0.16 : 0.10)) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .if(action.key != nil) { $0.keyboardShortcut(action.key!, modifiers: []) }
    }
}
