import AppKit

/// Caps Lock indicator. Global key monitors only deliver events once the app is
/// trusted for Accessibility, so this silently does nothing until then.
final class CapsLockMonitor {
    static let shared = CapsLockMonitor()
    private var monitor: Any?
    private var last = NSEvent.modifierFlags.contains(.capsLock)
    private init() {}

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let on = event.modifierFlags.contains(.capsLock)
            guard on != self.last else { return }
            self.last = on
            guard Preferences.shared.capsLockHUD, Preferences.shared.hudEnabled else { return }
            Task { @MainActor in NotchViewModel.shared.show(.capsLock(on), duration: 1.2) }
        }
    }
}
