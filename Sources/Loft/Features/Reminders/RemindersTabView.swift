import SwiftUI
import EventKit

struct RemindersTabView: View {
    @ObservedObject var rem = RemindersManager.shared
    @State private var draft = ""
    @State private var dueToday = true

    var body: some View {
        if !rem.authorized {
            VStack(spacing: 8) {
                Image(systemName: "checklist").font(.system(size: 22)).foregroundStyle(.secondary)
                Text(rem.denied ? "Reminders access was declined" : "Check things off from the notch").font(.system(size: 12, weight: .semibold))
                if rem.denied {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!) }
                } else {
                    Button("Allow Reminders Access") { rem.requestAccess() }
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                    TextField("New reminder…", text: $draft).textFieldStyle(.plain).font(.system(size: 12))
                        .onSubmit { rem.add(draft, dueToday: dueToday); draft = "" }
                    Toggle("Today", isOn: $dueToday).toggleStyle(.button).controlSize(.mini).font(.system(size: 10))
                }
                .padding(.horizontal, 10).frame(height: 26).background(.white.opacity(0.08), in: Capsule())
                if rem.reminders.isEmpty {
                    EmptyHint(symbol: "checkmark.circle", title: "All clear", subtitle: "No open reminders.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            section("Overdue", rem.overdue, color: .red)
                            section("Today", rem.today, color: .orange)
                            section("Later", rem.later, color: .secondary)
                        }
                    }.scrollIndicators(.never)
                }
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ items: [EKReminder], color: Color) -> some View {
        if !items.isEmpty {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(color).padding(.top, 4).padding(.leading, 6)
            ForEach(items, id: \.calendarItemIdentifier) { r in ReminderRow(reminder: r) }
        }
    }
}

private struct ReminderRow: View {
    @ObservedObject var rem = RemindersManager.shared
    let reminder: EKReminder
    @State private var hover = false
    @State private var checking = false
    var body: some View {
        HStack(spacing: 8) {
            Button {
                checking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { rem.complete(reminder) }
            } label: {
                Image(systemName: checking ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                    .foregroundStyle(checking ? Color.green : Color(cgColor: reminder.calendar.cgColor))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title ?? "Untitled").font(.system(size: 12, weight: .medium)).strikethrough(checking).lineLimit(1)
                if let d = reminder.dueDateComponents?.date {
                    Text(d, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if reminder.priority > 0 && reminder.priority <= 4 { Image(systemName: "exclamationmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.red) }
            Text(reminder.calendar.title).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(hover ? .white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hover = $0 }
    }
}
