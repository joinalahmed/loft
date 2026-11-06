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
    }
    let id = UUID()
    let kind: Kind
    let duration: TimeInterval
    static func == (a: Transient, b: Transient) -> Bool { a.id == b.id }
}

struct IslandMessage: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var symbol: String?
    var progress: Double?
    var tint: Color = .white
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
    @Published var isHidden = false
    @Published var paletteVisible = false
    @Published var isDragTargeted = false
    @Published var pinnedOpen = false   // e.g. while a sharing sheet is up

    let prefs = Preferences.shared
    private var hoverTask: Task<Void, Never>?
    private var transientTask: Task<Void, Never>?
    private var autoCloseTask: Task<Void, Never>?

    var openSize: CGSize { CGSize(width: prefs.panelWidth, height: prefs.panelHeight) }
    var closedHeight: CGFloat { metrics.closedSize.height }
    var notchWidth: CGFloat { metrics.closedSize.width }

    // Corner radii follow the real notch when closed and swell when open.
    var topRadius: CGFloat { state == .open ? 19 : (metrics.hasNotch ? 6 : 0) }
    var bottomRadius: CGFloat { state == .open ? 24 : (metrics.hasNotch ? 14 : closedHeight / 2) }

    private init() {}

    // MARK: Open / close

    func open(tab: PanelTab? = nil) {
        hoverTask?.cancel()
        autoCloseTask?.cancel()
        if let tab, prefs.enabledTabs.contains(tab) { self.tab = tab }
        guard state != .open else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { state = .open }
        NotificationCenter.default.post(name: .islaOpenPanel, object: nil)
    }

    func close() {
        hoverTask?.cancel()
        autoCloseTask?.cancel()
        paletteVisible = false
        guard state != .closed, !pinnedOpen else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) { state = .closed }
        NotificationCenter.default.post(name: .islaClosePanel, object: nil)
    }

    func toggle() { state == .open ? close() : open() }

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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self.transient = nil }
        }
    }

    func show(message: IslandMessage, duration: TimeInterval = 4) {
        show(.message(message), duration: duration)
    }

    func dismissTransient() {
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
