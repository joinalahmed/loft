import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, tools, features, music, clipboard, timer, developer, permissions, about
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .tools: "switch.2"
        case .features: "square.grid.2x2"
        case .music: "music.note"
        case .clipboard: "doc.on.clipboard"
        case .timer: "timer"
        case .developer: "terminal"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    let selection = SettingsSelection()

    func show(tab: SettingsTab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Loft Settings"
            w.identifier = NSUserInterfaceItemIdentifier("loft.settings")
            w.appearance = NSAppearance(named: .darkAqua)   // matches the island; avoids vibrancy-only text
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView().environmentObject(selection))
            w.center()
            window = w
        }
        // LSUIElement apps are not "frontmost", so a plain makeKey can leave the window
        // visible but unfocused. Activate first (the deprecated flag still works for
        // self-activation from a menu/hotkey), then order front and verify once.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let w = self?.window, w.isVisible, !w.isKeyWindow else { return }
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            w.makeKeyAndOrderFront(nil)
        }
    }

    func close() { window?.close() }
}

final class SettingsSelection: ObservableObject { @Published var tab: SettingsTab = .general }

struct SettingsView: View {
    @EnvironmentObject var selection: SettingsSelection
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(get: { Optional(selection.tab) }, set: { if let t = $0 { selection.tab = t } })) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(170)
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selection.tab {
                    case .general: GeneralSettings()
                    case .appearance: AppearanceSettings()
                    case .tools: ToolsSettings()
                    case .features: FeatureSettings()
                    case .music: MusicSettings()
                    case .clipboard: ClipboardSettings()
                    case .timer: TimerSettings()
                    case .developer: DeveloperSettings()
                    case .permissions: PermissionsSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selection.tab.title)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 480)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sections

struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }
}

struct GeneralSettings: View {
    @ObservedObject var prefs = Preferences.shared
    var body: some View {
        SettingsSection(title: "Behavior") {
            Toggle("Fade the island out while an app is full screen (hover the notch to bring it back)", isOn: $prefs.hideInFullscreen)
            Toggle("Show the next meeting in the menu bar", isOn: $prefs.menuBarNextMeeting)
            Toggle("Open when hovering the notch", isOn: $prefs.openOnHover)
            HStack {
                Text("Hover delay"); Slider(value: $prefs.hoverDelay, in: 0...1, step: 0.05).frame(width: 220)
                Text(String(format: "%.2f s", prefs.hoverDelay)).monospacedDigit().foregroundStyle(.secondary)
            }.disabled(!prefs.openOnHover)
            Toggle("Close when clicking outside", isOn: $prefs.closeOnClickOutside)
            Toggle("Haptic feedback", isOn: $prefs.hapticsEnabled)
            Toggle("Invisible until hover (idle pill fades out)", isOn: $prefs.invisibleUntilHover)
        }
        SettingsSection(title: "System") {
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            Toggle("Hide from screenshots and screen sharing", isOn: $prefs.hideFromScreenCapture)
        }
        SettingsSection(title: "Keyboard shortcuts", footer: "Shortcuts are global and work without Accessibility access. Inside the panel: ⌘1-9 switch tabs, ← → cycle, ⌘K palette, esc closes.") {
            ForEach(HotKeyManager.shared.bindings, id: \.id) { b in Text(b.title).font(.system(.body, design: .monospaced)) }
        }
        Button("Restore Defaults", role: .destructive) { prefs.restoreDefaults() }
    }
}

struct AppearanceSettings: View {
    @ObservedObject var prefs = Preferences.shared
    var body: some View {
        SettingsSection(title: "Closed pill", footer: "On a notched display the pill always covers the hardware notch; the scale widens it slightly.") {
            HStack { Text("Width scale"); Slider(value: $prefs.closedPillScale, in: 1.0...1.4, step: 0.05).frame(width: 220); Text(String(format: "%.0f%%", prefs.closedPillScale * 100)).monospacedDigit().foregroundStyle(.secondary) }
            Toggle("Show clock beside the notch when idle", isOn: $prefs.showClockInPill)
        }
        SettingsSection(title: "Expanded panel") {
            HStack { Text("Width"); Slider(value: $prefs.panelWidth, in: 520...900, step: 10).frame(width: 220); Text("\(Int(prefs.panelWidth)) pt").monospacedDigit().foregroundStyle(.secondary) }
            HStack { Text("Height"); Slider(value: $prefs.panelHeight, in: 180...360, step: 10).frame(width: 220); Text("\(Int(prefs.panelHeight)) pt").monospacedDigit().foregroundStyle(.secondary) }
            Toggle("Drop shadow", isOn: $prefs.enableShadow)
            Toggle("Tint controls with album art colour", isOn: $prefs.accentTinting)
        }
    }
}

