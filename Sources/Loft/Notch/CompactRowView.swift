import SwiftUI

/// Top row of the island. Collapsed: live activity around the hardware notch.
/// Open: tab strip and panel controls.
struct CompactRowView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var timer = TimerManager.shared
    @ObservedObject var keepAwake = KeepAwakeManager.shared
    @ObservedObject var privacy = PrivacyMonitor.shared
    @ObservedObject var downloads = DownloadMonitor.shared
    @ObservedObject var audio = AudioDeviceManager.shared
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var salah = PrayerTimesService.shared
    @Environment(\.islandTint) private var tint

    @ObservedObject var weather = WeatherService.shared

    /// What the idle pill cycles through, in order. One item shows on its own; two or more rotate.
    private var pillItems: [PillRotator.Item] {
        var items: [PillRotator.Item] = []
        if prefs.salahEnabled, prefs.salahInPill, salah.next() != nil { items.append(.salah) }
        if prefs.calendarEnabled, prefs.calendarInPill, PillRotator.nextEvent(cal) != nil { items.append(.event) }
        if prefs.weatherEnabled, prefs.weatherInPill, weather.snapshot != nil { items.append(.weather) }
        return items
    }

    var body: some View {
        closedContent
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { vm.compactWidth = $0 }
    }

    // MARK: Closed

    @ViewBuilder
    private var closedContent: some View {
        let h = vm.closedHeight
        let inset: CGFloat = 6
        let side = max(0, h - 2 * inset)   // square that fits beside the notch

        if let t = vm.transient {
            TransientView(transient: t, side: side)
        } else if let ev = cal.imminentEvent, prefs.calendarEnabled, prefs.meetingAlertsEnabled {
            let isCall = ev.isVideoCall
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                Image(systemName: isCall ? "video.fill" : "calendar")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                    .frame(width: side).padding(.horizontal, inset)
                }
                HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(ev.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(maxWidth: 120, alignment: .leading)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let s = Int(ev.startDate.timeIntervalSince(ctx.date))
                        Text(s > 0 ? (s >= 60 ? "\(s / 60)m" : "\(s)s") : "now")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, inset + 4)
                }
            }
            .frame(height: h)
        } else if timer.isRunning && prefs.timerEnabled {
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                TimerRingView(progress: timer.progress, side: side)
                    .padding(.horizontal, inset)
                    .frame(width: side + inset * 2)
                }
                HStack(spacing: 0) {
                Text(timer.remaining.clockString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(timer.mode == .pomodoroBreak ? .green : .orange)
                    .padding(.horizontal, inset)
                    .frame(width: 66, alignment: .trailing)
                }
            }
            .frame(height: h)
        } else if music.isActive && prefs.musicLiveActivity {
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                AlbumArtView(image: music.artwork, cornerRadius: 4)
                    .frame(width: side, height: side)
                    .padding(.horizontal, inset)
                }
                HStack(spacing: 0) {
                Group {
                    if prefs.musicVisualizer {
                        AudioBarsView(isPlaying: music.isPlaying, tint: tint)
                            .frame(width: 18, height: 12)
                    } else {
                        Image(systemName: music.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
                    }
                }
                .frame(width: side, height: side)
                .padding(.horizontal, inset)
                }
            }
            .frame(height: h)
        } else {
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                if privacy.inCall, prefs.callIsland {
                    // Live call: timer on the left, mic mute button on the right.
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 5) {
                            Circle().fill(.green).frame(width: 7, height: 7)
                            Text(ctx.date.timeIntervalSince(privacy.callStarted ?? ctx.date).clockString)
                                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.green)
                        }
                    }.padding(.horizontal, inset + 2)
                } else if downloads.active == nil, keepAwake.isActive || !pillItems.isEmpty {
                    let items = pillItems
                    // With info to show, the cup moves to the right side so both sides stay short and even.
                    if items.isEmpty {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                            .frame(width: side).padding(.horizontal, inset)
                    } else {
                        PillRotator(items: items, height: h).padding(.horizontal, inset + 2)
                    }
                } else if let d = downloads.active {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 11, weight: .semibold)).foregroundStyle(.cyan)
                        if let p = d.progress {
                            ProgressView(value: p).progressViewStyle(.linear).tint(.cyan).frame(width: 46)
                        } else {
                            Text(SystemStats.bytes(Double(d.bytes), perSecond: false)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.cyan)
                        }
                    }.padding(.horizontal, inset + 2).help(d.name)
                }
                }
                HStack(spacing: 0) {
                if privacy.inCall, prefs.callIsland {
                    Button { audio.toggleMicMute() } label: {
                        Image(systemName: audio.micMuted ? "mic.slash.fill" : "mic.fill").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(audio.micMuted ? .red : .white).frame(width: side, height: side)
                    }.buttonStyle(.plain).padding(.horizontal, inset).help(audio.micMuted ? "Unmute microphone" : "Mute microphone")
                } else if keepAwake.isActive, !pillItems.isEmpty, downloads.active == nil, !(prefs.privacyIndicator && (privacy.micInUse || privacy.cameraInUse)) {
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        if prefs.showClockInPill {
                            TimelineView(.everyMinute) { ctx in
                                Text(ctx.date.pillTime).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(.horizontal, inset + 2)
                } else if prefs.privacyIndicator, privacy.micInUse || privacy.cameraInUse {
                    HStack(spacing: 4) {
                        if privacy.cameraInUse { Circle().fill(.green).frame(width: 7, height: 7) }
                        if privacy.micInUse { Circle().fill(.orange).frame(width: 7, height: 7) }
                    }.padding(.horizontal, inset + 2).help((privacy.cameraInUse ? "Camera" : "") + (privacy.cameraInUse && privacy.micInUse ? " and " : "") + (privacy.micInUse ? "microphone" : "") + " in use")
                } else if prefs.showClockInPill {
                    TimelineView(.everyMinute) { ctx in
                        Text(ctx.date.shortTime).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, inset + 2)
                }
                }
            }
            .frame(height: h)
        }
    }
}

