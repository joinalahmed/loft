import SwiftUI

struct CalendarTabView: View {
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var google = GoogleCalendarService.shared
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        if !cal.hasSource {
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
                .buttonStyle(.borderedProminent).controlSize(.small)
                Text("Apple Calendar covers every account in System Settings. Connect Google directly to sync without adding it to macOS.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date(), format: .dateTime.weekday(.wide)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    Text(Date(), format: .dateTime.day()).font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(Date(), format: .dateTime.month(.wide)).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if let url = cal.nextEvent?.joinURL {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Join next", systemImage: "video.fill") }
                            .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                    }
                    Button("Open Calendar") { NSWorkspace.shared.open(URL(string: "ical://")!) }.buttonStyle(.bordered).controlSize(.small)
                }
                .frame(width: 130)
                VStack(spacing: 6) {
                    if cal.todayEvents.isEmpty {
                        EmptyHint(symbol: "sun.max", title: "No events today", subtitle: "Synced from \(cal.calendarSources.joined(separator: ", ")).")
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(cal.todayEvents) { ev in EventRow(event: ev) }
                            }
                        }.scrollIndicators(.never)
                    }
                    HStack {
                        Text("Alerts \(prefs.meetingLeadMinutes) min before · \(cal.calendarSources.count) account\(cal.calendarSources.count == 1 ? "" : "s")")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Preview alert") { cal.testAlert() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
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
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent).controlSize(.mini).tint(.green)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.white.opacity(past ? 0.03 : 0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(live ? Color.green.opacity(0.35) : .clear, lineWidth: 0.5))
        .opacity(past ? 0.55 : 1)
    }
}
