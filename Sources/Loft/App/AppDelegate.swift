import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow?
    private var hosting: IslandHostingView?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private let vm = NotchViewModel.shared
    private let prefs = Preferences.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        createWindow()
        observePanelState()
        startServices()
        installMonitors()
        HotKeyManager.shared.registerDefaults()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.repositionWindow() }
            .store(in: &cancellables)

        prefs.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyPreferences() }
            .store(in: &cancellables)

        vm.$isHidden.sink { [weak self] hidden in
            self?.window?.ignoresMouseEvents = hidden          // full-screen suppression keeps hover alive
        }.store(in: &cancellables)
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.publisher(for: name).sink { [weak self] _ in self?.updateFullscreenSuppression() }.store(in: &cancellables)
        }
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.updateFullscreenSuppression() } }
        fullscreenTimer?.tolerance = 1

        if !prefs.didFinishOnboarding {
            prefs.didFinishOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [vm] in
                vm.show(message: IslandMessage(title: "Welcome to Loft", subtitle: "Hover the notch to open · ⌃⌥N", symbol: "hand.wave.fill", tint: .cyan), duration: 5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { SettingsWindowController.shared.show() }
        }
        Log.app.info("Loft launched")
    }

    /// Double-clicking Loft.app while it is already running (it has no Dock icon) should do
    /// something visible: pop the panel open and say hello instead of silently ignoring the click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        vm.isHidden = false
        vm.suppressed = false
        vm.show(message: IslandMessage(title: "Loft is running", subtitle: "Hover the notch · ⌃⌥N opens the panel", symbol: "capsule.fill", tint: .cyan), duration: 3)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MusicManager.shared.shutdown()
        LocalAPIServer.shared.stop()
        KeepAwakeManager.shared.release()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Window

    private func createWindow() {
        let screen = NSScreen.preferredNotchScreen ?? NSScreen.screens[0]
        vm.updateMetrics(for: screen)
        let w = NotchWindow(contentRect: windowFrame(on: screen, expanded: false))
        let host = IslandHostingView(rootView: NotchRootView())
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        w.contentView = host
        w.applySharing(hidden: prefs.hideFromScreenCapture)
        w.orderFrontRegardless()
        window = w
        hosting = host
    }

    /// Full frame while the panel is open; a thin strip across the menu bar while closed, so the
    /// (transparent) window never sits over an app's toolbar when it has nothing to show there.
    private func windowFrame(on screen: NSScreen, expanded: Bool) -> NSRect {
        let pad: CGFloat = 40
        let width = max(prefs.panelWidth, 760) + pad * 2
        let height = expanded ? prefs.panelHeight + pad : vm.closedHeight + 10   // closed: stay within the menu bar
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    private var shrinkTask: Task<Void, Never>?

    func repositionWindow() {
        guard let window, let screen = NSScreen.preferredNotchScreen ?? NSScreen.screens.first else { return }
        vm.updateMetrics(for: screen)
        window.setFrame(windowFrame(on: screen, expanded: vm.state == .open), display: true)
        window.orderFrontRegardless()
    }

    private func observePanelState() {
        // `$state` fires from willSet, i.e. *before* the value changes. Resizing the window with
        // display:true at that moment forces a synchronous SwiftUI layout that still sees
        // `.closed`, and the pending invalidation is consumed, so the island never visibly opened.
        // Grow without a synchronous display and let the next run-loop turn render the open state.
        vm.$state.removeDuplicates().sink { [weak self] state in
            guard let self, let window = self.window, let screen = window.screen ?? NSScreen.preferredNotchScreen else { return }
            self.shrinkTask?.cancel()
            if state == .open {
                // Still inside willSet here: defer so the hosting view lays out with `.open`.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.vm.state == .open else { return }
                    window.setFrame(self.windowFrame(on: screen, expanded: true), display: true)
                }
            } else {
                self.shrinkTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))                           // after the close animation
                    guard !Task.isCancelled, let self, self.vm.state == .closed else { return }
                    window.setFrame(self.windowFrame(on: screen, expanded: false), display: true)
                }
            }
        }.store(in: &cancellables)
    }

    private var fullscreenTimer: Timer?

    /// With "hide in full screen" on, the island disappears while the frontmost app has a
    /// window covering the whole notch screen (videos, games, presentations). Uses only
    /// window bounds from CGWindowList, which needs no Screen Recording permission.
    private func updateFullscreenSuppression() {
        guard prefs.hideInFullscreen else { if vm.suppressed { vm.suppressed = false }; return }
        guard let front = NSWorkspace.shared.frontmostApplication, front != .current, let screen = window?.screen ?? NSScreen.preferredNotchScreen else { return }
        let pid = front.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // CG coordinates are top-left based; convert the screen frame.
        let target = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let full = list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return r.width >= target.width - 2 && r.height >= target.height - 2 && abs(r.minX - target.minX) < 2
        }
        if full != vm.suppressed {
            vm.suppressed = full
            if full, vm.state == .open { vm.close() }
        }
    }

    private func applyPreferences() {
        repositionWindow()
        window?.applySharing(hidden: prefs.hideFromScreenCapture)
        LocalAPIServer.shared.applyPreferences()
        MediaKeyInterceptor.shared.applyPreferences()
        ScreenshotManager.shared.applyPreferences()
        DownloadMonitor.shared.applyPreferences()
        LaunchAtLogin.apply(prefs.launchAtLogin)
    }

    // MARK: Services

    private func startServices() {
        MusicManager.shared.start()
        VolumeMonitor.shared.start()
        BrightnessMonitor.shared.start()
        BatteryMonitor.shared.start()
        ClipboardManager.shared.start()
        CapsLockMonitor.shared.start()
        MediaKeyInterceptor.shared.applyPreferences()
        LocalAPIServer.shared.applyPreferences()
        _ = TimerManager.shared
        _ = ShelfManager.shared
        _ = ScreenshotManager.shared
        _ = CalendarManager.shared
        _ = AudioDeviceManager.shared
        _ = LockScreenManager.shared
        PrivacyMonitor.shared.start()
        DownloadMonitor.shared.applyPreferences()
        if prefs.remindersEnabled { _ = RemindersManager.shared }
    }

    // MARK: Event monitors

    private func installMonitors() {
        // Close when clicking anywhere outside the island (no Accessibility needed for mouse events).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.prefs.closeOnClickOutside, self.vm.state == .open, !self.vm.isHovering else { return }
                self.vm.close()
            }
        }
        // Keys while our panel is key: Esc closes, ⌘K palette, ⌘1-9 tabs, arrows cycle.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.vm.state == .open, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { // esc
                if self.vm.paletteVisible { self.vm.paletteVisible = false } else { self.vm.close() }
                return nil
            }
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "k" { self.vm.paletteVisible.toggle(); return nil }
                if let c = event.charactersIgnoringModifiers, let n = Int(c), n >= 1, n <= 9 {
                    let tabs = self.prefs.enabledTabs
                    if n <= tabs.count { self.vm.tab = tabs[n - 1]; return nil }
                }
            }
            if !self.vm.paletteVisible, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                if event.keyCode == 123 { self.vm.nextTab(-1); return nil }  // left
                if event.keyCode == 124 { self.vm.nextTab(1); return nil }   // right
            }
            return event
        }
        // Keyboard focus is taken only on deliberate opens; hover-open must never interrupt typing.
        NotificationCenter.default.publisher(for: .loftOpenPanel).sink { [weak self] note in
            if note.userInfo?["focus"] as? Bool == true { self?.window?.makeKey() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .loftWantsKeyboard).sink { [weak self] _ in
            self?.window?.makeKey()
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .loftClosePanel).sink { [weak self] _ in
            guard let w = self?.window, w.isKeyWindow else { return }
            w.resignKey()
            // Hand focus back to whatever app the user was in.
            if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current { front.activate() }
        }.store(in: &cancellables)
    }

    // MARK: URL scheme  loft://show?title=…&message=…&duration=…&symbol=…

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: str) else { return }
        URLSchemeHandler.handle(url)
    }
}

enum URLSchemeHandler {
    @MainActor static func handle(_ url: URL) {
        guard Preferences.shared.urlSchemeEnabled else { return }
        let vm = NotchViewModel.shared
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let q = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } })
        switch url.host {
        case "show":
            let title = String((q["title"] ?? "Loft").prefix(120))
            let msg = q["message"].map { String($0.prefix(500)) }
            let dur = min(10, max(1, Double(q["duration"] ?? "") ?? 4))
            let progress = Double(q["progress"] ?? "")
            vm.show(message: IslandMessage(title: title, subtitle: msg, symbol: q["symbol"], progress: progress), duration: dur)
        case "open": vm.open(tab: PanelTab(rawValue: q["tab"] ?? ""))
        case "close": vm.close()
        case "toggle": vm.toggle()
        case "lock": LockScreenManager.shared.lock()
        case "timer":
            if let m = Int(q["minutes"] ?? "") { TimerManager.shared.startCountdown(minutes: m) }
            else if q["action"] == "pomodoro" { TimerManager.shared.startPomodoro() }
            else if q["action"] == "stop" { TimerManager.shared.stop() }
        default: break
        }
    }
}
