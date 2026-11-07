import EventKit
import SwiftUI

/// Source-independent event used everywhere in the UI, so Apple Calendar accounts and a
/// directly connected Google account render, alert and join exactly the same way.
struct MeetingEvent: Identifiable, Equatable {
    enum Source: String { case apple, google }
    let id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var url: URL?
    var calendarTitle: String
    var color: Color
    var attendeeCount: Int
    var declined: Bool
    var canceled: Bool
    var source: Source

    static func == (a: MeetingEvent, b: MeetingEvent) -> Bool { a.id == b.id && a.startDate == b.startDate && a.title == b.title }

    /// Title + start minute, used to drop the same meeting arriving from two sources.
    var dedupeKey: String { title.lowercased().trimmingCharacters(in: .whitespaces) + "|" + String(Int(startDate.timeIntervalSince1970 / 60)) }

    var joinURL: URL? {
        var haystack = [location ?? "", notes ?? "", url?.absoluteString ?? ""].joined(separator: " ")
        haystack = haystack.replacingOccurrences(of: "\n", with: " ")
        let pattern = #"https?://[^\s<>"']*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|around\.co|facetime\.apple\.com|slack\.com/call|discord\.gg)[^\s<>"']*"#
        if let r = haystack.range(of: pattern, options: .regularExpression) { return URL(string: String(haystack[r])) }
        if let url, ["http", "https"].contains(url.scheme ?? "") { return url }
        return nil
    }
    var isVideoCall: Bool { joinURL != nil }

    /// Location worth showing: not a bare link that duplicates the join URL.
    var displayLocation: String? {
        guard let l = location?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty, !l.hasPrefix("http") else { return nil }
        return l
    }

    var relativeStart: String {
        let s = Int(startDate.timeIntervalSinceNow.rounded())
        if s > 90 { return "in \(s / 60) min" }
        if s > 0 { return "in \(s) s" }
        if s > -90 { return "starting now" }
        return "started \(-s / 60) min ago"
    }

    init(id: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool = false, location: String? = nil, notes: String? = nil, url: URL? = nil,
         calendarTitle: String, color: Color, attendeeCount: Int = 0, declined: Bool = false, canceled: Bool = false, source: Source) {
        self.id = id; self.title = title; self.startDate = startDate; self.endDate = endDate; self.isAllDay = isAllDay
        self.location = location; self.notes = notes; self.url = url; self.calendarTitle = calendarTitle; self.color = color
        self.attendeeCount = attendeeCount; self.declined = declined; self.canceled = canceled; self.source = source
    }

    init(_ ev: EKEvent) {
        let me = ev.attendees?.first(where: { $0.isCurrentUser })
        self.init(id: "ek:" + (ev.eventIdentifier ?? ev.calendarItemIdentifier) + ":" + String(Int(ev.startDate.timeIntervalSince1970)),
                  title: ev.title ?? "Untitled", startDate: ev.startDate, endDate: ev.endDate, isAllDay: ev.isAllDay,
                  location: ev.location, notes: ev.notes, url: ev.url,
                  calendarTitle: ev.calendar?.title ?? "Calendar",
                  color: Color(cgColor: ev.calendar?.cgColor ?? NSColor.systemBlue.cgColor),
                  attendeeCount: ev.attendees?.count ?? 0,
                  declined: me?.participantStatus == .declined, canceled: ev.status == .canceled, source: .apple)
    }
}
