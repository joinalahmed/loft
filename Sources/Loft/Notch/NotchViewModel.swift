import SwiftUI
import Combine
import AppKit

enum NotchState { case closed, open }

/// Something that briefly takes over the collapsed pill (volume HUD, charger plugged in, API message…).
struct Transient: Identifiable, Equatable {
    enum Kind: Equatable {
        case volume(Double, muted: Bool)
        case brightness(Double)
        case keyboardBacklight(Double)
        case capsLock(Bool)
        case battery(level: Int, charging: Bool, pluggedIn: Bool, low: Bool)
        case message(IslandMessage)
        case ask(ApprovalRequest)
    }
    let id = UUID()
    let kind: Kind
    let duration: TimeInterval
    static func == (a: Transient, b: Transient) -> Bool { a.id == b.id }
}

/// A question shown in the pill with buttons; used by the local API `ask` command
/// (e.g. Claude Code permission prompts) so the answer never leaves the notch.
struct ApprovalRequest: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var symbol: String?
    var options: [String]          // first option is the affirmative / default
    var reply: (String?) -> Void   // nil when dismissed or timed out
    static func == (a: ApprovalRequest, b: ApprovalRequest) -> Bool { a.id == b.id }
}

struct IslandMessage: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var symbol: String?
    var progress: Double?
    var tint: Color = .white
    var thumbnail: NSImage?
    var action: (() -> Void)?
    static func == (a: IslandMessage, b: IslandMessage) -> Bool { a.id == b.id }
}

@MainActor
final class NotchViewModel: ObservableObject {
    static let shared = NotchViewModel()

    @Published private(set) var state: NotchState = .closed
    @Published var isHovering = false
    @Published var tab: PanelTab = .home
    @Published var metrics = NotchMetrics(hasNotch: true, closedSize: CGSize(width: 222, height: 38), menuBarHeight: 39)
    @Published private(set) var transient: Transient?
    /// Rendered island frame in hosting-view coordinates; everything outside is click-through.
    var islandFrame: CGRect = .zero
    /// Natural width of the live row (artwork + notch + bars…); the open panel's head grows to fit it.
    @Published var compactWidth: CGFloat = 0
    let headerHeight: CGFloat = 36

    /// Width of the top band while open: the notch plus whatever the live row needs. Nil = full width.
    var headWidth: CGFloat? {
        guard state == .open, metrics.hasNotch else { return nil }
        return max(metrics.closedSize.width, compactWidth + 8)
    }

    /// True when a window-local point (flipped, y down) is on the visible island. The transparent
    /// parts of the top band beside the head are not part of the island.
    func islandContains(_ p: CGPoint) -> Bool {
        let frame = islandFrame.insetBy(dx: -4, dy: -4)
        guard frame.contains(p) else { return false }
        if let head = headWidth, p.y < islandFrame.minY + closedHeight + 2, abs(p.x - islandFrame.midX) > head / 2 + 4 { return false }
        return true
    }
    @Published var isHidden = false
    /// Set while the frontmost app is full screen and the "hide in fullscreen" preference is on.
    @Published var suppressed = false
    var effectivelyHidden: Bool { isHidden || suppressed }
    @Published var paletteVisible = false
    @Published var isDragTargeted = false
    @Published var pinnedOpen = false   // e.g. while a sharing sheet is up
    /// True only when the user opened the panel deliberately (click, hotkey, palette).
    /// Hover- and API-opens never take keyboard focus away from the frontmost app.
    @Published private(set) var wantsKeyboard = false

    let prefs = Preferences.shared
    private var hoverTask: Task<Void, Never>?
    private var transientTask: Task<Void, Never>?
    private var autoCloseTask: Task<Void, Never>?

    var openSize: CGSize { CGSize(width: prefs.panelWidth, height: prefs.panelHeight + headerHeight) }
    var closedHeight: CGFloat { metrics.closedSize.height }
    var notchWidth: CGFloat { metrics.closedSize.width }

