import SwiftUI

/// Focus / Timer / Stopwatch. A glowing ring on the left, one glass card of controls on the
/// right; while something runs, the card turns into a status panel with Pause, Stop, +1 min.
struct TimerTabView: View {
    @ObservedObject var timer = TimerManager.shared
    @ObservedObject var prefs = Preferences.shared
    @State private var picker = 0   // 0 focus, 1 countdown, 2 stopwatch
    @Environment(\.islandTint) private var islandTint

    private var accent: Color {
        switch timer.mode {
        case .pomodoroBreak: .green
        case .stopwatch: .cyan
        default: .orange
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ring.frame(width: 176)
            VStack(alignment: .leading, spacing: 8) {
                if timer.isRunning { running } else { setup }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            switch timer.mode { case .countdown: picker = 1; case .stopwatch: picker = 2; case .idle: break; default: picker = 0 }
        }
    }

    // MARK: Ring

    private var ring: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 11)
                Circle().stroke(accent.opacity(0.12), lineWidth: 11).blur(radius: 6)
                let value = timer.mode == .stopwatch ? (timer.remaining.truncatingRemainder(dividingBy: 60)) / 60 : timer.progress
                Circle().trim(from: 0, to: timer.isRunning ? CGFloat(value) : 0)
                    .stroke(AngularGradient(colors: [accent.opacity(0.55), accent], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, value))),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(0.6), radius: 8)
                    .animation(.linear(duration: 0.25), value: value)
                VStack(spacing: 3) {
                    Text(timer.isRunning ? timer.remaining.clockString : previewString)
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().tracking(-0.5)
                        .contentTransition(.numericText())
                    Text(statusLine)
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(timer.isRunning ? accent : .secondary)
                        .textCase(.uppercase).tracking(0.6)
                }
            }
            .frame(width: 138, height: 138)
            .padding(.top, 2)
            if let end = timer.endsAt {
                Label(end.shortTime, systemImage: "bell").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).frame(height: 24).glass(Capsule(), strength: 0.7)
            } else if timer.isPaused {
                Label("Paused", systemImage: "pause.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).frame(height: 24).glass(Capsule(), strength: 0.7)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var statusLine: String {
        if timer.isRunning { return timer.isPaused ? "paused" : timer.modeTitle }
        return picker == 0 ? "focus" : picker == 1 ? "timer" : "stopwatch"
    }

    private var previewString: String {
        switch picker {
        case 0: TimeInterval(prefs.pomodoroWorkMinutes * 60).clockString
        case 1: TimeInterval(timer.customMinutes * 60).clockString
        default: "0:00"
        }
    }

    // MARK: Setup (idle)

    @ViewBuilder private var setup: some View {
        GlassSegments(selection: $picker, items: [("Focus", "brain.head.profile"), ("Timer", "timer"), ("Stopwatch", "stopwatch")], tint: .orange)
        Group {
            switch picker {
            case 0: focusSetup
            case 1: countdownSetup
            default: stopwatchSetup
            }
        }
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Button {
                switch picker {
                case 0: timer.startPomodoro()
                case 1: timer.startCountdown(minutes: timer.customMinutes)
                default: timer.startStopwatch()
                }
            } label: { Label(picker == 0 ? "Start focus" : picker == 1 ? "Start timer" : "Start", systemImage: "play.fill") }
            .buttonStyle(.loftProminent(picker == 2 ? .cyan : .orange))
            if picker == 0 {
                Button { timer.startBreak() } label: { Label("Take a break", systemImage: "cup.and.saucer") }.buttonStyle(.loftGlass)
            }
            Spacer()
            Text(prefs.timerFullScreenAlert ? "Full-screen alert when done" : "Island alert when done")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var focusSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            chipRow(title: "Focus", values: [15, 25, 45, 50, 90], selected: prefs.pomodoroWorkMinutes) { prefs.pomodoroWorkMinutes = $0 }
            chipRow(title: "Break", values: [5, 10, 15, 20], selected: prefs.pomodoroBreakMinutes) { prefs.pomodoroBreakMinutes = $0 }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        ForEach(0..<max(4, min(8, timer.sessionsToday + 1)), id: \.self) { i in
                            Circle().fill(i < timer.sessionsToday ? Color.orange : Color.white.opacity(0.12)).frame(width: 9, height: 9)
                        }
                        Text("\(timer.sessionsToday) session\(timer.sessionsToday == 1 ? "" : "s")")
                            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 4)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("This week").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    SessionHistoryChart(history: timer.sessionHistory())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .glassCard(cornerRadius: 12, strength: 0.8)
        }
    }

    private var countdownSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipRow(title: "Minutes", values: [5, 10, 15, 25, 45, 60], selected: timer.customMinutes) { timer.customMinutes = $0 }
            HStack(spacing: 8) {
                Text("Custom").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                HStack(spacing: 0) {
                    Button { timer.customMinutes = max(1, timer.customMinutes - (timer.customMinutes > 10 ? 5 : 1)) } label: { Image(systemName: "minus").frame(width: 26, height: 24) }
                    Text("\(timer.customMinutes) min").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 64)
                    Button { timer.customMinutes = min(240, timer.customMinutes + (timer.customMinutes >= 10 ? 5 : 1)) } label: { Image(systemName: "plus").frame(width: 26, height: 24) }
                }
                .buttonStyle(.plain).glass(Capsule(), strength: 0.8)
                Spacer()
            }
        }
    }

    private var stopwatchSetup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drift-free stopwatch").font(.system(size: 12, weight: .semibold))
            Text("Pause and resume as often as you like. The ring sweeps once per minute; the pill shows the elapsed time while you work.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).glassCard(cornerRadius: 12, strength: 0.8)
    }

    private func chipRow(title: String, values: [Int], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            ForEach(values, id: \.self) { m in
                Button("\(m)") { pick(m) }
                    .buttonStyle(m == selected ? .loftProminent(.orange) : .loftGlass).controlSize(.mini)
            }
            if !values.contains(selected) {
                Text("\(selected) min").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Running

    @ViewBuilder private var running: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timer.modeTitle).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(runningHint).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        if timer.mode == .pomodoroWork || timer.mode == .pomodoroBreak {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    ForEach(0..<max(4, min(8, timer.sessionsToday + 1)), id: \.self) { i in
                        Circle().fill(i < timer.sessionsToday ? Color.orange : Color.white.opacity(0.12)).frame(width: 9, height: 9)
                    }
                    Text("\(timer.sessionsToday) done today").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 4)
                }
                Spacer()
                SessionHistoryChart(history: timer.sessionHistory())
            }
            .padding(10).glassCard(cornerRadius: 12, strength: 0.8)
        }
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Button { timer.isPaused ? timer.resume() : timer.pause() } label: {
                Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill")
            }.buttonStyle(.loftProminent(accent))
            Button { timer.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.loftGlass)
            if timer.mode != .stopwatch {
                Button("+1 min") { timer.extend(minutes: 1) }.buttonStyle(.loftGlass)
                Button("+5") { timer.extend(minutes: 5) }.buttonStyle(.loftGlass)
            }
            if timer.mode == .pomodoroWork {
                Spacer()
                Button { timer.startBreak() } label: { Label("Skip to break", systemImage: "forward.end.fill") }.buttonStyle(.loftQuiet)
            } else if timer.mode == .pomodoroBreak {
                Spacer()
                Button { timer.startPomodoro() } label: { Label("Back to focus", systemImage: "forward.end.fill") }.buttonStyle(.loftQuiet)
            }
        }
    }

    private var runningHint: String {
        switch timer.mode {
        case .pomodoroWork: "Stay on one thing. \(prefs.pomodoroBreakMinutes)-minute break afterwards."
        case .pomodoroBreak: "Step away from the screen; focus resumes when you are back."
        case .countdown: timer.endsAt.map { "Rings at \($0.shortTime)." } ?? "Paused."
        case .stopwatch: "Running since \(Date().addingTimeInterval(-timer.remaining).shortTime)."
        case .idle: ""
        }
    }
}