/// Cycles the idle pill through its info items every few seconds. The slot keeps one width while
/// rotating so the pill does not resize with every change.
struct PillRotator: View {
    enum Item: String { case salah, event, weather }
    let items: [Item]
    let height: CGFloat
    @ObservedObject var cal = CalendarManager.shared
    @ObservedObject var weather = WeatherService.shared
    static let interval: TimeInterval = 6
    static let slotWidth: CGFloat = 104

    /// The next timed event within a day that is not one of the Salah blocks (those have their own item).
    @MainActor static func nextEvent(_ cal: CalendarManager, at now: Date = Date()) -> MeetingEvent? {
        cal.events.first { !$0.isAllDay && !$0.canceled && !$0.declined && $0.endDate > now && $0.startDate.timeIntervalSince(now) < 86400 && !PrayerTimesService.isBlock($0) }
    }

    var body: some View {
        if items.count == 1 {
            view(for: items[0])
        } else {
            TimelineView(.periodic(from: .now, by: Self.interval)) { ctx in
                let index = Int(ctx.date.timeIntervalSinceReferenceDate / Self.interval) % items.count
                ZStack(alignment: .leading) {
                    view(for: items[index])
                        .id(items[index])
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                }
                .frame(width: Self.slotWidth, height: height, alignment: .leading)
                .clipped()
                .animation(.smooth(duration: 0.35), value: index)
            }
        }
    }

    @ViewBuilder private func view(for item: Item) -> some View {
        switch item {
        case .salah: SalahPill()
        case .event: EventPill()
        case .weather:
            if let s = weather.snapshot {
                HStack(spacing: 4) {
                    Image(systemName: WeatherService.symbol(for: s.code)).symbolRenderingMode(.multicolor).font(.system(size: 10, weight: .semibold))
                    Text("\(Int(s.temperature.rounded()))°").font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92)).fixedSize()
                    // One word fits the slot: "Partly cloudy" → "Cloudy", "Light rain" → "Rain".
                    Text((WeatherService.describe(s.code).split(separator: " ").last.map(String.init) ?? "").capitalized)
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.cyan).lineLimit(1).truncationMode(.tail)
                }
                .lineLimit(1)
            }
        }
    }
}

/// Next calendar event beside the notch: title and start time, a countdown in the last hour.
struct EventPill: View {
    @ObservedObject var cal = CalendarManager.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            if let ev = PillRotator.nextEvent(cal, at: ctx.date) {
                let minutes = Int((ev.startDate.timeIntervalSince(ctx.date) / 60).rounded(.up))
                let live = minutes <= 0
                HStack(spacing: 4) {
                    Image(systemName: ev.isVideoCall ? "video.fill" : "calendar").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                    Text(ev.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).lineLimit(1).truncationMode(.tail)
                    Text(live ? "now" : minutes <= 60 ? "\(minutes)m" : (Calendar.current.isDateInToday(ev.startDate) ? ev.startDate.pillTime : "tmrw"))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.green).fixedSize()
                }
                .help("\(ev.title) at \(ev.startDate.shortTime)")
            }
        }
    }
}

/// Next prayer beside the notch: its time, switching to a countdown in the last hour.
struct SalahPill: View {
    @ObservedObject var salah = PrayerTimesService.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            if let p = salah.next(after: ctx.date) {
                let minutes = max(0, Int((p.date.timeIntervalSince(ctx.date) / 60).rounded(.up)))
                let soon = minutes <= 15
                HStack(spacing: 4) {
                    Image(systemName: p.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(soon ? .orange : .teal)
                    Text(p.name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                    Text(minutes <= 60 ? "\(minutes)m" : p.date.pillTime)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(soon ? .orange : .teal)
                }
                .lineLimit(1).fixedSize()
                .help("\(p.name) at \(p.date.shortTime)")
            }
        }
    }
}

// MARK: - Transient (HUD / battery / message)

