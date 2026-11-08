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
            // Full-screen takeover: the display dims behind a frosted glass sheet that scales
            // with the screen, so the alert cannot be missed and reads from across the room.
            let scale = max(0.85, min(1.5, geo.size.width / 1440))
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.62).ignoresSafeArea()
                RadialGradient(colors: [alert.accent.opacity(0.32), .clear], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: geo.size.width * 0.5)
                    .ignoresSafeArea().blendMode(.screen)
                sheet(scale: scale)
                    .frame(maxWidth: min(geo.size.width * 0.62, 820 * scale))
                    .scaleEffect(appeared ? 1 : 0.94)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { ctl.dismiss() }
            .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { appeared = true } }
        }
        .preferredColorScheme(.dark)
    }

    private func sheet(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12 * scale) {
                ZStack {
                    Circle().fill(alert.accent.opacity(0.22))
                    Circle().strokeBorder(alert.accent.opacity(0.5), lineWidth: 1)
                    Image(systemName: alert.symbol).font(.system(size: 20 * scale, weight: .semibold)).foregroundStyle(alert.accent)
                }
                .frame(width: 46 * scale, height: 46 * scale)
                Text(alert.eyebrow).font(.system(size: 16 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                Spacer(minLength: 8)
                if let countdown = alert.countdown {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 8 * scale) {
                            Circle().fill(alert.accent).frame(width: 7 * scale, height: 7 * scale)
                                .opacity(Int(ctx.date.timeIntervalSince1970) % 2 == 0 ? 1 : 0.35)
                                .animation(.easeInOut(duration: 0.8), value: Int(ctx.date.timeIntervalSince1970))
                            Text(countdown())
                                .font(.system(size: 16 * scale, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(alert.accent)
                        }
                        .padding(.horizontal, 14 * scale).frame(height: 34 * scale)
                        .glass(Capsule(), tint: alert.accent, strength: 1.1)
                    }
                }
            }
            .padding(.bottom, 30 * scale)

            Text(alert.title)
                .font(.system(size: 50 * scale, weight: .bold, design: .rounded)).tracking(-0.8)
                .lineLimit(3).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = alert.detail {
                Text(detail).font(.system(size: 21 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2).padding(.top, 12 * scale)
            }
            if let footnote = alert.footnote {
                HStack(spacing: 6 * scale) {
                    Image(systemName: "link").font(.system(size: 11 * scale, weight: .semibold))
                    Text(footnote).font(.system(size: 13 * scale, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 10 * scale).frame(height: 26 * scale)
                .glass(Capsule(), strength: 0.7)
                .padding(.top, 18 * scale)
            }

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, 28 * scale)

            HStack(spacing: 12 * scale) {
                ForEach(alert.actions.filter { $0.style == .quiet }) { a in AlertButton(action: a, accent: alert.accent, scale: scale) }
                Spacer(minLength: 0)
                ForEach(alert.actions.filter { $0.style != .quiet }) { a in AlertButton(action: a, accent: alert.accent, scale: scale) }
            }
        }
        .padding(40 * scale)
        .glass(RoundedRectangle(cornerRadius: 34 * scale, style: .continuous), tint: alert.accent, strength: 1.25)
        .shadow(color: .black.opacity(0.45), radius: 40 * scale, y: 20 * scale)
        .onTapGesture { }   // taps on the sheet do not dismiss
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
                if let s = action.symbol { Image(systemName: s).font(.system(size: 16 * scale, weight: .semibold)) }
                Text(action.title).font(.system(size: 18 * scale, weight: primary ? .semibold : .medium))
                if let hint = action.hint {
                    Text(hint).font(.system(size: 11.5 * scale, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6 * scale).frame(height: 21 * scale)
                        .background((primary ? Color.black : Color.white).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(primary ? Color.black.opacity(0.9) : .white.opacity(quiet ? (hover ? 0.95 : 0.65) : 0.94))
            .padding(.horizontal, (primary ? 26 : 20) * scale).frame(height: 52 * scale)
            .background {
                if primary {
                    Capsule().fill(accent)
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center))
                    Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.75)
                    if hover { Capsule().fill(.white.opacity(0.08)) }
                } else if !quiet {
                    Color.clear.glass(Capsule(), strength: hover ? 1.4 : 1.05, interactive: true)
                } else if hover {
                    Capsule().fill(.white.opacity(0.08))
                }
            }
            .shadow(color: primary ? accent.opacity(0.45) : .clear, radius: 14 * scale, y: 4 * scale)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.smooth(duration: 0.15), value: hover)
        .if(action.key != nil) { $0.keyboardShortcut(action.key!, modifiers: []) }
    }
}
