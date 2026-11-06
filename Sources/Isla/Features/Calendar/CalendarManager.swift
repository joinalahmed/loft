import EventKit
import SwiftUI
import Combine
import AppKit

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var imminentEvent: EKEvent?     // drives the pill countdown
    @Published private(set) var now = Date()
    private let store = EKEventStore()
    private var cancellable: AnyCancellable?
    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var alerted = Set<String>()
    private var snoozed: [String: Date] = [:]
    private let prefs = Preferences.shared

    private init() {
        cancellable = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .sink { [weak self] _ in Task { @MainActor in self?.reload() } }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tickTimer?.tolerance = 3
        checkStatus()
    }

    func checkStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = status == .fullAccess
        denied = status == .denied || status == .restricted || status == .writeOnly
        if authorized { reload() }
    }

    func requestAccess() {
        Task {
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            authorized = ok; denied = !ok
            if ok { reload() }
        }
    }

    /// Google, Outlook, iCloud and CalDAV accounts all arrive through EventKit once they are
    /// added in System Settings → Internet Accounts, so "sync" is free.
    func reload() {
        guard authorized else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 2, to: start)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
        tick()
    }

    var calendarSources: [String] {
        Array(Set(store.calendars(for: .event).map { $0.source.title })).sorted()
    }

    var todayEvents: [EKEvent] { events.filter { Calendar.current.isDateInToday($0.startDate) } }

    var nextEvent: EKEvent? { events.first { !$0.isAllDay && $0.endDate > now } }

    // MARK: Meeting alerts

    private func tick() {
        now = Date()
        guard authorized else { imminentEvent = nil; return }
        let pillWindow = TimeInterval(prefs.meetingPillMinutes * 60)
        imminentEvent = events.first { ev in
            !ev.isAllDay && ev.startDate.timeIntervalSince(now) <= pillWindow && ev.endDate > now
                && ev.startDate.timeIntervalSince(now) > -120
        }
        guard prefs.meetingAlertsEnabled else { return }
        let lead = TimeInterval(prefs.meetingLeadMinutes * 60)
        for ev in events where !ev.isAllDay && ev.status != .canceled {
            let id = ev.eventIdentifier ?? ev.calendarItemIdentifier
            let until = ev.startDate.timeIntervalSince(now)
            if let snoozeUntil = snoozed[id] {
                if now >= snoozeUntil, until > -600 { snoozed[id] = nil; fire(ev) }
                continue
            }
            guard !alerted.contains(id), until <= lead, until > -60 else { continue }
            if prefs.meetingAlertOnlyWithLinks && Self.joinURL(for: ev) == nil { continue }
            if ev.hasAttendees, let me = ev.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined { continue }
            alerted.insert(id)
            fire(ev)
        }
    }

    private func fire(_ ev: EKEvent) {
        if prefs.meetingAlertSound { NSSound(named: "Ping")?.play() }
        if prefs.meetingAlertFullScreen {
            MeetingAlertController.shared.show(event: ev)
        } else {
            let url = Self.joinURL(for: ev)
            NotchViewModel.shared.show(message: IslandMessage(
                title: ev.title ?? "Meeting", subtitle: Self.relativeStart(ev), symbol: url == nil ? "calendar" : "video.fill",
                tint: .green, action: url.map { u in { NSWorkspace.shared.open(u) } }), duration: 20)
        }
    }

    func snooze(_ ev: EKEvent, minutes: Int = 1) {
        snoozed[ev.eventIdentifier ?? ev.calendarItemIdentifier] = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func testAlert() {
        let ev = EKEvent(eventStore: store)
        ev.title = "Design review"
        ev.startDate = Date().addingTimeInterval(120)
        ev.endDate = ev.startDate.addingTimeInterval(1800)
        ev.location = "https://meet.google.com/abc-defg-hij"
        ev.calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first
        fire(ev)
    }

    static func relativeStart(_ ev: EKEvent) -> String {
        let s = Int(ev.startDate.timeIntervalSinceNow.rounded())
        if s > 90 { return "in \(s / 60) min" }
        if s > 0 { return "in \(s) s" }
        if s > -90 { return "starting now" }
        return "started \(-s / 60) min ago"
    }

    static func joinURL(for event: EKEvent) -> URL? {
        var haystack = [event.location ?? "", event.notes ?? "", event.url?.absoluteString ?? ""].joined(separator: " ")
        haystack = haystack.replacingOccurrences(of: "\n", with: " ")
        let pattern = #"https?://[^\s<>"']*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|around\.co|facetime\.apple\.com|slack\.com/call|discord\.gg)[^\s<>"']*"#
        if let r = haystack.range(of: pattern, options: .regularExpression) { return URL(string: String(haystack[r])) }
        if let url = event.url, ["http", "https"].contains(url.scheme ?? "") { return url }
        return nil
    }

    static func isVideoCall(_ event: EKEvent) -> Bool { joinURL(for: event) != nil }
}