struct TransientView: View {
    @ObservedObject var vm = NotchViewModel.shared
    let transient: Transient
    let side: CGFloat

    var body: some View {
        let h = vm.closedHeight
        switch transient.kind {
        case .volume(let v, let muted):
            hud(symbol: muted || v == 0 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill",
                value: muted ? 0 : v, color: .white, height: h)
        case .brightness(let v):
            hud(symbol: v < 0.5 ? "sun.min.fill" : "sun.max.fill", value: v, color: .yellow, height: h)
        case .keyboardBacklight(let v):
            hud(symbol: "keyboard", value: v, color: .white, height: h)
        case .capsLock(let on):
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                Image(systemName: "capslock.fill").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(on ? .green : .secondary)
                    .frame(width: side).padding(.horizontal, 6)
                }
                HStack(spacing: 0) {
                Text(on ? "Caps Lock On" : "Caps Lock Off").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .green : .secondary)
                    .padding(.horizontal, 10)
                }
            }.frame(height: h)
        case .battery(let level, let charging, let pluggedIn, let low):
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                Text(low ? "Low Battery" : charging ? "Charging" : pluggedIn ? "Plugged In" : "On Battery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(low ? .red : charging ? .green : .white)
                    .padding(.horizontal, 10)
                }
                HStack(spacing: 0) {
                BatteryGlyph(level: level, charging: charging, low: low)
                    .padding(.horizontal, 10)
                }
            }.frame(height: h)
        case .message(let m):
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                if let thumb = m.thumbnail {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 6)
                } else {
                    Image(systemName: m.symbol ?? "bell.badge.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(m.tint)
                        .frame(width: side).padding(.horizontal, 6)
                }
                }
                HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let s = m.subtitle, !s.isEmpty {
                        Text(s).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    } else if let p = m.progress {
                        ProgressView(value: min(1, max(0, p))).progressViewStyle(.linear).tint(m.tint).frame(width: 90)
                    }
                }
                .frame(maxWidth: 170, alignment: .leading)
                .padding(.horizontal, 10)
                }
            }.frame(height: h)
            .contentShape(Rectangle())
            .onTapGesture { if let a = m.action { vm.dismissTransient(); a() } }
        case .ask(let q):
            NotchSides(gap: vm.notchWidth) {
                HStack(spacing: 0) {
                Image(systemName: q.symbol ?? "questionmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                    .frame(width: side).padding(.horizontal, 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(q.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if let s = q.subtitle, !s.isEmpty { Text(s).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
                }
                .frame(maxWidth: 150, alignment: .leading)
                }
                HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(Array(q.options.prefix(3).enumerated()), id: \.offset) { i, opt in
                        Button { vm.answer(q, with: opt) } label: {
                            Text(opt).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                .padding(.horizontal, 8).frame(height: 20)
                                .background(i == 0 ? Color.green.opacity(0.85) : (i == q.options.count - 1 ? Color.red.opacity(0.7) : Color.white.opacity(0.15)), in: Capsule())
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                }
            }.frame(height: h)
        }
    }

    private func hud(symbol: String, value: Double, color: Color, height: CGFloat) -> some View {
        NotchSides(gap: vm.notchWidth) {
            HStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: side).padding(.horizontal, 6)
            }
            HStack(spacing: 0) {
            HStack(spacing: 8) {
                HUDBar(value: value, color: color).frame(width: 96, height: 6)
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85)).frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            }
        }
        .frame(height: height)
    }
}

struct HUDBar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: value)
    }
}

struct BatteryGlyph: View {
    let level: Int
    let charging: Bool
    let low: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text("\(level)%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(low ? .red : .white.opacity(0.9))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.6), lineWidth: 1).frame(width: 24, height: 11)
                RoundedRectangle(cornerRadius: 1.5).fill(low ? Color.red : charging ? Color.green : Color.white)
                    .frame(width: max(2, 20 * CGFloat(level) / 100), height: 7).padding(.leading, 2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 24)
                }
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.6)).frame(width: 2, height: 5).offset(x: 3)
            }
        }
    }
}

struct TimerRingView: View {
    let progress: Double
    let side: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 3)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: side - 4, height: side - 4)
        .animation(.linear(duration: 1), value: progress)
    }
}

/// Fake-but-pretty spectrum bars; a real FFT needs the audio process-tap permission.
struct AudioBarsView: View {
    let isPlaying: Bool
    let tint: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (2.1 + Double(i) * 0.6) + Double(i)
                    let level = isPlaying ? 0.3 + 0.7 * abs(sin(phase)) * (0.6 + 0.4 * abs(cos(t * 0.9 + Double(i)))) : 0.18
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tint)
                        .frame(width: 3, height: max(2, 12 * level))
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}

struct AlbumArtView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 6
    var body: some View {
        ZStack {
            if let image {
                // Fill the square and clip: wide video thumbnails must never spill out of the frame.
                Color.clear.overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill))
            } else {
                LinearGradient(colors: [.gray.opacity(0.6), .gray.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
