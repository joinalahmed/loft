import SwiftUI

/// In-memory sample content for screenshots and demos. Started from the local API (`demo`);
/// nothing is written to disk and the real sources stop updating until the app quits.
@MainActor
enum Demo {
    private(set) static var active = false

    static func start() {
        active = true
        let now = Date(), cal = Calendar.current
        func at(_ hour: Int, _ minute: Int, day: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: day, to: now)!)!
        }
        func ev(_ id: String, _ title: String, _ start: Date, minutes: Int, url: String? = nil, calendar: String = "Work",
                color: Color = .green, people: Int = 0, source: MeetingEvent.Source = .google, allDay: Bool = false) -> MeetingEvent {
            MeetingEvent(id: "demo:" + id, title: title, startDate: start, endDate: start.addingTimeInterval(Double(minutes) * 60), isAllDay: allDay,
                         url: url.flatMap(URL.init(string:)), calendarTitle: calendar, color: color, attendeeCount: people, source: source)
        }
        var events: [MeetingEvent] = [
            ev("1", "Design review", now.addingTimeInterval(12 * 60), minutes: 30, url: "https://meet.google.com/abc-defg-hij", people: 4),
            ev("2", "1:1 with Sam", now.addingTimeInterval(130 * 60), minutes: 30, url: "https://zoom.us/j/123456789", people: 2),
            ev("3", "Sprint planning", now.addingTimeInterval(250 * 60), minutes: 60, url: "https://teams.microsoft.com/l/meetup-join/demo", people: 7),
            ev("4", "Gym", at(18, 30), minutes: 60, calendar: "Personal", color: .orange, source: .apple),
        ]
        // Scatter the rest of the month so the calendar grid has dots to show.
        for (i, day) in [-5, -4, -1, 1, 2, 3, 6, 8, 9, 13, 15, 16, 20, 22].enumerated() {
            let titles = ["Team sync", "Roadmap", "Customer call", "Release train", "Office hours", "Retro", "Dentist"]
            events.append(ev("m\(i)", titles[i % titles.count], at(9 + (i % 6), i % 2 == 0 ? 0 : 30, day: day), minutes: 30 + 15 * (i % 3),
                             url: i % 3 == 0 ? "https://meet.google.com/xyz-demo" : nil, calendar: i % 4 == 3 ? "Personal" : "Work",
                             color: i % 4 == 3 ? .orange : .green, people: 2 + i % 5, source: i % 4 == 3 ? .apple : .google))
        }
        CalendarManager.shared.injectDemo(events: events)

        MusicManager.shared.injectDemo(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                                       duration: 244, elapsed: 65, artwork: artwork(), accent: Color(red: 0.86, green: 0.36, blue: 0.47))

        ClipboardManager.shared.injectDemo([
            ClipItem(id: UUID(), kind: .color, text: "#FF6B35", date: now.addingTimeInterval(-40), sourceBundle: "com.figma.Desktop"),
            ClipItem(id: UUID(), kind: .text, text: "Ship the launch build before lunch, then write the release notes.", date: now.addingTimeInterval(-300), sourceBundle: "com.apple.Notes"),
            ClipItem(id: UUID(), kind: .url, text: "https://developer.apple.com/documentation/swiftui", date: now.addingTimeInterval(-1500), sourceBundle: "com.apple.Safari"),
            ClipItem(id: UUID(), kind: .text, text: "swift build -c release --arch arm64 --arch x86_64", date: now.addingTimeInterval(-5400), pinned: true, sourceBundle: "com.apple.Terminal"),
        ])

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        WeatherService.shared.injectDemo(WeatherSnapshot(place: "San Francisco", temperature: 18, feelsLike: 17, humidity: 62, windKph: 14, code: 2,
            daily: (0..<5).map { WeatherSnapshot.Day(date: f.string(from: cal.date(byAdding: .day, value: $0, to: now)!), hi: [19, 21, 20, 17, 18][$0], lo: [12, 13, 13, 11, 12][$0], code: [2, 0, 1, 61, 3][$0]) },
            fetchedAt: now))

        WorldClockStore.shared.injectDemo(["Europe/London", "America/New_York", "Asia/Tokyo"])
        KeepAwakeManager.shared.acquire(minutes: 60)
    }

    /// A warm gradient square with a soft disc, so screenshots never show a real album cover.
    private static func artwork() -> NSImage {
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [NSColor(red: 0.98, green: 0.52, blue: 0.36, alpha: 1), NSColor(red: 0.78, green: 0.33, blue: 0.56, alpha: 1), NSColor(red: 0.42, green: 0.24, blue: 0.70, alpha: 1)])!
        gradient.draw(in: NSRect(origin: .zero, size: size), angle: -60)
        NSColor(white: 1, alpha: 0.92).setFill()
        NSBezierPath(ovalIn: NSRect(x: 100, y: 100, width: 100, height: 100)).fill()
        image.unlockFocus()
        return image
    }
}
