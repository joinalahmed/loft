import SwiftUI

@main
struct LoftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var calendar = CalendarManager.shared
    @ObservedObject var audio = AudioDeviceManager.shared

    private var menuBarTitle: String {
        guard prefs.menuBarNextMeeting, let ev = calendar.nextEvent, ev.startDate.timeIntervalSinceNow < 8 * 3600 else { return "" }
        let mins = Int(ev.startDate.timeIntervalSinceNow / 60)
        let when = mins <= 0 ? "now" : mins < 60 ? "in \(mins)m" : ev.startDate.shortTime
        return " " + String(ev.title.prefix(24)) + " · " + when
    }

    var body: some Scene {
        MenuBarExtra {
            Button(vm.state == .open ? "Close Panel" : "Open Panel  ⌃⌥N") { vm.toggle(focus: true) }
            Button(vm.isHidden ? "Show Loft  ⌥Space" : "Hide Loft  ⌥Space") { vm.isHidden.toggle() }
            Divider()
            if let ev = calendar.nextEvent {
                Button("Join “\(String(ev.title.prefix(30)))”  ⌃⌥M") {
                    if let url = ev.joinURL { NSWorkspace.shared.open(url) } else { vm.open(tab: .calendar) }
                }
            }
            Button(audio.micMuted ? "Unmute Microphone  ⌃⌥⇧M" : "Mute Microphone  ⌃⌥⇧M") { audio.toggleMicMute() }
            Menu("Tools") {
                Button("Pick a Colour  ⌃⌥P") { ToolsManager.shared.pickColor() }
                Button("Copy Text from Screen  ⌃⌥O") { ToolsManager.shared.captureText() }
                Button("Eject All External Drives") { SystemStats.shared.ejectAll() }
            }
            Divider()
            Menu("Keep Awake") {
                ForEach(KeepAwakeManager.durations, id: \.minutes) { d in Button(d.title) { KeepAwakeManager.shared.acquire(minutes: d.minutes) } }
                Divider()
                Button("Turn Off") { KeepAwakeManager.shared.release() }.disabled(!KeepAwakeManager.shared.isActive)
            }
            Menu("Screenshot") {
                Button("Region") { ScreenshotManager.shared.capture(.region) }
                Button("Window") { ScreenshotManager.shared.capture(.window) }
                Button("Full Screen") { ScreenshotManager.shared.capture(.full) }
            }
            Divider()
            Button("Lock Screen  ⌃⌥Q") { LockScreenManager.shared.lock() }
            Button("Settings…") { SettingsWindowController.shared.show() }
            Button("About Loft") { SettingsWindowController.shared.show(tab: .about) }
            Divider()
            Button("Quit Loft") { NSApp.terminate(nil) }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: menuBarTitle.isEmpty ? "capsule.fill" : "video.fill")
                if !menuBarTitle.isEmpty { Text(menuBarTitle) }
            }
        }
    }
}
