import Foundation
import Combine
import SwiftUI

/// A UserDefaults-backed property wrapper usable inside an ObservableObject.
/// Changes publish through the enclosing object's `objectWillChange`.
@propertyWrapper
struct Stored<Value> {
    let key: String
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    @available(*, unavailable, message: "Only usable inside a class")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript<T: ObservableObject>(
        _enclosingInstance instance: T,
        wrapped _: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Stored<Value>>
    ) -> Value where T.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let wrapper = instance[keyPath: storageKeyPath]
            if let raw = UserDefaults.standard.object(forKey: wrapper.key) {
                if let typed = raw as? Value { return typed }
                if let data = raw as? Data, let decodable = Value.self as? Decodable.Type,
                   let decoded = try? JSONDecoder().decode(decodable, from: data) as? Value {
                    return decoded
                }
            }
            return wrapper.defaultValue
        }
        set {
            let wrapper = instance[keyPath: storageKeyPath]
            instance.objectWillChange.send()
            if isPlistCompatible(newValue) {
                UserDefaults.standard.set(newValue, forKey: wrapper.key)
            } else if let encodable = newValue as? Encodable,
                      let data = try? JSONEncoder().encode(AnyEncodable(encodable)) {
                UserDefaults.standard.set(data, forKey: wrapper.key)
            }
        }
    }
}

private func isPlistCompatible(_ value: Any) -> Bool {
    switch value {
    case is String, is Bool, is Int, is Double, is Float, is Data, is Date: return true
    case let array as [Any]: return array.allSatisfy(isPlistCompatible)
    case let dict as [String: Any]: return dict.values.allSatisfy(isPlistCompatible)
    default: return false
    }
}

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

enum PanelTab: String, CaseIterable, Codable, Identifiable {
    case home, music, shelf, clipboard, timer, calendar, reminders, notes, launcher, stocks, system, mirror, weather
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .timer: "Timer"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notes: "Notes"
        case .launcher: "Apps"
        case .stocks: "Stocks"
        case .system: "System"
        case .mirror: "Mirror"
        case .weather: "Weather"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .music: "music.note"
        case .shelf: "tray.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .timer: "timer"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .notes: "note.text"
        case .launcher: "square.grid.3x3.fill"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .system: "gauge.with.dots.needle.33percent"
        case .mirror: "web.camera.fill"
        case .weather: "cloud.sun.fill"
        }
    }
}

enum HUDStyle: String, CaseIterable, Codable {
    case inline, expanded
    var title: String { self == .inline ? "Inline (beside notch)" : "Expanded (below notch)" }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private init() {
        if localAPIToken.isEmpty { localAPIToken = Preferences.generateToken() }
    }

    // Behavior
    @Stored("openOnHover") var openOnHover = true
    @Stored("hoverDelay") var hoverDelay: Double = 0.25
    @Stored("hapticsEnabled") var hapticsEnabled = true
    @Stored("closeOnClickOutside") var closeOnClickOutside = true
    @Stored("invisibleUntilHover") var invisibleUntilHover = false
    @Stored("hideFromScreenCapture") var hideFromScreenCapture = false
    @Stored("launchAtLogin") var launchAtLogin = false
    @Stored("didFinishOnboarding") var didFinishOnboarding = false

    // Appearance
    @Stored("closedPillScale") var closedPillScale: Double = 1.0
    @Stored("panelWidth") var panelWidth: Double = 640
    @Stored("panelHeight") var panelHeight: Double = 240
    @Stored("enableShadow") var enableShadow = true
    @Stored("accentTinting") var accentTinting = true
    @Stored("showClockInPill") var showClockInPill = false

