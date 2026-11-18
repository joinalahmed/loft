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
    var hasSource: Bool { Demo.active || authorized || GoogleCalendarService.shared.isConnected }

    func injectDemo(events demo: [MeetingEvent]) {
        events = demo.sorted { $0.startDate < $1.startDate }
        browsed = Dictionary(grouping: events, by: { Self.monthKey($0.startDate) })
        tick()
    }

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
        guard !Demo.active else { return }
        if authorized {
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 2, to: start)!
            let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            appleEvents = store.events(matching: pred).map(MeetingEvent.init)
        } else { appleEvents = [] }
        GoogleCalendarService.shared.sync()
        mergeSources()
        // Refresh every month already on screen in place, so the grid never blanks out.
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        for key in browsed.keys { if let d = f.date(from: key) { loadMonth(containing: d, force: true) } }
    }

    /// Called by either source after it refreshes. Drops Google events that also arrive via a
    /// Google account added to macOS, so a meeting never shows (or alerts) twice.
    func mergeSources() {
        guard !Demo.active else { return }
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
        guard !Demo.active, force || (browsed[key] == nil && !browsing.contains(key)) else { return }
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
        if Demo.active { return ["Google (Work)", "iCloud"] }
        var names = authorized ? Set(store.calendars(for: .event).map { $0.source.title }) : []
        if GoogleCalendarService.shared.isConnected { names.insert("Google" + (GoogleCalendarService.shared.accountEmail.isEmpty ? "" : " (\(GoogleCalendarService.shared.accountEmail))")) }
        return names.sorted()
    }

    // MARK: Adding and deleting events

    /// A calendar new events can be saved to, from either source.
    struct Target: Identifiable, Hashable {
        let id: String            // "ek:<identifier>" or "g:<calendar id>"
        let source: MeetingEvent.Source
        let name: String
        let account: String
        let color: Color
    }

    struct Draft {
        var title = ""
        var day: Date
        var start: Date           // only the time of day is used
        var minutes = 30
        var allDay = false
        var location = ""
        var targetID = ""
    }

    /// Set while the calendar tab shows the new-event form.
    @Published var composing = false

    var targets: [Target] {
        if Demo.active {
            return [Target(id: "demo:work", source: .google, name: "Work", account: "Google", color: .green),
                    Target(id: "demo:personal", source: .apple, name: "Personal", account: "iCloud", color: .orange)]
        }
        var out: [Target] = []
        if authorized {
            out += store.calendars(for: .event).filter(\.allowsContentModifications)
                .map { Target(id: "ek:" + $0.calendarIdentifier, source: .apple, name: $0.title, account: $0.source.title, color: Color(cgColor: $0.cgColor)) }
                .sorted { ($0.account, $0.name) < ($1.account, $1.name) }
        }
        let g = GoogleCalendarService.shared
        if g.isConnected && g.canWrite {
            out += g.calendars.filter(\.writable).sorted { $0.primary && !$1.primary }
                .map { Target(id: "g:" + $0.id, source: .google, name: $0.name, account: "Google", color: $0.color) }
        }
        return out
    }

    /// Last calendar used, else the system default, else the primary Google calendar.
    var defaultTargetID: String {
        let all = targets
        if let last = UserDefaults.standard.string(forKey: "calendarAddTarget"), all.contains(where: { $0.id == last }) { return last }
        if authorized, let d = store.defaultCalendarForNewEvents, let t = all.first(where: { $0.id == "ek:" + d.calendarIdentifier }) { return t.id }
        return all.first?.id ?? ""
    }

    /// Saves the draft to its calendar. Returns an error message, or nil on success.
    /// `remember` makes the calendar the default for the next manual add.
    func add(_ draft: Draft, remember: Bool = true, reload refresh: Bool = true) async -> String? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "Give the event a title." }
        guard let target = targets.first(where: { $0.id == draft.targetID }) else { return "Pick a calendar to add it to." }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: draft.day)
        let time = cal.dateComponents([.hour, .minute], from: draft.start)
        let start = draft.allDay ? dayStart : (cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: dayStart) ?? dayStart)
        let end = draft.allDay ? dayStart : start.addingTimeInterval(TimeInterval(max(5, draft.minutes) * 60))
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)

        if Demo.active {
            let ev = MeetingEvent(id: "demo:new-" + UUID().uuidString, title: title, startDate: start, endDate: draft.allDay ? start.addingTimeInterval(86400) : end,
                                  isAllDay: draft.allDay, location: location.isEmpty ? nil : location, calendarTitle: target.name, color: target.color,
                                  source: target.source, editable: true)
            injectDemo(events: events + [ev])
            return nil
        }
        switch target.source {
        case .apple:
            guard authorized, let calendar = store.calendar(withIdentifier: String(target.id.dropFirst(3))) else { return "That calendar is no longer available." }
            let ev = EKEvent(eventStore: store)
            ev.title = title; ev.startDate = start; ev.endDate = end; ev.isAllDay = draft.allDay; ev.calendar = calendar
            if !location.isEmpty { ev.location = location }
            do { try store.save(ev, span: .thisEvent, commit: true) } catch { return error.localizedDescription }
        case .google:
            if let err = await GoogleCalendarService.shared.createEvent(title: title, start: start, end: end, allDay: draft.allDay,
                                                                        location: location, calendarID: String(target.id.dropFirst(2))) { return err }
        }
        if remember { UserDefaults.standard.set(target.id, forKey: "calendarAddTarget") }
        if refresh { reload() }
        return nil
    }

    func canDelete(_ ev: MeetingEvent) -> Bool {
        guard ev.editable else { return false }
        if Demo.active { return true }
        return ev.source == .apple ? authorized : (GoogleCalendarService.shared.canWrite && ev.calendarID != nil)
    }

    /// Removes one event (only this occurrence when it repeats). Returns an error message, or nil.
    func delete(_ ev: MeetingEvent, reload refresh: Bool = true) async -> String? {
        guard canDelete(ev) else { return "This event cannot be deleted from Loft." }
        if Demo.active { injectDemo(events: events.filter { $0.id != ev.id }); return nil }
        switch ev.source {
        case .apple:
            let pred = store.predicateForEvents(withStart: ev.startDate.addingTimeInterval(-60), end: ev.endDate.addingTimeInterval(60), calendars: nil)
            guard let match = store.events(matching: pred).first(where: { MeetingEvent($0).id == ev.id }) else { return "The event is no longer in the calendar." }
            do { try store.remove(match, span: .thisEvent, commit: true) } catch { return error.localizedDescription }
        case .google:
            if let err = await GoogleCalendarService.shared.deleteEvent(ev) { return err }
        }
        if refresh { reload() }
        return nil
    }

    /// Every event in a date range from both sources (not deduplicated), read fresh.
    func events(from start: Date, to end: Date) async -> [MeetingEvent] {
        if Demo.active { return events.filter { $0.startDate >= start && $0.startDate < end } }
        var out: [MeetingEvent] = []
        if authorized { out = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).map(MeetingEvent.init) }
        return out + (await GoogleCalendarService.shared.events(from: start, to: end))
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
            if PrayerTimesService.isBlock(ev) && prefs.salahFullScreenAlert { alerted.insert(id); continue }   // announced at prayer time instead
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
