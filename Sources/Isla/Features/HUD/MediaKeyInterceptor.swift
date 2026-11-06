import AppKit
import ApplicationServices

/// Optional: swallow volume/brightness keys and apply them ourselves so macOS never
/// draws its own HUD. Needs Accessibility (event tap on HID events).
final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private init() {}

    private enum NXKey: Int { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }

    var isActive: Bool { tap != nil }

    func applyPreferences() {
        if Preferences.shared.hudReplacement && Preferences.shared.hudEnabled { start() } else { stop() }
    }

    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, _, event, _ in MediaKeyInterceptor.shared.handle(event) },
                                        userInfo: nil) else {
            Log.hud.error("media key tap failed"); return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.type == .tapDisabledByTimeout || event.type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data1 = ns.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard let key = NXKey(rawValue: keyCode) else { return Unmanaged.passUnretained(event) }
        let isDown = state == 0xA
        let fine = ns.modifierFlags.contains(.shift) && ns.modifierFlags.contains(.option)
        if isDown {
            switch key {
            case .soundUp: VolumeMonitor.shared.step(1, fine: fine)
            case .soundDown: VolumeMonitor.shared.step(-1, fine: fine)
            case .mute: VolumeMonitor.shared.toggleMute()
            case .brightnessUp: BrightnessMonitor.shared.step(1, fine: fine)
            case .brightnessDown: BrightnessMonitor.shared.step(-1, fine: fine)
            }
        }
        return nil // swallow both down and up so the system HUD never appears
    }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}
