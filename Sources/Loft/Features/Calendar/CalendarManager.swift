import EventKit
import SwiftUI
import Combine
import AppKit

/// Merges Apple Calendar accounts (EventKit) and a directly connected Google account into one
/// list of `MeetingEvent`s, and raises meeting alerts from it.
@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    @Published private(set) var events: [MeetingEvent] = []
    @Published private(set) var authorized = false            // EventKit full access
    @Published private(set) var denied = false
    @Published private(set) var imminentEvent: MeetingEvent?  // drives the pill countdown
    @Published private(set) var now = Date()
    private let store = EKEventStore()
    private var appleEvents: [MeetingEvent] = []
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
        _ = GoogleCalendarService.shared
    }

    /// True when at least one source can deliver events.
    var hasSource: Bool { authorized || GoogleCalendarService.shared.isConnected }

    func checkStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = status == .fullAccess
        denied = status == .denied || status == .restricted || status == .writeOnly
        if authorized { reload() } else { mergeSources() }
    }

    func requestAccess() {
        Task {
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            authorized = ok; denied = !ok
            if ok { reload() }
        }
    }

    /// Apple accounts (iCloud, Google-via-macOS, Outlook, CalDAV) arrive through EventKit.
    func reload() {
        if authorized {
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 2, to: start)!
            let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            appleEvents = store.events(matching: pred).map(MeetingEvent.init)
        } else { appleEvents = [] }
        GoogleCalendarService.shared.sync()
        mergeSources()
        if !browsed.isEmpty { browsed.removeAll(); loadMonth(containing: Date()) }
    }

    /// Called by either source after it refreshes. Drops Google events that also arrive via a
    /// Google account added to macOS, so a meeting never shows (or alerts) twice.
    func mergeSources() {
        var seen = Set(appleEvents.map(\.dedupeKey))
        var merged = appleEvents
        for ev in GoogleCalendarService.shared.events where !seen.contains(ev.dedupeKey) {
            seen.insert(ev.dedupeKey); merged.append(ev)
        }
        events = merged.sorted { $0.startDate < $1.startDate }
        tick()
    }

    // MARK: Browsing other days (month view)

    @Published private(set) var browsed: [String: [MeetingEvent]] = [:]   // "yyyy-MM" → events in that month
    private var browsing: Set<String> = []

    static func monthKey(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: date) }

    /// Loads a whole month (Apple + Google, deduped) once; the view reads `browsed`.
    func loadMonth(containing date: Date, force: Bool = false) {
        let key = Self.monthKey(date)
        guard force || (browsed[key] == nil && !browsing.contains(key)) else { return }
        browsing.insert(key)
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        var apple: [MeetingEvent] = []
        if authorized {
            apple = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).map(MeetingEvent.init)
        }
        Task { [weak self] in
            let google = await GoogleCalendarService.shared.events(from: start, to: end)
            guard let self else { return }
            var seen = Set(apple.map(\.dedupeKey)); var merged = apple
            for ev in google where !seen.contains(ev.dedupeKey) { seen.insert(ev.dedupeKey); merged.append(ev) }
            self.browsed[key] = merged.sorted { $0.startDate < $1.startDate }
            self.browsing.remove(key)
        }
    }

    func events(on day: Date) -> [MeetingEvent] {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return todayEvents }
        return (browsed[Self.monthKey(day)] ?? []).filter { ev in
            ev.isAllDay ? (cal.isDate(ev.startDate, inSameDayAs: day) || (ev.startDate < day && ev.endDate > cal.startOfDay(for: day).addingTimeInterval(1)))
                        : cal.isDate(ev.startDate, inSameDayAs: day)
        }
    }

    func hasEvents(on day: Date) -> Bool { !events(on: day).isEmpty }

    var calendarSources: [String] {
        var names = authorized ? Set(store.calendars(for: .event).map { $0.source.title }) : []
        if GoogleCalendarService.shared.isConnected { names.insert("Google" + (GoogleCalendarService.shared.accountEmail.isEmpty ? "" : " (\(GoogleCalendarService.shared.accountEmail))")) }
        return names.sorted()
    }

    var todayEvents: [MeetingEvent] { events.filter { Calendar.current.isDateInToday($0.startDate) } }

    var nextEvent: MeetingEvent? { events.first { !$0.isAllDay && !$0.canceled && !$0.declined && $0.endDate > now } }

    // MARK: Meeting alerts

    private func tick() {
        now = Date()
        guard hasSource else { imminentEvent = nil; return }
        let pillWindow = TimeInterval(prefs.meetingPillMinutes * 60)
        imminentEvent = events.first { ev in
            !ev.isAllDay && !ev.canceled && !ev.declined && ev.startDate.timeIntervalSince(now) <= pillWindow && ev.endDate > now
                && ev.startDate.timeIntervalSince(now) > -120
        }
        guard prefs.meetingAlertsEnabled else { return }
        let lead = TimeInterval(prefs.meetingLeadMinutes * 60)
        for ev in events where !ev.isAllDay && !ev.canceled {
            let id = ev.id
            let until = ev.startDate.timeIntervalSince(now)
            if let snoozeUntil = snoozed[id] {
                if now >= snoozeUntil, until > -600 { snoozed[id] = nil; fire(ev) }
                continue
            }
            guard !alerted.contains(id), until <= lead, until > -60 else { continue }
            if prefs.meetingAlertOnlyWithLinks && ev.joinURL == nil { continue }
            if ev.declined { continue }
            alerted.insert(id)
            fire(ev)
        }
    }

    private func fire(_ ev: MeetingEvent) {
        if prefs.meetingAlertSound { NSSound(named: "Ping")?.play() }
        if prefs.meetingAlertFullScreen {
            MeetingAlertController.shared.show(event: ev)
        } else {
            let url = ev.joinURL
            NotchViewModel.shared.show(message: IslandMessage(
                title: ev.title, subtitle: ev.relativeStart, symbol: url == nil ? "calendar" : "video.fill",
                tint: .green, action: url.map { u in { NSWorkspace.shared.open(u) } }), duration: 20)
        }
    }

    func snooze(_ ev: MeetingEvent, minutes: Int = 1) {
        snoozed[ev.id] = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func testAlert() {
        let ev = MeetingEvent(id: "test", title: "Design review", startDate: Date().addingTimeInterval(120), endDate: Date().addingTimeInterval(1920),
                              location: "https://meet.google.com/abc-defg-hij", calendarTitle: "Work", color: .green, attendeeCount: 4, source: .apple)
        fire(ev)
    }

    static func relativeStart(_ ev: MeetingEvent) -> String { ev.relativeStart }
    static func joinURL(for ev: MeetingEvent) -> URL? { ev.joinURL }
    static func isVideoCall(_ ev: MeetingEvent) -> Bool { ev.isVideoCall }
}
