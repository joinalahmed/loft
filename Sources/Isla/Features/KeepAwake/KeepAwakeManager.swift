import Foundation
import IOKit.pwr_mgt
import Combine

/// Caffeine. Holds a power assertion for a fixed duration or until turned off.
@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()
    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    private var assertion: IOPMAssertionID = 0
    private var expiry: Task<Void, Never>?
    private init() {}

    static let durations: [(title: String, minutes: Int)] = [
        ("Until turned off", 0), ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240)
    ]

    var remaining: TimeInterval? { endDate.map { max(0, $0.timeIntervalSinceNow) } }

    var statusText: String {
        guard isActive else { return "Off" }
        guard let r = remaining else { return "On" }
        return r >= 3600 ? "\(Int(r / 3600))h \(Int(r.truncatingRemainder(dividingBy: 3600) / 60))m left" : "\(max(1, Int(r / 60))) min left"
    }

    func toggle() {
        isActive ? release() : acquire(minutes: Preferences.shared.keepAwakeDefaultMinutes)
    }

    /// `minutes == 0` keeps the Mac awake until `release()`.
    func acquire(minutes: Int = 0) {
        if isActive { IOPMAssertionRelease(assertion); assertion = 0 }
        let type = Preferences.shared.keepAwakeAllowDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        let ok = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Isla keep awake" as CFString, &assertion)
        isActive = ok == kIOReturnSuccess
        expiry?.cancel()
        if minutes > 0 {
            endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(minutes * 60)))
                guard !Task.isCancelled else { return }
                self?.release(reason: "Timer ended")
            }
        } else { endDate = nil }
        if isActive {
            NotchViewModel.shared.show(message: IslandMessage(title: "Keep Awake On", subtitle: minutes > 0 ? "for \(Self.durations.first { $0.minutes == minutes }?.title ?? "\(minutes) min")" : "until turned off",
                                                              symbol: "cup.and.saucer.fill", tint: .yellow), duration: 2)
        }
    }

    func release(reason: String? = nil) {
        guard isActive else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isActive = false
        endDate = nil
        expiry?.cancel()
        NotchViewModel.shared.show(message: IslandMessage(title: "Keep Awake Off", subtitle: reason, symbol: "cup.and.saucer", tint: .secondary), duration: 1.5)
    }
}
