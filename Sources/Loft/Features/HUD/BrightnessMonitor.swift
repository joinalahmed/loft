import AppKit

/// Reads display brightness through DisplayServices (private, but stable since 10.13).
final class BrightnessMonitor {
    static let shared = BrightnessMonitor()
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private var getFn: GetFn?
    private var setFn: SetFn?
    private var timer: Timer?
    private var last: Float = -1

    private init() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return }
        if let g = dlsym(h, "DisplayServicesGetBrightness") { getFn = unsafeBitCast(g, to: GetFn.self) }
        if let s = dlsym(h, "DisplayServicesSetBrightness") { setFn = unsafeBitCast(s, to: SetFn.self) }
    }

    var isSupported: Bool { getFn != nil && current != nil }

    private var displayID: CGDirectDisplayID {
        NSScreen.preferredNotchScreen?.displayID ?? CGMainDisplayID()
    }

    var current: Float? {
        guard let getFn else { return nil }
        var v: Float = 0
        return getFn(displayID, &v) == 0 ? v : nil
    }

    func start() {
        guard isSupported else { return }
        last = current ?? -1
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
    }

    private func tick() {
        guard Preferences.shared.hudEnabled, let v = current else { return }
        defer { last = v }
        guard last >= 0, abs(v - last) > 0.002 else { return }
        Task { @MainActor in NotchViewModel.shared.show(.brightness(Double(v))) }
    }

    func set(_ value: Float) {
        guard let setFn else { return }
        let v = max(0, min(1, value))
        _ = setFn(displayID, v)
        last = v
        Task { @MainActor in NotchViewModel.shared.show(.brightness(Double(v))) }
    }

    func step(_ direction: Float, fine: Bool) {
        guard let c = current else { return }
        set(c + (fine ? 1.0 / 64 : 1.0 / 16) * direction)
    }
}
