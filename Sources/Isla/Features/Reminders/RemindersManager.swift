import EventKit
import SwiftUI
import Combine

@MainActor
final class RemindersManager: ObservableObject {
    static let shared = RemindersManager()
    @Published private(set) var reminders: [EKReminder] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    private let store = EKEventStore()
    private var cancellable: AnyCancellable?
    private init() {
        cancellable = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .sink { [weak self] _ in Task { @MainActor in self?.reload() } }
        checkStatus()
    }

    func checkStatus() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        authorized = status == .fullAccess
        denied = status == .denied || status == .restricted
        if authorized { reload() }
    }

    func requestAccess() {
        Task {
            let ok = (try? await store.requestFullAccessToReminders()) ?? false
            authorized = ok; denied = !ok
            if ok { reload() }
        }
    }

    func reload() {
        guard authorized else { return }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: pred) { [weak self] items in
            let sorted = (items ?? []).sorted { a, b in
                let da = a.dueDateComponents?.date ?? .distantFuture, db = b.dueDateComponents?.date ?? .distantFuture
                if da != db { return da < db }
                return a.priority != b.priority ? (a.priority == 0 ? false : b.priority == 0 ? true : a.priority < b.priority) : (a.title ?? "") < (b.title ?? "")
            }
            Task { @MainActor in self?.reminders = sorted }
        }
    }

    var overdue: [EKReminder] { reminders.filter { ($0.dueDateComponents?.date ?? .distantFuture) < Calendar.current.startOfDay(for: Date()) } }
    var today: [EKReminder] { reminders.filter { $0.dueDateComponents?.date.map { Calendar.current.isDateInToday($0) } ?? false } }
    var later: [EKReminder] { reminders.filter { r in !overdue.contains(r) && !today.contains(r) } }

    func complete(_ r: EKReminder) {
        r.isCompleted = true
        try? store.save(r, commit: true)
        reminders.removeAll { $0.calendarItemIdentifier == r.calendarItemIdentifier }
        Haptics.tap()
    }

    func add(_ title: String, dueToday: Bool) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let cal = store.defaultCalendarForNewReminders() else { return }
        let r = EKReminder(eventStore: store)
        r.title = t; r.calendar = cal
        if dueToday {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date()); c.hour = 18
            r.dueDateComponents = c
        }
        try? store.save(r, commit: true)
        reload()
    }
}
