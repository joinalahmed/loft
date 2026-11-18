import SwiftUI

/// Month grid on the left (‹ › to move, click a day, double-click to add an event), that day's
/// agenda on the right. "+" swaps the agenda for the new-event form.
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
                MonthGrid(month: $month, selected: $selected) { cal.composing = true }
                    .frame(width: 236)
                    .onAppear { cal.loadMonth(containing: month) }
                    .onChange(of: month) { _, m in cal.loadMonth(containing: m) }
                if cal.composing {
                    NewEventForm(day: selected) { cal.composing = false }
                        .transition(.opacity)
                } else {
                    agenda.transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.18), value: cal.composing)
            .onDisappear { cal.composing = false }
        }
    }

    private var agenda: some View {
        let isToday = Calendar.current.isDateInToday(selected)
        let all = cal.events(on: selected)
        // Today leads with what is on now or next; all-day entries follow, and what has ended sinks to the bottom.
        let ahead = all.filter { !$0.isAllDay && $0.endDate > cal.now }
        let earlier = all.filter { !$0.isAllDay && $0.endDate <= cal.now }
        let events = isToday ? ahead + all.filter(\.isAllDay) : all
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
                Button { cal.composing = true } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(.loftProminent()).controlSize(.mini).help("Add an event on this day")
                Button { openInCalendar(selected) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.loftGlass).controlSize(.mini).help("Open this day in Calendar")
            }
            if all.isEmpty {
                EmptyHint(symbol: isToday ? "sun.max" : "calendar", title: isToday ? "Nothing more today" : "Nothing scheduled",
                          subtitle: cal.calendarSources.isEmpty ? nil : "Synced from \(cal.calendarSources.joined(separator: ", ")).")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(events) { ev in AgendaRow(event: ev) }
                        if isToday, !earlier.isEmpty {
                            HStack(spacing: 6) {
                                Text("EARLIER TODAY").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
                                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                            }
                            .padding(.top, events.isEmpty ? 0 : 4).padding(.horizontal, 2)
                            ForEach(earlier) { ev in AgendaRow(event: ev) }
                        }
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
    /// Double-clicking a day selects it and calls this (starts a new event).
    var onAdd: (() -> Void)? = nil
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
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                if let day { selected = day; onAdd?() }
                            })
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
    /// Shown as a trash button while the pointer is over the row.
    var onDelete: (() -> Void)? = nil
    @State private var hover = false
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
            if hover, let onDelete { SmallIconButton(symbol: "trash", size: 10, help: "Delete event", action: onDelete) }
            if !past, let url = event.joinURL, !compact {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.loftProminent()).controlSize(.mini).tint(.green)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.white.opacity(past ? 0.03 : 0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(live ? Color.green.opacity(0.35) : .clear, lineWidth: 0.5))
        .opacity(past ? 0.55 : 1)
        .onHover { hover = $0 }
    }
}

/// Agenda row that can be deleted: the trash button asks once, inline, before removing anything.
private struct AgendaRow: View {
    let event: MeetingEvent
    @ObservedObject var cal = CalendarManager.shared
    @State private var confirming = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        if confirming {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Delete “\(event.title)”?").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(error ?? "Removes it from \(event.calendarTitle). This cannot be undone.")
                        .font(.system(size: 10)).foregroundStyle(error == nil ? Color.secondary : .red).lineLimit(1)
                }
                Spacer()
                Button("Keep") { confirming = false; error = nil }.buttonStyle(.loftGlass).controlSize(.mini)
                Button(working ? "Deleting…" : "Delete") {
                    working = true
                    Task {
                        error = await cal.delete(event)
                        working = false
                        if error == nil { confirming = false }
                    }
                }
                .buttonStyle(.loftProminent(.red)).controlSize(.mini).disabled(working)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            EventRow(event: event, onDelete: cal.canDelete(event) ? { confirming = true } : nil)
        }
    }
}