struct FeatureSettings: View {
    @ObservedObject var prefs = Preferences.shared
    var body: some View {
        SettingsSection(title: "Tabs", footer: "Disabled features do not run and use no resources.") {
            Toggle("Music (Now Playing live activity)", isOn: $prefs.musicLiveActivity)
            Toggle("Shelf (drop files on the notch)", isOn: $prefs.shelfEnabled)
            Toggle("Clipboard history", isOn: $prefs.clipboardEnabled)
            Toggle("Timer & Pomodoro", isOn: $prefs.timerEnabled)
            Toggle("Calendar", isOn: $prefs.calendarEnabled)
            Toggle("Reminders", isOn: $prefs.remindersEnabled)
            Toggle("Quick notes", isOn: $prefs.notesEnabled)
            Toggle("Terminal (zsh in the notch, ⌃⌥`)", isOn: $prefs.terminalEnabled)
            Toggle("App launcher", isOn: $prefs.launcherEnabled)
            Toggle("Stocks", isOn: $prefs.stocksEnabled)
            Toggle("System stats", isOn: $prefs.systemEnabled)
            Toggle("Camera mirror", isOn: $prefs.mirrorEnabled)
            Toggle("Weather", isOn: $prefs.weatherEnabled)
            Toggle("World clock", isOn: $prefs.worldClockEnabled)
        }
        SettingsSection(title: "Weather") {
            HStack { Text("City"); TextField("Lisbon", text: $prefs.weatherCity).frame(width: 220).onSubmit { WeatherService.shared.refreshIfNeeded(force: true) } }
            Toggle("Use Fahrenheit", isOn: $prefs.weatherUseFahrenheit).onChange(of: prefs.weatherUseFahrenheit) { _, _ in WeatherService.shared.refreshIfNeeded(force: true) }
        }
        GoogleCalendarSettings()
        SettingsSection(title: "Meeting alerts", footer: "Events come from every account added in System Settings → Internet Accounts (iCloud, Google, Outlook, CalDAV). Join links are detected for Zoom, Meet, Teams, Webex, Whereby, FaceTime, Slack and Discord.") {
            Toggle("Alert before meetings", isOn: $prefs.meetingAlertsEnabled)
            Stepper("Alert \(prefs.meetingLeadMinutes) min before", value: $prefs.meetingLeadMinutes, in: 0...30)
            Toggle("Full-screen pop-up on every display (otherwise an island)", isOn: $prefs.meetingAlertFullScreen)
            Toggle("Only events with a video-call link", isOn: $prefs.meetingAlertOnlyWithLinks)
            Toggle("Play a sound", isOn: $prefs.meetingAlertSound)
            Stepper("Show countdown in the pill \(prefs.meetingPillMinutes) min before", value: $prefs.meetingPillMinutes, in: 1...60)
            Button("Preview alert") { CalendarManager.shared.testAlert() }
        }
        SettingsSection(title: "Full-screen alerts", footer: "Timers and due reminders use the same every-display pop-up as meetings. ↩ takes the main action, S snoozes, esc dismisses.") {
            Toggle("When a timer or focus session ends", isOn: $prefs.timerFullScreenAlert)
            Toggle("Alert when a reminder is due", isOn: $prefs.reminderAlerts)
            Toggle("Reminder alerts full screen (otherwise an island)", isOn: $prefs.reminderAlertFullScreen)
        }
        SettingsSection(title: "Screenshots", footer: "Capture uses the system screencapture tool; macOS asks for Screen Recording access the first time. ⌃⌥⇧3 full · ⌃⌥⇧4 region · ⌃⌥⇧5 window.") {
            Toggle("Add screenshots to the shelf", isOn: $prefs.screenshotToShelf)
            Toggle("Copy screenshots to the clipboard", isOn: $prefs.screenshotToClipboard)
            Toggle("Save to Desktop (otherwise ~/Library/Application Support/Loft/Screenshots)", isOn: $prefs.screenshotSaveToDesktop)
            Toggle("Watch the Desktop so native ⌘⇧3/4/5 screenshots land on the shelf", isOn: $prefs.watchDesktopScreenshots)
        }
        SettingsSection(title: "Keep awake") {
            Picker("Default duration", selection: $prefs.keepAwakeDefaultMinutes) {
                ForEach(KeepAwakeManager.durations, id: \.minutes) { d in Text(d.title).tag(d.minutes) }
            }.frame(width: 300)
            Toggle("Allow the display to sleep (keep only the system awake)", isOn: $prefs.keepAwakeAllowDisplaySleep)
        }
        SettingsSection(title: "Battery") {
            Toggle("Show charger and low-battery islands", isOn: $prefs.batteryAlerts)
            Stepper("Low battery warning at \(prefs.batteryLowLevel)%", value: $prefs.batteryLowLevel, in: 5...50, step: 5)
            Stepper("Critical warning at \(prefs.batteryCriticalLevel)%", value: $prefs.batteryCriticalLevel, in: 1...30)
            Toggle("Tell me when the battery is fully charged", isOn: $prefs.batteryFullAlert)
        }
        SettingsSection(title: "Privacy & calls", footer: "Dots appear in the pill while the microphone (orange) or camera (green) is in use, like iPhone. During a call the pill shows a timer and a one-tap mic mute.") {
            Toggle("Show mic / camera indicator", isOn: $prefs.privacyIndicator)
            Toggle("Call island with mute button", isOn: $prefs.callIsland)
        }
        SettingsSection(title: "Downloads", footer: "Watches ~/Downloads for in-progress browser downloads (Safari, Chrome, Firefox) and shows progress in the pill; finished files are added to the shelf. macOS asks for Downloads-folder access the first time.") {
            Toggle("Show download progress", isOn: $prefs.downloadsEnabled)
        }
        SettingsSection(title: "Stocks", footer: "Comma-separated tickers, quotes from Yahoo Finance.") {
            HStack { Text("Symbols"); TextField("AAPL, MSFT", text: Binding(get: { prefs.stockSymbols.joined(separator: ", ") }, set: { prefs.stockSymbols = $0.uppercased().components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty } })).frame(width: 260).onSubmit { StocksService.shared.refresh(force: true) } }
        }
        SettingsSection(title: "Command palette") {
            Picker("Web search engine", selection: $prefs.searchEngine) {
                Text("Google").tag("google"); Text("DuckDuckGo").tag("duckduckgo"); Text("Bing").tag("bing"); Text("Perplexity").tag("perplexity")
            }.frame(width: 300)
        }
    }
}

