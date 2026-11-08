import Foundation
import Combine
#if LOFT_ACTIVITYKIT
import ActivityKit
#endif

/// One place that knows what Loft is currently "doing": running timer, imminent meeting, download,
/// keep-awake, playback. Today the island, the menu bar and the local API read it; when ActivityKit
/// becomes available for native macOS apps (the macOS 27.2 SDK still marks every ActivityKit symbol
/// `@available(macOS, unavailable)`), `ActivityKitBridge` publishes the same records as system
/// Live Activities. Build with `-D LOFT_ACTIVITYKIT` once the SDK flips the availability.
struct LoftLiveActivity: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case timer, meeting, download, keepAwake, music }
    var id: String { kind.rawValue + ":" + key }
    var kind: Kind
    var key: String                 // stable per activity instance (event id, download path, "timer")
    var title: String
    var subtitle: String
    var progress: Double?           // 0…1 when meaningful
    var endDate: Date?              // when a countdown-style activity ends
    var deepLink: URL?              // what tapping it should open (join link, loft:// URL)
}

@MainActor
final class LiveActivityHub: ObservableObject {
    static let shared = LiveActivityHub()
    @Published private(set) var activities: [LoftLiveActivity] = []
    private var bag = Set<AnyCancellable>()
    private var tick: Timer?

    private init() {
        // Recompute whenever a source changes; coalesce bursts.
        let sources: [any ObservableObject] = [TimerManager.shared, CalendarManager.shared, KeepAwakeManager.shared, MusicManager.shared]
        for s in sources {
            (s.objectWillChange as? ObservableObjectPublisher)?
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &bag)
        }
        tick = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        refresh()
    }

    func refresh() {
        var list: [LoftLiveActivity] = []
        let timer = TimerManager.shared
        if timer.isRunning {
            let remaining = timer.remaining
            let mm = Int(remaining) / 60, ss = Int(remaining) % 60
            list.append(.init(kind: .timer, key: "timer", title: timer.modeTitle, subtitle: String(format: "%02d:%02d", mm, ss),
                              progress: timer.progress, endDate: remaining > 0 ? Date().addingTimeInterval(remaining) : nil,
                              deepLink: URL(string: "loft://open?tab=timer")))
        }
        if let ev = CalendarManager.shared.imminentEvent {
            list.append(.init(kind: .meeting, key: ev.id, title: ev.title, subtitle: ev.relativeStart, progress: nil, endDate: ev.startDate, deepLink: ev.joinURL))
        }
        let awake = KeepAwakeManager.shared
        if awake.isActive {
            list.append(.init(kind: .keepAwake, key: "awake", title: "Keep awake", subtitle: awake.statusText, progress: nil, endDate: awake.endDate, deepLink: nil))
        }
        let music = MusicManager.shared
        if music.isPlaying {
            list.append(.init(kind: .music, key: "music", title: music.title, subtitle: music.artist,
                              progress: music.duration > 0 ? music.elapsed / music.duration : nil, endDate: nil, deepLink: URL(string: "loft://open?tab=music")))
        }
        if list != activities {
            activities = list
            ActivityKitBridge.shared.sync(list)
        }
    }

    var json: [[String: Any]] {
        activities.map { a in
            var d: [String: Any] = ["id": a.id, "kind": a.kind.rawValue, "title": a.title, "subtitle": a.subtitle]
            if let p = a.progress { d["progress"] = p }
            if let e = a.endDate { d["endsAt"] = ISO8601DateFormatter().string(from: e) }
            if let u = a.deepLink { d["url"] = u.absoluteString }
            return d
        }
    }
}

/// Mirrors `LoftLiveActivity` records into ActivityKit. No-op until the SDK allows ActivityKit on macOS.
@MainActor
final class ActivityKitBridge {
    static let shared = ActivityKitBridge()
    var isAvailable: Bool {
        #if LOFT_ACTIVITYKIT
        return true
        #else
        return false
        #endif
    }

    func sync(_ list: [LoftLiveActivity]) {
        #if LOFT_ACTIVITYKIT
        Task { await syncActivityKit(list) }
        #endif
    }

    #if LOFT_ACTIVITYKIT
    struct LoftActivityAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable { var title: String; var subtitle: String; var progress: Double?; var endDate: Date? }
        var kind: String
        var key: String
    }
    private var live: [String: Activity<LoftActivityAttributes>] = [:]

    private func syncActivityKit(_ list: [LoftLiveActivity]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let wanted = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        for (id, activity) in live where wanted[id] == nil {
            await activity.end(nil, dismissalPolicy: .immediate); live[id] = nil
        }
        for a in list {
            let state = LoftActivityAttributes.ContentState(title: a.title, subtitle: a.subtitle, progress: a.progress, endDate: a.endDate)
            if let existing = live[a.id] {
                await existing.update(ActivityContent(state: state, staleDate: a.endDate))
            } else if let created = try? Activity.request(attributes: LoftActivityAttributes(kind: a.kind.rawValue, key: a.key),
                                                          content: ActivityContent(state: state, staleDate: a.endDate), pushType: nil) {
                live[a.id] = created
            }
        }
    }
    #endif
}
