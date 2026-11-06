import SwiftUI

/// Top row of the island. Collapsed: live activity around the hardware notch.
/// Open: tab strip and panel controls.
struct CompactRowView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var timer = TimerManager.shared
    @ObservedObject var keepAwake = KeepAwakeManager.shared
    @ObservedObject var cal = CalendarManager.shared
    @Environment(\.islandTint) private var tint

    var body: some View {
        if vm.state == .open {
            PanelHeaderView()
        } else {
            closedContent
        }
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
            let isCall = CalendarManager.isVideoCall(ev)
            HStack(spacing: 0) {
                Image(systemName: isCall ? "video.fill" : "calendar")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                    .frame(width: side).padding(.horizontal, inset)
                Spacer().frame(width: vm.notchWidth)
                HStack(spacing: 6) {
                    Text(ev.title ?? "Meeting").font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(maxWidth: 120, alignment: .leading)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let s = Int(ev.startDate.timeIntervalSince(ctx.date))
                        Text(s > 0 ? (s >= 60 ? "\(s / 60)m" : "\(s)s") : "now")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, inset + 4)
            }
            .frame(height: h)
        } else if timer.isRunning && prefs.timerEnabled {
            HStack(spacing: 0) {
                TimerRingView(progress: timer.progress, side: side)
                    .padding(.horizontal, inset)
                    .frame(width: side + inset * 2)
                Spacer().frame(width: vm.notchWidth)
                Text(timer.remaining.clockString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(timer.mode == .pomodoroBreak ? .green : .orange)
                    .padding(.horizontal, inset)
                    .frame(width: 66, alignment: .trailing)
            }
            .frame(height: h)
        } else if music.isActive && prefs.musicLiveActivity {
            HStack(spacing: 0) {
                AlbumArtView(image: music.artwork, cornerRadius: 4)
                    .frame(width: side, height: side)
                    .padding(.horizontal, inset)
                Spacer().frame(width: vm.notchWidth)
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
            .frame(height: h)
        } else {
            HStack(spacing: 0) {
                if keepAwake.isActive {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        .frame(width: side).padding(.horizontal, inset)
                }
                Spacer().frame(width: vm.notchWidth)
                if prefs.showClockInPill {
                    TimelineView(.everyMinute) { ctx in
                        Text(ctx.date.shortTime).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, inset + 2)
                }
            }
            .frame(height: h)
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
            HStack(spacing: 0) {
                Image(systemName: "capslock.fill").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(on ? .green : .secondary)
                    .frame(width: side).padding(.horizontal, 6)
                Spacer().frame(width: vm.notchWidth)
                Text(on ? "Caps Lock On" : "Caps Lock Off").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .green : .secondary)
                    .padding(.horizontal, 10)
            }.frame(height: h)
        case .battery(let level, let charging, let pluggedIn, let low):
            HStack(spacing: 0) {
                Text(low ? "Low Battery" : charging ? "Charging" : pluggedIn ? "Plugged In" : "On Battery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(low ? .red : charging ? .green : .white)
                    .padding(.horizontal, 10)
                Spacer().frame(width: vm.notchWidth)
                BatteryGlyph(level: level, charging: charging, low: low)
                    .padding(.horizontal, 10)
            }.frame(height: h)
        case .message(let m):
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
                Spacer().frame(width: vm.notchWidth)
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
            }.frame(height: h)
            .contentShape(Rectangle())
            .onTapGesture { if let a = m.action { vm.dismissTransient(); a() } }
        }
    }

    private func hud(symbol: String, value: Double, color: Color, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: side).padding(.horizontal, 6)
            Spacer().frame(width: vm.notchWidth)
            HStack(spacing: 8) {
                HUDBar(value: value, color: color).frame(width: 96, height: 6)
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85)).frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 10)
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
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.gray.opacity(0.6), .gray.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
