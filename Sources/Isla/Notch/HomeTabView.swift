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
    @Environment(\.islandTint) private var tint

    var body: some View {
        HStack(spacing: 10) {
            musicCard.frame(width: 250)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if prefs.calendarEnabled { calendarCard } else { batteryCard }
                    if prefs.timerEnabled { timerCard } else { shelfCard }
                }
                HStack(spacing: 8) {
                    if prefs.weatherEnabled { weatherCard } else { batteryCard }
                    if prefs.clipboardEnabled { clipboardCard } else if prefs.shelfEnabled { shelfCard } else { batteryCard }
                }
            }
        }
        .onAppear { if prefs.weatherEnabled { weather.refreshIfNeeded() } }
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
            if !cal.authorized {
                Text("Tap to connect").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let ev = cal.nextEvent {
                Text(ev.title ?? "Event").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(ev.startDate > Date() ? "in \(relative(ev.startDate))" : "now · ends \(ev.endDate.shortTime)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
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
                Button("Start \(prefs.pomodoroWorkMinutes) min") { timer.startPomodoro() }.buttonStyle(.bordered).controlSize(.mini)
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
            .padding(8)
            .background(.white.opacity(hover ? 0.11 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