    // Corner radii follow the real notch when closed and swell when open.
    var topRadius: CGFloat { state == .open ? (metrics.hasNotch ? 6 : 19) : (metrics.hasNotch ? 6 : 0) }
    var bottomRadius: CGFloat { state == .open ? 24 : (metrics.hasNotch ? 14 : closedHeight / 2) }

    private init() {}

    // MARK: Open / close

    func open(tab: PanelTab? = nil, focus: Bool = false) {
        hoverTask?.cancel()
        autoCloseTask?.cancel()
        if let tab, prefs.enabledTabs.contains(tab) { self.tab = tab }
        if focus && !wantsKeyboard { wantsKeyboard = true; NotificationCenter.default.post(name: .loftWantsKeyboard, object: nil) }
        guard state != .open else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { state = .open }
        NotificationCenter.default.post(name: .loftOpenPanel, object: nil, userInfo: ["focus": focus])
    }

    func close() {
        hoverTask?.cancel()
        autoCloseTask?.cancel()
        paletteVisible = false
        wantsKeyboard = false
        guard state != .closed, !pinnedOpen else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) { state = .closed }
        NotificationCenter.default.post(name: .loftClosePanel, object: nil)
    }

    func toggle(focus: Bool = false) { state == .open ? close() : open(focus: focus) }

    /// Called when a control that needs typing is used (palette, search). Plain clicks on
    /// buttons never take the keyboard away from the app underneath.
    func userInteracted() {
        guard !wantsKeyboard else { return }
        wantsKeyboard = true
        NotificationCenter.default.post(name: .loftWantsKeyboard, object: nil)
    }

    /// Open, then close automatically after `seconds` unless the user moves in.
    func peek(tab: PanelTab? = nil, seconds: Double = 3) {
        open(tab: tab)
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.isHovering else { return }
            self.close()
        }
    }

    func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()
        if hovering {
            if state == .closed { Haptics.tap() }
            guard state == .closed, prefs.openOnHover, transient == nil else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.prefs.hoverDelay ?? 0.25))
                guard !Task.isCancelled, let self, self.isHovering, self.state == .closed else { return }
                self.open()
            }
        } else if state == .open, !pinnedOpen {
            // Grace period so a quick exit and re-entry does not slam the panel shut.
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self, !self.isHovering, !self.isDragTargeted else { return }
                self.close()
            }
        }
    }

    // MARK: Transients

    func show(_ kind: Transient.Kind, duration: TimeInterval = 1.6) {
        let t = Transient(kind: kind, duration: duration)
        transientTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { transient = t }
        transientTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.transient?.id == t.id else { return }
            if case .ask(let pending) = t.kind { pending.reply(nil) }   // timed out
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self.transient = nil }
        }
    }

    func show(message: IslandMessage, duration: TimeInterval = 4) {
        show(.message(message), duration: duration)
    }

    func ask(_ request: ApprovalRequest, timeout: TimeInterval = 120) {
        if case .ask(let pending)? = transient?.kind { pending.reply(nil) }
        show(.ask(request), duration: timeout)
        Haptics.tap()
        NSSound(named: "Pop")?.play()
    }

    func answer(_ request: ApprovalRequest, with option: String?) {
        if case .ask(let cur)? = transient?.kind, cur.id == request.id { dismissTransient() }
        request.reply(option)
    }

    func dismissTransient() {
        if case .ask(let pending)? = transient?.kind { pending.reply(nil) }
        transientTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { transient = nil }
    }

    func updateMetrics(for screen: NSScreen) {
        metrics = NotchMetrics.measure(screen, scale: prefs.closedPillScale)
    }

    func nextTab(_ delta: Int) {
        let tabs = prefs.enabledTabs
        guard let i = tabs.firstIndex(of: tab) else { return }
        tab = tabs[(i + delta + tabs.count) % tabs.count]
    }
}
