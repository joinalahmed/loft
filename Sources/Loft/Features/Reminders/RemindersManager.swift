import EventKit
import SwiftUI
import Combine
import AppKit

@MainActor
final class RemindersManager: ObservableObject {
    static let shared = RemindersManager()
    @Published private(set) var reminders: [EKReminder] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    private let store = EKEventStore()
    private var cancellable: AnyCancellable?
    private var ticker: Timer?
    private var alerted: Set<String> = []
    private init() {
        cancellable = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .sink { [weak self] _ in Task { @MainActor in self?.reload() } }
        checkStatus()
        ticker = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkDue() } }
        ticker?.tolerance = 5
    }

    /// Reminders whose due time just passed get a full-screen (or island) alert, like meetings.
    private func checkDue() {
        guard authorized, Preferences.shared.reminderAlerts else { return }
        let now = Date()
        for r in reminders {
            guard let comps = r.dueDateComponents, comps.hour != nil, let due = comps.date else { continue }
            let key = r.calendarItemIdentifier + "|" + String(Int(due.timeIntervalSince1970))
            guard due <= now, now.timeIntervalSince(due) < 90, !alerted.contains(key) else { continue }
            alerted.insert(key)
            alert(r)
        }
    }

    func alert(_ r: EKReminder) {
        let title = r.title ?? "Reminder"
        let accent = Color(cgColor: r.calendar.cgColor).ensureMinimumBrightness(0.6)
        if Preferences.shared.reminderAlertFullScreen {
            NSSound(named: "Glass")?.play()
            FullScreenAlertController.shared.show(FullScreenAlert(
                eyebrow: "Reminders · \(r.calendar.title)", accent: accent, symbol: "checklist", title: title,
                detail: r.dueDateComponents?.date.map { "Due \($0.shortTime)" } ?? nil,
                footnote: r.notes?.components(separatedBy: .newlines).first, countdown: nil, actions: [
                    .init(title: "Dismiss", style: .quiet, key: .escape, hint: "esc") {},
                    .init(title: "Snooze 10 min", symbol: "zzz", style: .secondary, key: "s", hint: "S") { [weak self] in self?.snooze(r, minutes: 10) },
                    .init(title: "Complete", symbol: "checkmark", style: .primary, key: .return, hint: "↩") { [weak self] in self?.complete(r) },
                ], autoDismiss: 120))
        } else {
            NotchViewModel.shared.show(message: IslandMessage(title: title, subtitle: "Reminder due", symbol: "checklist", tint: accent, action: { [weak self] in self?.complete(r) }), duration: 8)
        }
    }

    func snooze(_ r: EKReminder, minutes: Int) {
        let newDue = Date().addingTimeInterval(TimeInterval(minutes * 60))
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: newDue)
        try? store.save(r, commit: true)
        reload()
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