    // Features
    @Stored("musicLiveActivity") var musicLiveActivity = true
    @Stored("musicVisualizer") var musicVisualizer = true
    @Stored("hideMusicWhenPaused") var hideMusicWhenPaused = true
    @Stored("hudEnabled") var hudEnabled = true
    @Stored("hudStyle") var hudStyle: HUDStyle = .inline
    @Stored("hudReplacement") var hudReplacement = false
    @Stored("batteryAlerts") var batteryAlerts = true
    @Stored("clipboardEnabled") var clipboardEnabled = true
    @Stored("clipboardLimit") var clipboardLimit = 200
    @Stored("shelfEnabled") var shelfEnabled = true
    @Stored("timerEnabled") var timerEnabled = true
    @Stored("calendarEnabled") var calendarEnabled = true
    @Stored("notesEnabled") var notesEnabled = true
    @Stored("systemEnabled") var systemEnabled = true
    @Stored("mirrorEnabled") var mirrorEnabled = true
    @Stored("weatherEnabled") var weatherEnabled = true
    @Stored("weatherCity") var weatherCity = ""
    @Stored("weatherUseFahrenheit") var weatherUseFahrenheit = false
    @Stored("capsLockHUD") var capsLockHUD = true
    @Stored("lyricsEnabled") var lyricsEnabled = true
    @Stored("lyricsShown") var lyricsShown = false        // remembers the Music-tab toggle
    @Stored("downloadsEnabled") var downloadsEnabled = false      // opt-in: needs Downloads folder access
    @Stored("privacyIndicator") var privacyIndicator = true
    @Stored("callIsland") var callIsland = true
    @Stored("remindersEnabled") var remindersEnabled = true
    @Stored("launcherEnabled") var launcherEnabled = false
    @Stored("stocksEnabled") var stocksEnabled = false
    @Stored("stockSymbols") var stockSymbols: [String] = ["AAPL", "MSFT", "NVDA"]
    @Stored("batteryLowLevel") var batteryLowLevel = 20
    @Stored("batteryCriticalLevel") var batteryCriticalLevel = 10
    @Stored("batteryFullAlert") var batteryFullAlert = true
    @Stored("searchEngine") var searchEngine = "google"
    @Stored("menuBarNextMeeting") var menuBarNextMeeting = false
    @Stored("hideInFullscreen") var hideInFullscreen = false

    // Calendar / meetings
    @Stored("meetingAlertsEnabled") var meetingAlertsEnabled = true
    @Stored("meetingLeadMinutes") var meetingLeadMinutes = 2
    @Stored("meetingAlertOnlyWithLinks") var meetingAlertOnlyWithLinks = false
    @Stored("meetingAlertFullScreen") var meetingAlertFullScreen = true
    @Stored("meetingPillMinutes") var meetingPillMinutes = 10
    @Stored("meetingAlertSound") var meetingAlertSound = true

    // Screenshots
    @Stored("screenshotToShelf") var screenshotToShelf = true
    @Stored("screenshotToClipboard") var screenshotToClipboard = true
    @Stored("screenshotSaveToDesktop") var screenshotSaveToDesktop = true
    @Stored("watchDesktopScreenshots") var watchDesktopScreenshots = false   // opt-in: needs Desktop folder access

    // Keep awake
    @Stored("keepAwakeDefaultMinutes") var keepAwakeDefaultMinutes = 0   // 0 = until turned off
    @Stored("keepAwakeAllowDisplaySleep") var keepAwakeAllowDisplaySleep = false

    // Timer
    @Stored("pomodoroWorkMinutes") var pomodoroWorkMinutes = 25
    @Stored("pomodoroBreakMinutes") var pomodoroBreakMinutes = 5
    @Stored("timerSound") var timerSound = true

    // Developer
    @Stored("localAPIEnabled") var localAPIEnabled = false
    @Stored("localAPIPort") var localAPIPort = 9999
    @Stored("localAPIToken") var localAPIToken = ""
    @Stored("urlSchemeEnabled") var urlSchemeEnabled = true

    var enabledTabs: [PanelTab] {
        PanelTab.allCases.filter { tab in
            switch tab {
            case .home: true
            case .music: musicLiveActivity
            case .shelf: shelfEnabled
            case .clipboard: clipboardEnabled
            case .timer: timerEnabled
            case .calendar: calendarEnabled
            case .reminders: remindersEnabled
            case .notes: notesEnabled
            case .launcher: launcherEnabled
            case .stocks: stocksEnabled
            case .system: systemEnabled
            case .mirror: mirrorEnabled
            case .weather: weatherEnabled
            }
        }
    }

    static func generateToken() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<32).map { _ in chars.randomElement()! })
    }

    func restoreDefaults() {
        let keep = localAPIToken
        let domain = Bundle.main.bundleIdentifier ?? "dev.joinal.isla"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        localAPIToken = keep
        didFinishOnboarding = true
        objectWillChange.send()
    }
}