struct MusicSettings: View {
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var music = MusicManager.shared
    var body: some View {
        SettingsSection(title: "Now Playing", footer: music.usingAdapter ? "Source: system Now Playing (MediaRemote adapter). Works with every app." : "Source: AppleScript polling of Spotify / Music. The MediaRemote adapter could not start.") {
            Toggle("Show album art and visualizer beside the notch", isOn: $prefs.musicLiveActivity)
            Toggle("Animated bars while playing", isOn: $prefs.musicVisualizer)
            Toggle("Hide the music island 30 s after pausing", isOn: $prefs.hideMusicWhenPaused)
        }
        SettingsSection(title: "HUDs", footer: "Replacing the system HUD needs Accessibility access: Loft intercepts the volume and brightness keys and applies them itself, so macOS never draws its own overlay.") {
            Toggle("Show volume and brightness changes in the notch", isOn: $prefs.hudEnabled)
            Toggle("Caps Lock indicator (needs Accessibility)", isOn: $prefs.capsLockHUD)
        }
        SettingsSection(title: "Lyrics", footer: "Time-synced lyrics from LRCLIB, a free community database. The track title, artist and duration are sent to lrclib.net.") {
            Toggle("Show lyrics button in the Music tab", isOn: $prefs.lyricsEnabled)
            Toggle("Replace the system HUD (hide macOS overlay)", isOn: $prefs.hudReplacement)
                .onChange(of: prefs.hudReplacement) { _, on in if on && !AXIsProcessTrusted() { MediaKeyInterceptor.requestAccessibility() } }
            if prefs.hudReplacement && !AXIsProcessTrusted() {
                Label("Grant Accessibility access, then relaunch Loft.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }
}

struct ClipboardSettings: View {
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var clip = ClipboardManager.shared
    var body: some View {
        SettingsSection(title: "Clipboard", footer: "Items marked concealed by password managers are never recorded. Double-click an item to paste it (pasting needs Accessibility).") {
            Toggle("Record clipboard history", isOn: $prefs.clipboardEnabled)
            Stepper("Keep up to \(prefs.clipboardLimit) items", value: $prefs.clipboardLimit, in: 20...1000, step: 20)
            HStack {
                Text("\(clip.items.count) stored")
                Button("Clear unpinned") { clip.clear() }
                Button("Clear all", role: .destructive) { clip.clear(keepPinned: false) }
            }
        }
        SettingsSection(title: "Shelf") {
            Toggle("Enable the file shelf", isOn: $prefs.shelfEnabled)
            Text("Drop files onto the notch while it is closed. Text and images dropped become files in ~/Library/Application Support/Loft/Shelf.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TimerSettings: View {
    @ObservedObject var prefs = Preferences.shared
    var body: some View {
        SettingsSection(title: "Pomodoro") {
            Stepper("Focus length: \(prefs.pomodoroWorkMinutes) min", value: $prefs.pomodoroWorkMinutes, in: 5...90, step: 5)
            Stepper("Break length: \(prefs.pomodoroBreakMinutes) min", value: $prefs.pomodoroBreakMinutes, in: 1...30)
            Toggle("Play a sound when a timer ends", isOn: $prefs.timerSound)
        }
    }
}

struct DeveloperSettings: View {
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var api = LocalAPIServer.shared
    var body: some View {
        SettingsSection(title: "Local API", footer: "Newline-delimited JSON over TCP, loopback only. Every request must carry the token.") {
            Toggle("Enable local API", isOn: $prefs.localAPIEnabled)
            HStack { Text("Port"); TextField("9191", value: $prefs.localAPIPort, format: .number.grouping(.never)).frame(width: 80) ; Circle().fill(api.isRunning ? .green : .gray).frame(width: 8, height: 8); Text(api.isRunning ? "listening" : (api.lastError ?? "stopped")).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Text("Token"); Text(prefs.localAPIToken).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prefs.localAPIToken, forType: .string) }
                Button("Regenerate") { prefs.localAPIToken = Preferences.generateToken() }
            }
            Text("""
            echo '{"token":"\(prefs.localAPIToken)","command":"status"}' | nc 127.0.0.1 \(prefs.localAPIPort)
            echo '{"token":"\(prefs.localAPIToken)","title":"Build finished","subtitle":"main · 42s","symbol":"hammer.fill"}' | nc 127.0.0.1 \(prefs.localAPIPort)
            """).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).padding(8).background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            Text("Commands: status · open · close · toggle · hide · show · music · timer · keepawake · clipboard · shelf · volume · brightness").font(.caption).foregroundStyle(.secondary)
        }
        SettingsSection(title: "URL scheme", footer: "Use from Shortcuts, scripts or a shell: open 'loft://show?title=Hello&message=Ready&duration=3'") {
            Toggle("Allow loft:// URLs", isOn: $prefs.urlSchemeEnabled)
            Text("loft://show?title=…&message=…&symbol=…&duration=1-10\nloft://open?tab=clipboard · loft://close · loft://toggle\nloft://timer?minutes=10 · loft://timer?action=pomodoro").font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
        }
    }
}

struct PermissionsSettings: View {
    @State private var ax = AXIsProcessTrusted()
    var body: some View {
        SettingsSection(title: "Permissions", footer: "Loft only asks when you turn on a feature that needs it. The app is unsigned (ad-hoc), so macOS may forget grants after you rebuild; re-add Loft in System Settings if a feature stops working.") {
            PermissionRow(name: "Accessibility", detail: "HUD replacement, Caps Lock indicator, paste from clipboard", granted: ax,
                          request: { MediaKeyInterceptor.requestAccessibility() },
                          open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            PermissionRow(name: "Calendars", detail: "Calendar tab and Up-next card", granted: CalendarManager.shared.authorized,
                          request: { CalendarManager.shared.requestAccess() },
                          open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
            PermissionRow(name: "Camera", detail: "Mirror tab", granted: AVCaptureDeviceAuth.granted,
                          request: { AVCaptureDeviceAuth.request() },
                          open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
            PermissionRow(name: "Screen Recording", detail: "Screenshots from the notch", granted: nil, request: nil,
                          open: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            PermissionRow(name: "Automation (Music / Spotify)", detail: "Only used if the Now Playing adapter is unavailable", granted: nil, request: nil,
                          open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in ax = AXIsProcessTrusted() }
    }
}

private struct PermissionRow: View {
    let name: String
    let detail: String
    let granted: Bool?
    let request: (() -> Void)?
    let open: String
    var body: some View {
        HStack {
            VStack(alignment: .leading) { Text(name).fontWeight(.medium); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if let granted { Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .green : .secondary) }
            if let request, granted != true { Button("Request") { request() } }
            Button("Open Settings") { NSWorkspace.shared.open(URL(string: open)!) }
        }
        .controlSize(.small)
    }
}

import AVFoundation
enum AVCaptureDeviceAuth {
    static var granted: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    static func request() { AVCaptureDevice.requestAccess(for: .video) { _ in } }
}

struct AboutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading) {
                    Text("Loft").font(.title.bold())
                    Text("Dynamic Island for your Mac · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")").foregroundStyle(.secondary)
                }
            }
            Text("Loft turns the MacBook notch into a live, hoverable island: Now Playing with lyrics, HUDs, clipboard, file shelf, timers, Apple and Google calendars with full-screen meeting alerts, reminders, notes, a terminal, world clock, system stats, weather, screenshots, keep-awake, lock screen, a command palette and a local automation API. Everything stays on this Mac; the only network calls are weather, lyrics, stocks and the calendar account you connect.")
            SettingsSection(title: "Acknowledgements") {
                Text("MediaRemoteAdapter by Jonas van den Berg (BSD-3-Clause) — keeps Now Playing working on macOS 15.4+.")
                Text("Notch shape adapted from DynamicNotchKit by Kai Azim (MIT).")
                Text("Weather data by Open-Meteo (CC BY 4.0).")
            }
            Text("Loft is not affiliated with Apple.").font(.caption).foregroundStyle(.secondary)
        }
    }
}


/// Direct Google Calendar connection (OAuth desktop client + PKCE), no macOS account needed.
struct GoogleCalendarSettings: View {
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var google = GoogleCalendarService.shared
    @State private var showSecret = false
    var body: some View {
        SettingsSection(title: "Google Calendar", footer: "Create an OAuth client in Google Cloud Console → APIs & Services → Credentials → “OAuth client ID” → Desktop app, enable the Google Calendar API, add your Gmail address as a test user, then paste the client ID (and secret, if shown) here. Loft only asks for read-only calendar access and your e-mail address; the refresh token is kept in the Keychain.") {
            if google.isConnected {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(google.accountEmail.isEmpty ? "Connected" : google.accountEmail).font(.system(size: 13, weight: .semibold))
                        Text("\(google.calendars.count) calendar\(google.calendars.count == 1 ? "" : "s") · \(google.events.count) event\(google.events.count == 1 ? "" : "s") today and tomorrow" + (google.lastSync.map { " · synced \($0.shortTime)" } ?? ""))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sync now") { google.sync() }
                    Button("Disconnect", role: .destructive) { google.disconnect() }
                }
                if !google.calendars.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(google.calendars) { c in
                            HStack(spacing: 4) { Circle().fill(c.color).frame(width: 7, height: 7); Text(c.name).font(.system(size: 10)) }
                                .padding(.horizontal, 7).frame(height: 20).background(.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
            } else {
                HStack {
                    Text("Client ID")
                    TextField("…apps.googleusercontent.com", text: $prefs.googleClientID).frame(width: 360)
                        .onSubmit { prefs.googleClientID = GoogleCalendarService.sanitizeClientID(prefs.googleClientID) }
                }
                if prefs.googleClientID != GoogleCalendarService.sanitizeClientID(prefs.googleClientID) {
                    Label("Will use: \(GoogleCalendarService.sanitizeClientID(prefs.googleClientID))", systemImage: "wand.and.stars").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Client secret")
                    if showSecret { TextField("optional for Desktop clients", text: $prefs.googleClientSecret).frame(width: 300) }
                    else { SecureField("optional for Desktop clients", text: $prefs.googleClientSecret).frame(width: 300) }
                    Button(showSecret ? "Hide" : "Show") { showSecret.toggle() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button(google.isConnecting ? "Waiting for Google…" : "Connect Google Account") { google.connect() }
                        .buttonStyle(.borderedProminent).disabled(google.isConnecting || !google.clientID.hasSuffix(".apps.googleusercontent.com"))
                    Button("Open Google Cloud Console") { NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!) }
                }
            }
            if let err = google.lastError { Label(err, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange) }
        }
    }
}
