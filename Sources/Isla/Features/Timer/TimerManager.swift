import AppKit
import SwiftUI
import Combine

@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()
    enum Mode: String { case idle, countdown, pomodoroWork, pomodoroBreak, stopwatch }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var now = Date()
    @Published private(set) var sessionsToday: Int = UserDefaults.standard.integer(forKey: "pomodoroSessions.\(TimerManager.dayKey)")
    @Published var customMinutes = 10

    private var endDate = Date()
    private var startDate = Date()
    private var total: TimeInterval = 0
    private var pausedRemaining: TimeInterval = 0
    private var ticker: Timer?
    private let prefs = Preferences.shared

    private init() {}

    static var dayKey: String { dayKey(for: Date()) }
    static func dayKey(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    /// Completed focus sessions for the last `days` days, oldest first.
    func sessionHistory(days: Int = 7) -> [(date: Date, count: Int)] {
        (0..<days).reversed().map { back in
            let d = Calendar.current.date(byAdding: .day, value: -back, to: Date())!
            return (d, back == 0 ? sessionsToday : UserDefaults.standard.integer(forKey: "pomodoroSessions.\(Self.dayKey(for: d))"))
        }
    }

    var remaining: TimeInterval {
        if mode == .stopwatch { return isPaused ? pausedRemaining : now.timeIntervalSince(startDate) }
        if isPaused { return pausedRemaining }
        return max(0, endDate.timeIntervalSince(now))
    }

    var progress: Double {
        guard total > 0, mode != .stopwatch else { return 0 }
        return 1 - remaining / total
    }

    var modeTitle: String {
        switch mode {
        case .idle: "Timer"
        case .countdown: "Countdown"
        case .pomodoroWork: "Focus"
        case .pomodoroBreak: "Break"
        case .stopwatch: "Stopwatch"
        }
    }

    // MARK: Controls

    func startCountdown(minutes: Int) { begin(.countdown, duration: TimeInterval(minutes * 60)) }
    func startPomodoro() { begin(.pomodoroWork, duration: TimeInterval(prefs.pomodoroWorkMinutes * 60)) }
    func startBreak() { begin(.pomodoroBreak, duration: TimeInterval(prefs.pomodoroBreakMinutes * 60)) }

    func startStopwatch() {
        mode = .stopwatch; startDate = Date(); total = 0; isPaused = false
        run()
    }

    private func begin(_ m: Mode, duration: TimeInterval) {
        mode = m; total = duration; startDate = Date(); endDate = Date().addingTimeInterval(duration); isPaused = false
        run()
        Haptics.level()
    }

    private func run() {
        isRunning = true
        now = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        pausedRemaining = remaining; isPaused = true
    }

    func resume() {
        guard isRunning, isPaused else { return }
        if mode == .stopwatch { startDate = Date().addingTimeInterval(-pausedRemaining) }
        else { endDate = Date().addingTimeInterval(pausedRemaining) }
        isPaused = false
    }

    func stop() {
        ticker?.invalidate(); ticker = nil
        isRunning = false; isPaused = false; mode = .idle; total = 0
    }

    private func tick() {
        now = Date()
        guard mode != .stopwatch, !isPaused, remaining <= 0 else { return }
        finished()
    }

    private func finished() {
        let finishedMode = mode
        if prefs.timerSound { NSSound(named: "Glass")?.play() }
        let vm = NotchViewModel.shared
        switch finishedMode {
        case .pomodoroWork:
            sessionsToday += 1
            UserDefaults.standard.set(sessionsToday, forKey: "pomodoroSessions.\(TimerManager.dayKey)")
            vm.show(message: IslandMessage(title: "Focus done · \(sessionsToday) today", subtitle: "Break for \(prefs.pomodoroBreakMinutes) min", symbol: "checkmark.circle.fill", tint: .green), duration: 5)
            startBreak()
        case .pomodoroBreak:
            vm.show(message: IslandMessage(title: "Break over", subtitle: "Back to focus", symbol: "bolt.fill", tint: .orange), duration: 5)
            startPomodoro()
        default:
            stop()
            vm.show(message: IslandMessage(title: "Timer done", subtitle: "\(Int(total / 60)) minutes are up", symbol: "timer", tint: .orange), duration: 6)
        }
    }
}
