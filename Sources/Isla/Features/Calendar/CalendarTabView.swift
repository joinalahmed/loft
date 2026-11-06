import SwiftUI
import EventKit

struct CalendarTabView: View {
    @ObservedObject var cal = CalendarManager.shared

    var body: some View {
        if !cal.authorized {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 22)).foregroundStyle(.secondary)
                Text(cal.denied ? "Calendar access was declined" : "Show today's events in the notch").font(.system(size: 12, weight: .semibold))
                if cal.denied {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
                } else {
                    Button("Allow Calendar Access") { cal.requestAccess() }
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date(), format: .dateTime.weekday(.wide)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    Text(Date(), format: .dateTime.day()).font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(Date(), format: .dateTime.month(.wide)).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Calendar") { NSWorkspace.shared.open(URL(string: "ical://")!) }.buttonStyle(.bordered).controlSize(.small)
                }
                .frame(width: 120)
                if cal.todayEvents.isEmpty {
                    EmptyHint(symbol: "sun.max", title: "No events today", subtitle: "Enjoy the open calendar.")
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(cal.todayEvents, id: \.eventIdentifier) { ev in EventRow(event: ev) }
                        }
                    }.scrollIndicators(.never)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: EKEvent
    var compact = false
    var body: some View {
        let past = event.endDate < Date()
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(event.isAllDay ? "All day" : "\(event.startDate.shortTime) – \(event.endDate.shortTime)" + (event.location.map { " · \($0)" } ?? ""))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !past, let url = CalendarManager.joinURL(for: event), !compact {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent).controlSize(.mini).tint(.green)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.white.opacity(past ? 0.03 : 0.07), in: RoundedRectangle(cornerRadius: 8))
        .opacity(past ? 0.6 : 1)
    }
}
