import SwiftUI

/// Next prayer and countdown on the left, the day's timetable on the right, and a switch that
/// keeps a 30-minute block in the calendar for every upcoming prayer.
struct SalahTabView: View {
    @ObservedObject var salah = PrayerTimesService.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var google = GoogleCalendarService.shared
    @Environment(\.islandTint) private var tint
    @State private var cityDraft = ""
    @State private var editingCity = false

    var body: some View {
        Group {
            if (salah.city.isEmpty && !Demo.active) || editingCity {
                citySetup
            } else if salah.today.isEmpty {
                if let err = salah.error {
                    VStack(spacing: 8) {
                        EmptyHint(symbol: "moon.stars", title: "Could not load prayer times", subtitle: err)
                        HStack {
                            Button("Retry") { salah.refreshIfNeeded(force: true) }.buttonStyle(.loftProminent())
                            Button("Change city") { startEditing() }.buttonStyle(.loftGlass)
                        }.controlSize(.small)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 20)) { ctx in timetable(now: ctx.date) }
            }
        }
        .onAppear { salah.refreshIfNeeded() }
    }

    // MARK: Timetable

    private func timetable(now: Date) -> some View {
        let next = salah.next(after: now)
        let current = salah.current(at: now)
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT PRAYER").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                Text(next?.name ?? "—").font(.system(size: 28, weight: .bold, design: .rounded))
                if let next {
                    Text(next.date.shortTime + (Calendar.current.isDateInToday(next.date) ? "" : " tomorrow"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(Self.countdown(to: next.date, from: now)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .padding(.horizontal, 8).frame(height: 20).background(tint.opacity(0.22), in: Capsule()).padding(.top, 4)
                }
                Spacer(minLength: 0)
                optionsMenu
            }
            .frame(width: 150, alignment: .leading)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(salah.today) { p in
                        card(p, isNext: p.id == next?.id, isCurrent: p.id == current?.id && p.id != next?.id, past: p.date <= now)
                    }
                }
                .frame(maxHeight: .infinity)
                blocksRow
            }
        }
    }

    private func card(_ p: PrayerTime, isNext: Bool, isCurrent: Bool, past: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: p.symbol).font(.system(size: 16, weight: .medium))
                .foregroundStyle(isNext ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(p.isPrayer ? 0.85 : 0.5)))
                .frame(height: 20)
            Text(p.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(p.date.shortTime).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(isNext ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary)).lineLimit(1).minimumScaleFactor(0.8)
            Image(systemName: "calendar.badge.checkmark").font(.system(size: 8)).foregroundStyle(.secondary)
                .opacity(salah.blocked.contains(p.id) ? 1 : 0).help("Blocked in your calendar")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 12, tint: isNext ? tint : nil, strength: isNext ? 1.3 : (p.isPrayer ? 0.8 : 0.45))
        .overlay(alignment: .top) {
            if isCurrent { Capsule().fill(.green).frame(width: 14, height: 2.5).padding(.top, 5).help("Current prayer time") }
        }
        .opacity(past && !isCurrent ? 0.55 : 1)
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let m = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if m < 1 { return "now" }
        return m >= 60 ? "in \(m / 60) h \(m % 60) min" : "in \(m) min"
    }

    // MARK: Calendar blocks

    private var blocksRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { prefs.salahCalendarBlocks }, set: { on in
                prefs.salahCalendarBlocks = on
                if on { Task { await salah.syncBlocks() } }
            })) {
                Text("Calendar blocks").font(.system(size: 10.5, weight: .medium))
            }
            .toggleStyle(.switch).controlSize(.mini).tint(tint)
            if prefs.salahCalendarBlocks {
                if let err = blockProblem {
                    Text(err).font(.system(size: 10)).foregroundStyle(.red).lineLimit(1)
                    if google.isConnected && !google.canWrite {
                        Button("Allow Google edits") { google.connect() }.buttonStyle(.loftGlass).controlSize(.mini)
                    } else if !cal.authorized && !cal.denied {
                        Button("Use Apple Calendar") { cal.requestAccess() }.buttonStyle(.loftGlass).controlSize(.mini)
                    }
                } else {
                    Text("Next \(PrayerTimesService.blockDays) days are added to").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                    calendarMenu
                }
            } else {
                Text("30 min from the next quarter hour, two weeks ahead").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }

    private var blockProblem: String? {
        if cal.targets.isEmpty { return "No calendar accepts new events yet." }
        return salah.blockError
    }

    private var calendarMenu: some View {
        let target = cal.targets.first { $0.id == salah.blockTargetID }
        return Menu {
            ForEach(cal.targets) { t in
                Button(t.account == t.name ? t.name : "\(t.name) · \(t.account)") { prefs.salahCalendarTarget = t.id }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(target?.color ?? .gray).frame(width: 7, height: 7)
                Text(target?.name ?? "Calendar").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 20).frame(maxWidth: 160)
            .background(.white.opacity(0.09), in: Capsule()).contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: City and method

    private var optionsMenu: some View {
        Menu {
            Section("Calculation method") {
                ForEach(PrayerTimesService.methods, id: \.key) { m in
                    Toggle(m.name, isOn: Binding(get: { prefs.salahMethod == m.key }, set: { _ in prefs.salahMethod = m.key; salah.refreshIfNeeded(force: true) }))
                }
            }
            Section("Asr") {
                ForEach(["Shafi", "Hanafi"], id: \.self) { m in
                    Toggle(m == "Shafi" ? "Standard (Shafi, Maliki, Hanbali)" : "Hanafi (later Asr)",
                           isOn: Binding(get: { prefs.salahMadhab == m }, set: { _ in prefs.salahMadhab = m; salah.refreshIfNeeded(force: true) }))
                }
            }
            Divider()
            Toggle("Full-screen alert at prayer time", isOn: Binding(get: { prefs.salahFullScreenAlert }, set: { prefs.salahFullScreenAlert = $0; salah.refreshIfNeeded() }))
            Button("Preview alert") { salah.testAlert() }
            Button("Change city…") { startEditing() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 9))
                Text(salah.place.isEmpty ? salah.city : salah.place).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary).frame(height: 20).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("City, calculation method and Asr school")
    }

    private func startEditing() {
        cityDraft = salah.city
        editingCity = true
        NotchViewModel.shared.userInteracted()
    }

    private func saveCity() {
        let c = cityDraft.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        prefs.salahCity = c
        editingCity = false
        salah.refreshIfNeeded(force: true)
    }

    private var citySetup: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars").font(.system(size: 22)).foregroundStyle(.secondary)
            Text("Prayer times for which city?").font(.system(size: 12, weight: .semibold))
            HStack {
                TextField("e.g. Riyadh", text: $cityDraft).textFieldStyle(.roundedBorder).frame(width: 180).onSubmit(saveCity)
                Button("Save", action: saveCity).buttonStyle(.loftProminent())
                if editingCity { Button("Cancel") { editingCity = false }.buttonStyle(.loftGlass) }
            }.controlSize(.small)
            Text("No location permission needed. Times by UmmahAPI, \(prefs.salahMethod) method.").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { NotchViewModel.shared.userInteracted() }
    }
}
