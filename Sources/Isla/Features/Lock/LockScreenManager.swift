import AppKit
import SwiftUI
import Combine

/// Lock the Mac from the notch, react to lock / unlock, and (optionally) float a clock +
/// Now Playing widget above the lock screen.
@MainActor
final class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()
    @Published private(set) var isLocked = false
    @Published private(set) var lockedAt: Date?
    private var widgetWindows: [NSWindow] = []
    private var pausedMusicForLock = false
    private var prefs: Preferences { Preferences.shared }
    private init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.didLock() } }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.didUnlock() } }
    }

    /// Locks immediately. Uses the private login.framework call Raycast/Alfred rely on; it needs no
    /// permission. Falls back to the ⌃⌘Q key event (needs Accessibility) and then to display sleep.
    func lock() {
        NotchViewModel.shared.close()
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            typealias Fn = @convention(c) () -> Int32
            _ = unsafeBitCast(sym, to: Fn.self)()
            return
        }
        if AXIsProcessTrusted() {
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: false)
            down?.flags = [.maskCommand, .maskControl]; up?.flags = [.maskCommand, .maskControl]
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
            return
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    private func didLock() {
        isLocked = true
        lockedAt = Date()
        if prefs.pauseMusicOnLock, MusicManager.shared.isPlaying { MusicManager.shared.pause(); pausedMusicForLock = true }
        if prefs.releaseKeepAwakeOnLock, KeepAwakeManager.shared.isActive { KeepAwakeManager.shared.release(reason: "screen locked") }
        if prefs.lockScreenWidgets { showWidgets() }
    }

    private func didUnlock() {
        isLocked = false
        hideWidgets()
        if prefs.resumeMusicOnUnlock, pausedMusicForLock { MusicManager.shared.play() }
        pausedMusicForLock = false
        if prefs.welcomeBackIsland, let t = lockedAt {
            let away = Date().timeIntervalSince(t)
            if away > 60 {
                let text = away < 3600 ? "\(Int(away / 60)) min away" : String(format: "%dh %02dm away", Int(away) / 3600, (Int(away) % 3600) / 60)
                var subtitle = text
                if let ev = CalendarManager.shared.nextEvent, ev.startDate.timeIntervalSinceNow < 3600 { subtitle += " · \(ev.title) \(ev.relativeStart)" }
                NotchViewModel.shared.show(message: IslandMessage(title: "Welcome back", subtitle: subtitle, symbol: "lock.open.fill", tint: .cyan), duration: 4)
            }
        }
        lockedAt = nil
    }

    // MARK: Lock-screen widgets

    /// A borderless panel above the lock screen's shield window. macOS lets a session's windows
    /// show over the lock screen only at or above the shielding level; this is best effort.
    private func showWidgets() {
        hideWidgets()
        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        for screen in NSScreen.screens {
            let w = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = level
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: LockWidgetView())
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            widgetWindows.append(w)
        }
    }

    private func hideWidgets() {
        widgetWindows.forEach { $0.close() }
        widgetWindows.removeAll()
    }

    /// Developer aid: show the widget layer for a few seconds without locking.
    func previewWidgets(seconds: TimeInterval = 5) {
        showWidgets()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.hideWidgets() }
    }
}

/// Clock, date, Now Playing and the next meeting, bottom-centred so they sit under the
/// lock screen's own clock and avatar.
struct LockWidgetView: View {
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var battery = BatteryMonitor.shared
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                if music.isActive, !music.title.isEmpty {
                    HStack(spacing: 10) {
                        AlbumArtView(image: music.artwork, cornerRadius: 8).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(music.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(music.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        AudioBarsView(isPlaying: music.isPlaying, tint: .white).frame(width: 18, height: 14)
                    }
                    .frame(maxWidth: 320)
                    .pillBackground()
                }
                if let ev = cal.nextEvent, ev.startDate.timeIntervalSinceNow < 12 * 3600 {
                    HStack(spacing: 8) {
                        Image(systemName: ev.isVideoCall ? "video.fill" : "calendar").foregroundStyle(ev.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(ev.startDate <= Date() ? "Now · ends \(ev.endDate.shortTime)" : "\(ev.startDate.shortTime) · \(ev.relativeStart)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 300)
                    .pillBackground()
                }
                HStack(spacing: 6) {
                    Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent").foregroundStyle(battery.level <= 20 ? .red : .white)
                    Text("\(battery.level)%").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .pillBackground()
            }
            .foregroundStyle(.white)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    func pillBackground() -> some View {
        self.padding(.horizontal, 14).frame(height: 56)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}
