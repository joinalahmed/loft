import SwiftUI

struct HomeTabView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var timer = TimerManager.shared
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var battery = BatteryMonitor.shared
    @ObservedObject var clip = ClipboardManager.shared
    @ObservedObject var shelf = ShelfManager.shared
    @ObservedObject var keepAwake = KeepAwakeManager.shared
    @Environment(\.islandTint) private var tint

    /// The cards the user chose (Settings → Tools → Home cards), minus any whose tool is switched off.
    private var cards: [HomeCard] { prefs.homeCardList.filter { $0.isAvailable(prefs) } }

    var body: some View {
        if vm.homeEditing {
            HomeCardPicker { withAnimation(.smooth(duration: 0.2)) { vm.homeEditing = false } }
        } else {
            dashboard
                .overlay(alignment: .bottomTrailing) {
                    Button { withAnimation(.smooth(duration: 0.2)) { vm.homeEditing = true } } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                            .frame(width: 22, height: 22).glass(Circle(), strength: 1.3, interactive: true)
                    }
                    .buttonStyle(.plain).padding(5).help("Choose and arrange the cards on Home")
                }
        }
    }

    private var dashboard: some View {
        GeometryReader { geo in
            let showMusic = prefs.musicLiveActivity
            let gridWidth = showMusic ? geo.size.width - 250 - 10 : geo.size.width
            // Columns follow the width; rows follow the height; the rest is reachable from the tabs.
            let columns = max(2, min(4, Int(gridWidth / 150)))
            let rows = max(1, min(3, Int((geo.size.height + 8) / 95)))
            let visible = Array(cards.prefix(columns * rows))
            HStack(spacing: 10) {
                if showMusic { musicCard.frame(width: 250) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                    ForEach(visible, id: \.self) { kind in
                        card(kind).frame(height: (geo.size.height - CGFloat(rows - 1) * 8) / CGFloat(rows))
                            .contextMenu {
                                if kind == .keepAwake {
                                    ForEach(KeepAwakeManager.durations, id: \.minutes) { d in Button(d.title) { keepAwake.acquire(minutes: d.minutes) } }
                                    if keepAwake.isActive { Button("Turn Off") { keepAwake.release() } }
                                    Divider()
                                }
                                Button("Hide “\(kind.title)” from Home") { prefs.setHomeCard(kind, shown: false) }
                                Button("Customize Home…") { vm.homeEditing = true }
                            }
                    }
                }
                .animation(.smooth(duration: 0.25), value: visible)
            }
        }
        .onAppear { if prefs.weatherEnabled { weather.refreshIfNeeded() } }
    }

    @ViewBuilder private func card(_ kind: HomeCard) -> some View {
        switch kind {
        case .calendar: calendarCard
        case .reminders: remindersCard
        case .keepAwake: keepAwakeCard
        case .screenshot: screenshotCard
        case .timer: timerCard
        case .weather: weatherCard
        case .clipboard: clipboardCard
        case .shelf: shelfCard
        case .battery: batteryCard
        case .system: systemCard
        case .worldClock: worldClockCard
        case .salah: salahCard
        }
    }

    private var salahCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let salah = PrayerTimesService.shared
            let next = salah.next(after: ctx.date)
            MiniCard(symbol: next?.symbol ?? "moon.stars.fill", title: "Salah", color: .teal, action: { vm.tab = .salah }) {
                if let next {
                    Text("\(next.name) · \(next.date.shortTime)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(SalahTabView.countdown(to: next.date, from: ctx.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text(salah.city.isEmpty ? "Set a city" : "Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var remindersCard: some View {
        MiniCard(symbol: "checklist", title: "Reminders", color: .orange, action: { vm.tab = .reminders }) {
            let r = RemindersManager.shared
            if !r.authorized {
                Text("Tap to connect").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let first = (r.overdue + r.today).first {
                Text(first.title ?? "Reminder").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(r.overdue.count + r.today.count) due today" + (r.overdue.isEmpty ? "" : " · \(r.overdue.count) overdue")).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("All clear").font(.system(size: 12, weight: .semibold))
                Text("\(r.reminders.count) open").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var systemCard: some View {
        MiniCard(symbol: "gauge.with.dots.needle.33percent", title: "System", color: .mint, action: { vm.tab = .system }) {
            let st = SystemStats.shared
            Text("CPU \(Int(st.cpu * 100))% · Mem \(Int(st.memoryTotal > 0 ? st.memoryUsed / st.memoryTotal * 100 : 0))%").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
            Text(SystemStats.bytes(st.netDown, perSecond: true) + " ↓").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var worldClockCard: some View {
        MiniCard(symbol: "globe", title: "World clock", color: .teal, action: { vm.tab = .worldClock }) {
            let zones = WorldClockStore.shared.zones.prefix(2)
            if zones.isEmpty {
                Text("Add cities in the tab").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                TimelineView(.everyMinute) { ctx in
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(zones)) { z in
                            HStack {
                                Text(z.city).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text(z.time(at: ctx.date)).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Cards

    private var musicCard: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                AlbumArtView(image: music.artwork, cornerRadius: 10)
                    .frame(width: 72, height: 72).shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    .onTapGesture { vm.tab = .music }
                VStack(alignment: .leading, spacing: 3) {
                    if music.title.isEmpty {
                        Text("Not playing").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Text("Spotify, Music, browsers…").font(.system(size: 10)).foregroundStyle(.tertiary)
                    } else {
                        MarqueeText(music.title, font: .system(size: 13, weight: .bold))
                        Text(music.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    HStack(spacing: 14) {
                        SmallIconButton(symbol: "backward.fill", size: 13) { music.previous() }
                        Button { music.togglePlayPause() } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.black).frame(width: 30, height: 30).background(tint, in: Circle())
                        }.buttonStyle(.plain)
                        SmallIconButton(symbol: "forward.fill", size: 13) { music.next() }
                    }.frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var calendarCard: some View {
        MiniCard(symbol: "calendar", title: "Up next", color: .red, action: { vm.tab = .calendar }) {
            if !cal.hasSource {
                Text("Tap to connect").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let ev = cal.nextEvent {
                Text(ev.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(ev.startDate > Date() ? "in \(relative(ev.startDate))" : "now · ends \(ev.endDate.shortTime)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if let url = ev.joinURL {
                    Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.loftProminent(.green)).controlSize(.mini)
                }
            } else {
                Text("No more events").font(.system(size: 12, weight: .semibold))
                Text("today").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var timerCard: some View {
        MiniCard(symbol: "timer", title: timer.isRunning ? timer.modeTitle : "Focus", color: .orange, action: { vm.tab = .timer }) {
            if timer.isRunning {
                Text(timer.remaining.clockString).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
            } else {
                Button("Start \(prefs.pomodoroWorkMinutes) min") { timer.startPomodoro() }.buttonStyle(.loftGlass).controlSize(.mini)
            }
        }
    }

    private var weatherCard: some View {
        MiniCard(symbol: weather.snapshot.map { WeatherService.symbol(for: $0.code) } ?? "cloud.sun", title: weather.snapshot?.place.components(separatedBy: ",").first ?? "Weather", color: .cyan, action: { vm.tab = .weather }) {
            if let s = weather.snapshot {
                Text("\(Int(s.temperature.rounded()))°  \(WeatherService.describe(s.code))").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let d = s.daily.first { Text("H \(Int(d.hi.rounded()))° · L \(Int(d.lo.rounded()))°").font(.system(size: 10)).foregroundStyle(.secondary) }
            } else {
                Text(prefs.weatherCity.isEmpty ? "Set a city" : "Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var clipboardCard: some View {
        MiniCard(symbol: "doc.on.clipboard", title: "Clipboard", color: .purple, action: { vm.tab = .clipboard }) {
            if let last = clip.items.first {
                Text(last.preview).font(.system(size: 11)).lineLimit(2)
            } else { Text("Empty").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }

    private var shelfCard: some View {
        MiniCard(symbol: "tray", title: "Shelf", color: .mint, action: { vm.tab = .shelf }) {
            Text("\(shelf.items.count) items").font(.system(size: 12, weight: .semibold))
        }
    }

    private var keepAwakeCard: some View {
        MiniCard(symbol: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer", title: "Keep awake", color: .yellow, action: { keepAwake.toggle() }) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(keepAwake.statusText).font(.system(size: 12, weight: .semibold)).foregroundStyle(keepAwake.isActive ? .yellow : .secondary)
            }
            Text(keepAwake.isActive ? "tap to turn off" : "tap to start · ⌃⌥A").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    private var screenshotCard: some View {
        MiniCard(symbol: "camera.viewfinder", title: "Screenshot", color: .cyan, action: { ScreenshotManager.shared.capture(.region) }) {
            HStack(spacing: 4) {
                Button("Region") { ScreenshotManager.shared.capture(.region) }
                Button("Window") { ScreenshotManager.shared.capture(.window) }
            }.buttonStyle(.loftGlass).controlSize(.mini)
            Text("to shelf · ⌃⌥⇧4").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    private var batteryCard: some View {
        MiniCard(symbol: "battery.100percent", title: "Battery", color: .green, action: { vm.tab = .system }) {
            Text("\(battery.level)%").font(.system(size: 16, weight: .bold, design: .rounded))
        }
    }

    private func relative(_ d: Date) -> String {
        let m = Int(d.timeIntervalSinceNow / 60)
        return m < 60 ? "\(m) min" : "\(m / 60)h \(m % 60)m"
    }
}

/// Home's edit mode: every available card as a tile. Shown cards come first, numbered in the
/// order they appear; − removes one, + adds one, the arrows move it earlier or later.
struct HomeCardPicker: View {
    let onDone: () -> Void
    @ObservedObject var prefs = Preferences.shared
    @Environment(\.islandTint) private var tint

    var body: some View {
        let shown = prefs.homeCardList
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Customize Home").font(.system(size: 13, weight: .bold))
                Text("Numbered cards show on Home in that order, as many as fit.").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Reset") { withAnimation(.smooth(duration: 0.2)) { prefs.homeCards = [] } }.buttonStyle(.loftGlass).controlSize(.mini)
                Button("Done", action: onDone).buttonStyle(.loftProminent()).controlSize(.mini)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(prefs.allHomeCards) { card in
                    tile(card, index: shown.firstIndex(of: card), count: shown.count)
                }
            }
            .animation(.smooth(duration: 0.2), value: prefs.homeCards)
            Spacer(minLength: 0)
        }
        .onExitCommand(perform: onDone)
    }

    private func tile(_ card: HomeCard, index: Int?, count: Int) -> some View {
        let on = index != nil
        let usable = card.isAvailable(prefs)
        return HStack(spacing: 5) {
            ZStack {
                Circle().fill(on ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.1))).frame(width: 18, height: 18)
                if let index { Text("\(index + 1)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.85)) }
                else { Image(systemName: card.symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(card.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if !usable { Text("tool is off").font(.system(size: 8.5)).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
            if let index {
                HStack(spacing: -5) {
                    SmallIconButton(symbol: "chevron.left", size: 8, help: "Show earlier") { move(card, by: -1) }.opacity(index > 0 ? 1 : 0.25).disabled(index == 0)
                    SmallIconButton(symbol: "chevron.right", size: 8, help: "Show later") { move(card, by: 1) }.opacity(index < count - 1 ? 1 : 0.25).disabled(index >= count - 1)
                    SmallIconButton(symbol: "minus", size: 8, help: "Remove from Home", tint: .red) { prefs.setHomeCard(card, shown: false) }
                }
            } else {
                SmallIconButton(symbol: "plus", size: 9, help: "Add to Home", tint: .green) { prefs.setHomeCard(card, shown: true) }
            }
        }
        .padding(.leading, 7).padding(.trailing, 3).frame(height: 38)
        .glassCard(cornerRadius: 10, tint: on ? tint : nil, strength: on ? 1 : 0.5)
        .opacity(on ? 1 : 0.75)
    }

    private func move(_ card: HomeCard, by delta: Int) {
        var list = prefs.homeCardList
        guard let i = list.firstIndex(of: card), list.indices.contains(i + delta) else { return }
        list.swapAt(i, i + delta)
        prefs.setHomeCards(list)
    }
}

/// A card that can be placed on Home. The raw value is what is stored in preferences.
enum HomeCard: String, CaseIterable, Identifiable {
    case calendar, salah, reminders, keepAwake, screenshot, timer, weather, worldClock, clipboard, shelf, system, battery
    var id: String { rawValue }
    static let defaults: [HomeCard] = allCases

    var title: String {
        switch self {
        case .calendar: "Up next"
        case .salah: "Salah"
        case .reminders: "Reminders"
        case .keepAwake: "Keep awake"
        case .screenshot: "Screenshot"
        case .timer: "Focus timer"
        case .weather: "Weather"
        case .worldClock: "World clock"
        case .clipboard: "Clipboard"
        case .shelf: "Shelf"
        case .system: "System"
        case .battery: "Battery"
        }
    }
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .salah: "moon.stars.fill"
        case .reminders: "checklist"
        case .keepAwake: "cup.and.saucer"
        case .screenshot: "camera.viewfinder"
        case .timer: "timer"
        case .weather: "cloud.sun"
        case .worldClock: "globe"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray"
        case .system: "gauge.with.dots.needle.33percent"
        case .battery: "battery.100percent"
        }
    }
    /// A card only appears while the tool behind it is switched on.
    func isAvailable(_ prefs: Preferences) -> Bool {
        switch self {
        case .calendar: prefs.calendarEnabled
        case .salah: prefs.salahEnabled
        case .reminders: prefs.remindersEnabled
        case .timer: prefs.timerEnabled
        case .weather: prefs.weatherEnabled
        case .worldClock: prefs.worldClockEnabled
        case .clipboard: prefs.clipboardEnabled
        case .shelf: prefs.shelfEnabled
        case .system: prefs.systemEnabled
        case .keepAwake, .screenshot, .battery: true
        }
    }
}

extension Preferences {
    /// Cards shown on Home, in order.
    var homeCardList: [HomeCard] { homeCards.isEmpty ? HomeCard.defaults : homeCards.compactMap(HomeCard.init(rawValue:)) }
    /// Every card: the shown ones in their order, then the hidden ones.
    var allHomeCards: [HomeCard] { let shown = homeCardList; return shown + HomeCard.allCases.filter { !shown.contains($0) } }

    func setHomeCards(_ cards: [HomeCard]) { homeCards = cards.isEmpty ? ["-"] : cards.map(\.rawValue) }   // "-" keeps an empty choice from reading as "default"
    func setHomeCard(_ card: HomeCard, shown: Bool) {
        var list = homeCardList
        if shown { if !list.contains(card) { list.append(card) } } else { list.removeAll { $0 == card } }
        setHomeCards(list)
    }
}

struct MiniCard<Content: View>: View {
    let symbol: String
    let title: String
    let color: Color
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(color).lineLimit(1)
                }
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(9)
            .glass(RoundedRectangle(cornerRadius: 12, style: .continuous), tint: hover ? color : nil, strength: hover ? 1.2 : 1, interactive: true)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(hover ? 0.35 : 0), lineWidth: 0.75))
            .scaleEffect(hover ? 1.012 : 1)
            .animation(.smooth(duration: 0.18), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
