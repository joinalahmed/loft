import SwiftUI

struct TimerTabView: View {
    @ObservedObject var timer = TimerManager.shared
    @ObservedObject var prefs = Preferences.shared
    @State private var picker = 0   // 0 pomodoro, 1 countdown, 2 stopwatch

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                    Circle().trim(from: 0, to: timer.mode == .stopwatch ? 1 : CGFloat(timer.progress))
                        .stroke(timer.mode == .pomodoroBreak ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: timer.progress)
                    VStack(spacing: 2) {
                        Text(timer.isRunning ? timer.remaining.clockString : previewString)
                            .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(timer.isRunning ? timer.modeTitle + (timer.isPaused ? " · paused" : "") : "ready")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 128, height: 128)
            }
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $picker) {
                    Text("Pomodoro").tag(0); Text("Timer").tag(1); Text("Stopwatch").tag(2)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                Group {
                    switch picker {
                    case 0:
                        HStack(spacing: 8) {
                            Stepper("Focus \(prefs.pomodoroWorkMinutes) min", value: $prefs.pomodoroWorkMinutes, in: 5...90, step: 5)
                            Stepper("Break \(prefs.pomodoroBreakMinutes) min", value: $prefs.pomodoroBreakMinutes, in: 1...30)
                        }.font(.system(size: 11))
                        HStack(alignment: .bottom, spacing: 10) {
                            Text("\(timer.sessionsToday) focus session\(timer.sessionsToday == 1 ? "" : "s") completed today")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            SessionHistoryChart(history: timer.sessionHistory())
                        }
                    case 1:
                        HStack(spacing: 6) {
                            ForEach([5, 10, 15, 25, 45, 60], id: \.self) { m in
                                Button("\(m)") { timer.customMinutes = m; timer.startCountdown(minutes: m) }
                                    .buttonStyle(.loftGlass).controlSize(.small)
                            }
                        }
                        Stepper("Custom: \(timer.customMinutes) min", value: $timer.customMinutes, in: 1...240).font(.system(size: 11))
                    default:
                        Text("Drift-free stopwatch. Pause and resume as needed.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if timer.isRunning {
                        Button(timer.isPaused ? "Resume" : "Pause") { timer.isPaused ? timer.resume() : timer.pause() }
                            .buttonStyle(.loftProminent(.orange))
                        Button("Stop", role: .destructive) { timer.stop() }.buttonStyle(.loftGlass)
                    } else {
                        Button(startTitle) {
                            switch picker {
                            case 0: timer.startPomodoro()
                            case 1: timer.startCountdown(minutes: timer.customMinutes)
                            default: timer.startStopwatch()
                            }
                        }.buttonStyle(.loftProminent(.orange))
                    }
                }.controlSize(.small)
            }
        }
    }

    private var previewString: String {
        switch picker {
        case 0: TimeInterval(prefs.pomodoroWorkMinutes * 60).clockString
        case 1: TimeInterval(timer.customMinutes * 60).clockString
        default: "0:00"
        }
    }
    private var startTitle: String { picker == 0 ? "Start Focus" : picker == 1 ? "Start Timer" : "Start" }
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
        .frame(height: 34, alignment: .bottom)
    }
}
