import AppKit
import SwiftUI
import EventKit
import Combine

/// Full-screen meeting reminder on every display, Notchy-style: dimmed backdrop, big card,
/// Join / Snooze / Dismiss. Non-activating so it never steals typing focus; clicks still work.
@MainActor
final class MeetingAlertController: ObservableObject {
    static let shared = MeetingAlertController()
    @Published private(set) var current: EKEvent?
    private var windows: [NSWindow] = []
    private var autoDismiss: Task<Void, Never>?
    private init() {}

    func show(event: EKEvent) {
        dismiss(animated: false)
        current = event
        for screen in NSScreen.screens {
            let w = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .mainMenu + 2
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = false
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: MeetingAlertView(event: event))
            w.alphaValue = 0
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        autoDismiss?.cancel()
        autoDismiss = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func join() {
        if let ev = current, let url = CalendarManager.joinURL(for: ev) { NSWorkspace.shared.open(url) }
        dismiss()
    }

    func snooze(minutes: Int = 1) {
        if let ev = current { CalendarManager.shared.snooze(ev, minutes: minutes) }
        dismiss()
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

struct MeetingAlertView: View {
    let event: EKEvent
    @ObservedObject var ctl = MeetingAlertController.shared
    @State private var hoverJoin = false

    var body: some View {
        let url = CalendarManager.joinURL(for: event)
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { ctl.dismiss() }
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    Circle().fill(Color(cgColor: event.calendar?.cgColor ?? NSColor.systemGreen.cgColor)).frame(width: 10, height: 10)
                    Text(event.calendar?.title ?? "Calendar").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(CalendarManager.relativeStart(event)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                    }
                }
                Text(event.title ?? "Meeting").font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center).lineLimit(2)
                Text("\(event.startDate.shortTime) – \(event.endDate.shortTime)" + (event.location.map { l in url?.absoluteString == l ? "" : " · \(l)" } ?? ""))
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(2)
                if let url {
                    Text(url.host ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 12) {
                    Button { ctl.snooze(minutes: 1) } label: { Text("Snooze 1 min").frame(width: 110) }
                        .buttonStyle(.bordered).controlSize(.large).keyboardShortcut("s", modifiers: [])
                    Button { ctl.dismiss() } label: { Text("Dismiss").frame(width: 90) }
                        .buttonStyle(.bordered).controlSize(.large).keyboardShortcut(.escape, modifiers: [])
                    if url != nil {
                        Button { ctl.join() } label: { Label("Join", systemImage: "video.fill").frame(width: 120) }
                            .buttonStyle(.borderedProminent).tint(.green).controlSize(.large).keyboardShortcut(.return, modifiers: [])
                    } else {
                        Button { NSWorkspace.shared.open(URL(string: "ical://")!); ctl.dismiss() } label: { Label("Open Calendar", systemImage: "calendar").frame(width: 140) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
                .padding(.top, 6)
            }
            .padding(28)
            .frame(width: 520)
            .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
        }
        .preferredColorScheme(.dark)
    }
}
