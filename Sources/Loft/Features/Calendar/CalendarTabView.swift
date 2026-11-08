import SwiftUI

/// Month grid on the left (‹ › to move, click a day), that day's agenda on the right.
struct CalendarTabView: View {
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var google = GoogleCalendarService.shared
    @ObservedObject var prefs = Preferences.shared
    @State private var month: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var selected: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        if !cal.hasSource {
            connectView
        } else {
            HStack(alignment: .top, spacing: 14) {
                MonthGrid(month: $month, selected: $selected)
                    .frame(width: 236)
                    .onAppear { cal.loadMonth(containing: month) }
                    .onChange(of: month) { _, m in cal.loadMonth(containing: m) }
                agenda
            }
        }
    }

    private var agenda: some View {
        let events = cal.events(on: selected)
        let isToday = Calendar.current.isDateInToday(selected)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(selected, format: .dateTime.weekday(.wide)).font(.system(size: 10, weight: .semibold)).foregroundStyle(isToday ? .orange : .secondary)
                    Text(selected, format: .dateTime.day().month(.wide)).font(.system(size: 14, weight: .bold))
                }
                Spacer()
                if !isToday {
                    Button("Today") { selected = Calendar.current.startOfDay(for: Date()); month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))! }
                        .buttonStyle(.loftGlass).controlSize(.mini)
                }
                if isToday, let url = cal.nextEvent?.joinURL {
                    Button { NSWorkspace.shared.open(url) } label: { Label("Join next", systemImage: "video.fill") }
                        .buttonStyle(.loftProminent(.green)).controlSize(.mini)
                }
                Button { openInCalendar(selected) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.loftGlass).controlSize(.mini).help("Open this day in Calendar")
            }
            if events.isEmpty {
                EmptyHint(symbol: isToday ? "sun.max" : "calendar", title: isToday ? "Nothing more today" : "Nothing scheduled",
                          subtitle: cal.calendarSources.isEmpty ? nil : "Synced from \(cal.calendarSources.joined(separator: ", ")).")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(events) { ev in EventRow(event: ev) }
                        Color.clear.frame(height: 10)
                    }
                }
                .scrollIndicators(.never)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            HStack {
                Text("Alerts \(prefs.meetingLeadMinutes) min before · \(cal.calendarSources.count) source\(cal.calendarSources.count == 1 ? "" : "s")")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("Preview alert") { cal.testAlert() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func openInCalendar(_ day: Date) {
        // Calendar.app accepts a Unix timestamp to show a specific day.
        NSWorkspace.shared.open(URL(string: "ical://showdate?\(Int(day.timeIntervalSince1970))")!)
    }

    private var connectView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(.white.opacity(0.06)).frame(width: 44, height: 44)
                Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(cal.denied ? "Calendar access was declined" : "Show today's meetings in the notch").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                if cal.denied {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
                } else {
                    Button("Use Apple Calendar") { cal.requestAccess() }
                }
                Button(google.isConnecting ? "Waiting for Google…" : "Connect Google Calendar") { SettingsWindowController.shared.show(tab: .features) }
                    .disabled(google.isConnecting)
            }
            .buttonStyle(.loftProminent()).controlSize(.small)
            Text("Apple Calendar covers every account in System Settings. Connect Google directly to sync without adding it to macOS.")
                .font(.system(size: 10)).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact month: weekday header, 6 rows, dots for days with events, today ringed, selection filled.
struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selected: Date
    @ObservedObject var cal = CalendarManager.shared
    @Environment(\.islandTint) private var tint
    private let calendar = Calendar.current

    private var days: [Date?] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in 0..<count { cells.append(calendar.date(byAdding: .day, value: d, to: first)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var weekdaySymbols: [String] {
        let s = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(s[start...] + s[..<start])
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(month, format: .dateTime.month(.wide).year()).font(.system(size: 12, weight: .bold))
                Spacer()
                SmallIconButton(symbol: "chevron.left", size: 10, help: "Previous month") { shift(-1) }
                SmallIconButton(symbol: "circle.fill", size: 6, help: "This month") { month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))! }
                SmallIconButton(symbol: "chevron.right", size: 10, help: "Next month") { shift(1) }
            }
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { d in
                    Text(d).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }
            }
            let rows = days.count / 7
            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in
                            let day = days[r * 7 + c]
                            DayCell(day: day, selected: day.map { calendar.isDate($0, inSameDayAs: selected) } ?? false,
                                    today: day.map { calendar.isDateInToday($0) } ?? false,
                                    hasEvents: day.map { cal.hasEvents(on: $0) } ?? false,
                                    weekend: day.map { calendar.isDateInWeekend($0) } ?? false, tint: tint) {
                                if let day { withAnimation(.smooth(duration: 0.15)) { selected = day } }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: cal.browsed.count) { _, _ in }   // re-render dots when a month finishes loading
    }

    private func shift(_ by: Int) {
        withAnimation(.smooth(duration: 0.2)) {
            month = calendar.date(byAdding: .month, value: by, to: month)!
            // Keep the selection inside the visible month so the agenda follows along.
            if !calendar.isDate(selected, equalTo: month, toGranularity: .month) {
                selected = calendar.isDate(month, equalTo: Date(), toGranularity: .month) ? calendar.startOfDay(for: Date()) : month
            }
        }
    }
}

private struct DayCell: View {
    let day: Date?
    let selected: Bool
    let today: Bool
    let hasEvents: Bool
    let weekend: Bool
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if let day {
                    Text(Calendar.current.component(.day, from: day), format: .number)
                        .font(.system(size: 11, weight: selected || today ? .bold : .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(selected ? .black : today ? tint : weekend ? .white.opacity(0.55) : .white.opacity(0.9))
                    Circle().fill(hasEvents ? (selected ? Color.black.opacity(0.7) : tint) : .clear).frame(width: 3, height: 3)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 22)
            .background {
                if selected { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint) }
                else if today { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(tint.opacity(0.6), lineWidth: 1) }
                else if hover && day != nil { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.1)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
        .onHover { hover = $0 }
    }
}

struct EventRow: View {
    let event: MeetingEvent
    var compact = false
    var body: some View {
        let past = event.endDate < Date()
        let live = event.startDate <= Date() && !past
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).strikethrough(event.declined || event.canceled)
                    if live { Circle().fill(.green).frame(width: 5, height: 5) }
                    if event.source == .google { Image(systemName: "g.circle").font(.system(size: 9)).foregroundStyle(.tertiary) }
                }
                Text(event.isAllDay ? "All day" : "\(event.startDate.shortTime) – \(event.endDate.shortTime)" + (event.displayLocation.map { " · \($0)" } ?? "") + (event.attendeeCount > 1 ? " · \(event.attendeeCount) people" : ""))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !past, let url = event.joinURL, !compact {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.loftProminent()).controlSize(.mini).tint(.green)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.white.opacity(past ? 0.03 : 0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(live ? Color.green.opacity(0.35) : .clear, lineWidth: 0.5))
        .opacity(past ? 0.55 : 1)
    }
}
