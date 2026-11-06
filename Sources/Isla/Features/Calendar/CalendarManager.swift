import EventKit
import SwiftUI
import Combine

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    private let store = EKEventStore()
    private var cancellable: AnyCancellable?
    private var refreshTimer: Timer?

    private init() {
        cancellable = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .sink { [weak self] _ in Task { @MainActor in self?.reload() } }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
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

    func reload() {
        guard authorized else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 2, to: start)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    var todayEvents: [EKEvent] {
        events.filter { Calendar.current.isDateInToday($0.startDate) || ($0.isAllDay && Calendar.current.isDateInToday($0.startDate)) }
    }

    var nextEvent: EKEvent? {
        events.first { !$0.isAllDay && $0.endDate > Date() }
    }

    static func joinURL(for event: EKEvent) -> URL? {
        var haystack = [event.location ?? "", event.notes ?? "", event.url?.absoluteString ?? ""].joined(separator: " ")
        haystack = haystack.replacingOccurrences(of: "\n", with: " ")
        let pattern = #"https?://[^\s<>"']*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com|whereby\.com|around\.co)[^\s<>"']*"#
        guard let r = haystack.range(of: pattern, options: .regularExpression) else { return event.url }
        return URL(string: String(haystack[r]))
    }
}
