import AppKit
import SwiftUI

/// Meeting flavour of the shared full-screen alert: Join / Snooze / Dismiss on every display.
@MainActor
final class MeetingAlertController {
    static let shared = MeetingAlertController()
    private(set) var current: MeetingEvent?
    private init() {}

    func show(event: MeetingEvent) {
        current = event
        let url = event.joinURL
        let accent = event.color.ensureMinimumBrightness(0.6)
        var detailParts = ["\(event.startDate.shortTime) – \(event.endDate.shortTime)"]
        if let location = event.displayLocation { detailParts.append(location) }
        if event.attendeeCount > 1 { detailParts.append("\(event.attendeeCount) people") }

        var actions: [FullScreenAlert.Action] = [
            .init(title: "Dismiss", style: .quiet, key: .escape, hint: "esc") { [weak self] in self?.current = nil },
            .init(title: "Snooze 1 min", symbol: "zzz", style: .secondary, key: "s", hint: "S") { [weak self] in self?.snooze(minutes: 1) },
        ]
        if url != nil {
            actions.append(.init(title: "Join", symbol: "video.fill", style: .primary, key: .return, hint: "↩") { [weak self] in self?.join() })
        } else {
            actions.append(.init(title: "Open Calendar", symbol: "calendar", style: .primary, key: .return, hint: "↩") { [weak self] in
                NSWorkspace.shared.open(URL(string: "ical://")!); self?.current = nil
            })
        }
        FullScreenAlertController.shared.show(FullScreenAlert(
            eyebrow: event.calendarTitle + (event.source == .google ? " · Google" : ""), accent: accent, symbol: url == nil ? "calendar" : "video.fill",
            title: event.title, detail: detailParts.joined(separator: " · "),
            footnote: url?.host, countdown: { event.relativeStart }, actions: actions, autoDismiss: 90))
    }

    func join() {
        if let url = current?.joinURL { NSWorkspace.shared.open(url) }
        current = nil
        FullScreenAlertController.shared.dismiss()
    }

    func snooze(minutes: Int = 1) {
        if let ev = current { CalendarManager.shared.snooze(ev, minutes: minutes) }
        current = nil
        FullScreenAlertController.shared.dismiss()
    }

    func dismiss() { current = nil; FullScreenAlertController.shared.dismiss() }
}
