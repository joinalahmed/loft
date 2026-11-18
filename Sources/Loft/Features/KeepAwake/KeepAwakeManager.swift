import Foundation
import IOKit.pwr_mgt
import Combine
import AppKit

/// Caffeine. Holds a power assertion for a fixed duration, until turned off, or for as long as
/// a rule applies (a meeting or call in progress, or a chosen app running).
@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()
    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    private var assertion: IOPMAssertionID = 0
    private var expiry: Task<Void, Never>?
    /// Why a rule is holding the Mac awake ("during Design review"); nil when it was turned on by hand.
    @Published private(set) var ruleReason: String?
    /// Set when the user turns it off while a rule still applies, so the rule does not switch it straight back on.
    private var suppressed = false
    private var ruleTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private init() {}

    // MARK: Rules

    func startRules() {
        guard ruleTimer == nil else { return }
        ruleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.evaluateRules() } }
        ruleTimer?.tolerance = 5
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.evaluateRules() } })
        }
        evaluateRules()
    }

    /// The first rule that currently applies, phrased for the status line.
    private func activeRule() -> String? {
        let prefs = Preferences.shared
        if prefs.keepAwakeDuringMeetings {
            if PrivacyMonitor.shared.inCall { return "during your call" }
            let now = Date()
            if let ev = CalendarManager.shared.events.first(where: {
                !$0.isAllDay && !$0.declined && !$0.canceled && $0.startDate <= now && $0.endDate > now && !PrayerTimesService.isBlock($0)
            }) { return "during \(ev.title)" }
        }
        let wanted = Set(prefs.keepAwakeApps)
        if !wanted.isEmpty, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier.map(wanted.contains) ?? false }) {
            return "while \(app.localizedName ?? "an app") is open"
        }
        return nil
    }

    func evaluateRules() {
        guard let reason = activeRule() else {
            suppressed = false
            if isActive, ruleReason != nil { release(reason: "Rule no longer applies", byUser: false) }
            return
        }
        if !isActive { if !suppressed { acquire(minutes: 0, rule: reason) } }
        else if ruleReason != nil, ruleReason != reason { ruleReason = reason }
    }

    static let durations: [(title: String, minutes: Int)] = [
        ("Until turned off", 0), ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240)
    ]

    var remaining: TimeInterval? { endDate.map { max(0, $0.timeIntervalSinceNow) } }

    var statusText: String {
        guard isActive else { return "Off" }
        if let ruleReason { return "On " + ruleReason }
        guard let r = remaining else { return "On" }
        return r >= 3600 ? "\(Int(r / 3600))h \(Int(r.truncatingRemainder(dividingBy: 3600) / 60))m left" : "\(max(1, Int(r / 60))) min left"
    }

    func toggle() {
        isActive ? release() : acquire(minutes: Preferences.shared.keepAwakeDefaultMinutes)   // release() here counts as the user's choice
    }

    /// `minutes == 0` keeps the Mac awake until `release()`.
    func acquire(minutes: Int = 0, rule: String? = nil) {
        if isActive { IOPMAssertionRelease(assertion); assertion = 0 }
        ruleReason = rule
        if rule == nil { suppressed = false }
        let type = Preferences.shared.keepAwakeAllowDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        let ok = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Loft keep awake" as CFString, &assertion)
        isActive = ok == kIOReturnSuccess
        expiry?.cancel()
        if minutes > 0 {
            endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(minutes * 60)))
                guard !Task.isCancelled else { return }
                self?.release(reason: "Timer ended", byUser: false)
                self?.evaluateRules()   // a rule may still want the Mac awake
            }
        } else { endDate = nil }
        if isActive {
            NotchViewModel.shared.show(message: IslandMessage(title: "Keep Awake On", subtitle: rule ?? (minutes > 0 ? "for \(Self.durations.first { $0.minutes == minutes }?.title ?? "\(minutes) min")" : "until turned off"),
                                                              symbol: "cup.and.saucer.fill", tint: .yellow), duration: 2)
        }
    }

    /// `byUser` (the default) means a rule that still applies stays off until it stops applying.
    func release(reason: String? = nil, byUser: Bool = true) {
        guard isActive else { return }
        if byUser, activeRule() != nil { suppressed = true }
        ruleReason = nil
        IOPMAssertionRelease(assertion)
        assertion = 0
        isActive = false
        endDate = nil
        expiry?.cancel()
        NotchViewModel.shared.show(message: IslandMessage(title: "Keep Awake Off", subtitle: reason, symbol: "cup.and.saucer", tint: .secondary), duration: 1.5)
    }
}
