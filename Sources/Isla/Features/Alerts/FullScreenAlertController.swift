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
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { ctl.dismiss() }
            card
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
                .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appeared = true } }
        }
        .preferredColorScheme(.dark)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(alert.accent.opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: alert.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(alert.accent)
                }
                Text(alert.eyebrow).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let countdown = alert.countdown {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(countdown())
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(alert.accent)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(alert.accent.opacity(0.14), in: Capsule())
                    }
                }
            }
            .padding(.bottom, 22)

            Text(alert.title)
                .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-0.4)
                .lineLimit(2).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail = alert.detail {
                Text(detail).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(2).padding(.top, 6)
            }
            if let footnote = alert.footnote {
                Text(footnote).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).padding(.top, 10)
            }

            HStack(spacing: 10) {
                ForEach(alert.actions.filter { $0.style == .quiet }) { a in AlertButton(action: a, accent: alert.accent) }
                Spacer(minLength: 0)
                ForEach(alert.actions.filter { $0.style != .quiet }) { a in AlertButton(action: a, accent: alert.accent) }
            }
            .padding(.top, 28)
        }
        .padding(30)
        .frame(width: 560)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.55))
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [alert.accent.opacity(0), alert.accent, alert.accent.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1.5).padding(.horizontal, 60).offset(y: 0.5)
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
        .shadow(color: alert.accent.opacity(0.15), radius: 80, y: 0)
    }
}

private struct AlertButton: View {
    let action: FullScreenAlert.Action
    let accent: Color
    @ObservedObject var ctl = FullScreenAlertController.shared
    @State private var hover = false

    var body: some View {
        let primary = action.style == .primary
        let quiet = action.style == .quiet
        Button { ctl.perform(action) } label: {
            HStack(spacing: 7) {
                if let s = action.symbol { Image(systemName: s).font(.system(size: 13, weight: .semibold)) }
                Text(action.title).font(.system(size: 14, weight: primary ? .semibold : .medium))
                if let hint = action.hint {
                    Text(hint).font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5).frame(height: 17)
                        .background((primary ? Color.black : Color.white).opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(primary ? .black : .white.opacity(quiet ? 0.65 : 0.92))
            .padding(.horizontal, primary ? 18 : 14).frame(height: 40)
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