/// Glass segmented control: one capsule, the selected segment lit with the tint.
struct GlassSegments: View {
    @Binding var selection: Int
    let items: [(String, String)]
    var tint: Color
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let on = i == selection
                Button { withAnimation(.smooth(duration: 0.22)) { selection = i } } label: {
                    Label(item.0, systemImage: item.1)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(on ? Color.black.opacity(0.9) : .white.opacity(0.75))
                        .padding(.horizontal, 12).frame(height: 22)
                        .frame(maxWidth: .infinity)
                        .background {
                            if on {
                                Capsule().fill(tint)
                                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)))
                                    .shadow(color: tint.opacity(0.4), radius: 6, y: 1)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .glass(Capsule(), strength: 0.7)
    }
}

/// Seven small bars, one per day, so a streak is visible at a glance.
struct SessionHistoryChart: View {
    let history: [(date: Date, count: Int)]
    var body: some View {
        let peak = max(1, history.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(history.enumerated()), id: \.offset) { i, day in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == history.count - 1 ? Color.orange : Color.orange.opacity(0.45))
                        .frame(width: 10, height: max(2, 22 * CGFloat(day.count) / CGFloat(peak)))
                    Text(day.date, format: .dateTime.weekday(.narrow)).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                }
                .help("\(day.count) session\(day.count == 1 ? "" : "s")")
            }
        }
        .frame(height: 30, alignment: .bottom)
    }
}
