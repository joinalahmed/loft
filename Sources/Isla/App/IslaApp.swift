import SwiftUI

@main
struct IslaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var vm = NotchViewModel.shared

    var body: some Scene {
        MenuBarExtra("Isla", systemImage: "capsule.fill") {
            Button(vm.state == .open ? "Close Panel" : "Open Panel  ⌃⌥N") { vm.toggle(focus: true) }
            Button(vm.isHidden ? "Show Isla  ⌥Space" : "Hide Isla  ⌥Space") { vm.isHidden.toggle() }
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
            Button("Settings…") { SettingsWindowController.shared.show() }
            Button("About Isla") { SettingsWindowController.shared.show(tab: .about) }
            Divider()
            Button("Quit Isla") { NSApp.terminate(nil) }
        }
    }
}