/// Inline composer: title, time, length, place and calendar. The month grid stays live beside it,
/// so clicking another day moves the event there.
private struct NewEventForm: View {
    let day: Date
    let onDone: () -> Void
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var google = GoogleCalendarService.shared
    @Environment(\.islandTint) private var tint
    @State private var title = ""
    @State private var start = Date()
    @State private var minutes = 30
    @State private var allDay = false
    @State private var location = ""
    @State private var targetID = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case title, location }
    private static let lengths: [(Int, String)] = [(15, "15m"), (30, "30m"), (45, "45m"), (60, "1h"), (90, "1.5h"), (120, "2h")]

    private var targets: [CalendarManager.Target] { cal.targets }
    private var target: CalendarManager.Target? { targets.first { $0.id == targetID } ?? targets.first }
    private var googleNeedsConsent: Bool { google.isConnected && !google.canWrite }
    private var endTime: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("New event").font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    Text(day, format: .dateTime.weekday(.wide).day().month(.wide)).font(.system(size: 14, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                if !targets.isEmpty { calendarMenu }
            }
            if targets.isEmpty {
                noCalendar
            } else {
                field("Title", text: $title, symbol: "pencil", field: .title)
                HStack(spacing: 6) {
                    chip("All day", selected: allDay) { allDay.toggle() }
                    if !allDay {
                        DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.field).controlSize(.small).fixedSize()
                        ForEach(Self.lengths, id: \.0) { len in
                            chip(len.1, selected: minutes == len.0) { minutes = len.0 }
                        }
                        Spacer(minLength: 0)
                        Text("until \(endTime.shortTime)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 24)
                field("Location or meeting link", text: $location, symbol: "mappin.and.ellipse", field: .location)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(error ?? "Return to add · Esc to cancel").font(.system(size: 10))
                        .foregroundStyle(error == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.red)).lineLimit(2)
                    Spacer()
                    Button("Cancel", action: onDone).buttonStyle(.loftGlass).controlSize(.small)
                    Button(saving ? "Adding…" : "Add event", action: save)
                        .buttonStyle(.loftProminent()).controlSize(.small)
                        .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onExitCommand(perform: onDone)
        .onAppear {
            let vm = NotchViewModel.shared
            vm.pinnedOpen = true          // moving the pointer away must not throw the draft away
            vm.userInteracted()           // typing needs the keyboard
            targetID = cal.defaultTargetID
            start = Self.defaultStart(for: day)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .title }
        }
        .onDisappear { NotchViewModel.shared.pinnedOpen = false }
        .onChange(of: targets) { _, new in if !new.contains(where: { $0.id == targetID }) { targetID = cal.defaultTargetID } }
    }

    /// Next half hour when adding to today, 9:00 on any other day.
    private static func defaultStart(for day: Date) -> Date {
        let cal = Calendar.current
        guard cal.isDateInToday(day) else { return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day }
        let now = Date()
        let minute = cal.component(.minute, from: now)
        let base = cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)) ?? now
        let next = base.addingTimeInterval(TimeInterval((30 - minute % 30) * 60))
        return cal.isDateInToday(next) ? next : base
    }

    private func save() {
        guard !saving else { return }
        saving = true; error = nil
        let draft = CalendarManager.Draft(title: title, day: day, start: start, minutes: minutes, allDay: allDay, location: location, targetID: target?.id ?? "")
        Task {
            let err = await cal.add(draft)
            saving = false
            if let err { error = err } else { Haptics.tap(); onDone() }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, symbol: String, field: Field) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 14)
            TextField(placeholder, text: text).textFieldStyle(.plain).font(.system(size: 12))
                .focused($focus, equals: field).onSubmit(save)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(.white.opacity(focus == field ? 0.12 : 0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(focus == field ? tint.opacity(0.5) : .clear, lineWidth: 0.75))
        .contentShape(Capsule())
        .onTapGesture { NotchViewModel.shared.userInteracted(); focus = field }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 10.5, weight: selected ? .semibold : .medium)).monospacedDigit().lineLimit(1).fixedSize()
                .foregroundStyle(selected ? Color.black.opacity(0.9) : .white.opacity(0.85))
                .padding(.horizontal, 7).frame(height: 20)
                .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.09)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var calendarMenu: some View {
        Menu {
            ForEach(targets) { t in
                Button { targetID = t.id } label: { Text(t.account == t.name ? t.name : "\(t.name) · \(t.account)") }
            }
            if googleNeedsConsent {
                Divider()
                Button("Allow adding to Google Calendar…") { google.connect() }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(target?.color ?? .gray).frame(width: 7, height: 7)
                Text(target?.name ?? "Calendar").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 20).frame(maxWidth: 170)
            .background(.white.opacity(0.09), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Calendar to add the event to")
    }

    /// No calendar accepts new events yet: say why and offer the one step that fixes it.
    private var noCalendar: some View {
        VStack(spacing: 8) {
            Text(googleNeedsConsent ? "Loft can only read your Google Calendar so far" : "No calendar to add events to")
                .font(.system(size: 12, weight: .semibold))
            Text(googleNeedsConsent
                 ? "Sign in once more to let Loft create and delete events. Nothing else changes."
                 : "Allow Apple Calendar access, or connect Google in Settings.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
            HStack(spacing: 8) {
                Button("Cancel", action: onDone).buttonStyle(.loftGlass)
                if googleNeedsConsent {
                    Button(google.isConnecting ? "Waiting for Google…" : "Allow Google edits") { google.connect() }
                        .buttonStyle(.loftProminent()).disabled(google.isConnecting)
                }
                if !cal.authorized && !cal.denied {
                    Button("Use Apple Calendar") { cal.requestAccess() }.buttonStyle(googleNeedsConsent ? .loftGlass : .loftProminent())
                }
            }
            .controlSize(.small)
            if let err = google.lastError { Text(err).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
