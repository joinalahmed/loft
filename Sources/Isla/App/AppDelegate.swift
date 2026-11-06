import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow?
    private var hosting: NSHostingView<NotchRootView>?
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
            self?.window?.ignoresMouseEvents = hidden
        }.store(in: &cancellables)

        if !prefs.didFinishOnboarding {
            prefs.didFinishOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [vm] in
                vm.show(message: IslandMessage(title: "Welcome to Isla", subtitle: "Hover the notch to open · ⌃⌥N", symbol: "hand.wave.fill", tint: .cyan), duration: 5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { SettingsWindowController.shared.show() }
        }
        Log.app.info("Isla launched")
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
        let w = NotchWindow(contentRect: windowFrame(on: screen))
        let host = NSHostingView(rootView: NotchRootView())
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        w.contentView = host
        w.applySharing(hidden: prefs.hideFromScreenCapture)
        w.orderFrontRegardless()
        window = w
        hosting = host
    }

    private func windowFrame(on screen: NSScreen) -> NSRect {
        let pad: CGFloat = 40
        let width = max(prefs.panelWidth, 760) + pad * 2
        let height = prefs.panelHeight + pad
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    func repositionWindow() {
        guard let window, let screen = NSScreen.preferredNotchScreen ?? NSScreen.screens.first else { return }
        vm.updateMetrics(for: screen)
        window.setFrame(windowFrame(on: screen), display: true)
        window.orderFrontRegardless()
    }

    private func applyPreferences() {
        repositionWindow()
        window?.applySharing(hidden: prefs.hideFromScreenCapture)
        LocalAPIServer.shared.applyPreferences()
        MediaKeyInterceptor.shared.applyPreferences()
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
            guard let self, self.vm.state == .open else { return event }
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
        NotificationCenter.default.publisher(for: .islaOpenPanel).sink { [weak self] _ in
            self?.window?.makeKey()
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .islaClosePanel).sink { [weak self] _ in
            self?.window?.resignKey()
        }.store(in: &cancellables)
    }

    // MARK: URL scheme  isla://show?title=…&message=…&duration=…&symbol=…

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
            let title = String((q["title"] ?? "Isla").prefix(120))
            let msg = q["message"].map { String($0.prefix(500)) }
            let dur = min(10, max(1, Double(q["duration"] ?? "") ?? 4))
            let progress = Double(q["progress"] ?? "")
            vm.show(message: IslandMessage(title: title, subtitle: msg, symbol: q["symbol"], progress: progress), duration: dur)
        case "open": vm.open(tab: PanelTab(rawValue: q["tab"] ?? ""))
        case "close": vm.close()
        case "toggle": vm.toggle()
        case "timer":
            if let m = Int(q["minutes"] ?? "") { TimerManager.shared.startCountdown(minutes: m) }
            else if q["action"] == "pomodoro" { TimerManager.shared.startPomodoro() }
            else if q["action"] == "stop" { TimerManager.shared.stop() }
        default: break
        }
    }
}
