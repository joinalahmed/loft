import Foundation
import SwiftUI
import Combine

struct WorldClockZone: Identifiable, Codable, Equatable {
    var id: String { identifier }
    let identifier: String          // e.g. "Asia/Riyadh"
    var label: String?              // user override, e.g. "Mum"

    var timeZone: TimeZone { TimeZone(identifier: identifier) ?? .current }
    var city: String { label ?? Self.cityName(identifier) }

    static func cityName(_ id: String) -> String {
        (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }

    func time(at date: Date) -> String {
        let f = DateFormatter(); f.timeZone = timeZone; f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }

    /// "+3h", "−8h", "+5½h", "Same time"
    func offsetText(at date: Date) -> String {
        let delta = timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if delta == 0 { return "Same time" }
        let hours = Double(delta) / 3600
        let sign = hours > 0 ? "+" : "−"
        let whole = Int(abs(hours)); let frac = abs(hours) - Double(whole)
        let fracText = frac == 0 ? "" : frac == 0.5 ? "½" : frac == 0.75 ? "¾" : "¼"
        return "\(sign)\(whole)\(fracText)h"
    }

    /// "Tomorrow", "Yesterday" or nil when the calendar day matches ours.
    func dayText(at date: Date) -> String? {
        var cal = Calendar.current; cal.timeZone = timeZone
        let theirs = cal.startOfDay(for: date)
        let ours = Calendar.current.startOfDay(for: date)
        let diff = Int((theirs.timeIntervalSince1970 - ours.timeIntervalSince1970) / 86400 + (theirs > ours ? 0.5 : -0.5))
        if diff > 0 { return "Tomorrow" } else if diff < 0 { return "Yesterday" } else { return nil }
    }

    /// Hour 0…23 in that zone, for the day/night tint.
    func hour(at date: Date) -> Int {
        var cal = Calendar.current; cal.timeZone = timeZone
        return cal.component(.hour, from: date)
    }
}

@MainActor
final class WorldClockStore: ObservableObject {
    static let shared = WorldClockStore()
    @Published var zones: [WorldClockZone] { didSet { save() } }
    private let key = "worldClockZones"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let z = try? JSONDecoder().decode([WorldClockZone].self, from: data) {
            zones = z
        } else {
            zones = ["Europe/London", "America/New_York", "Asia/Tokyo"].filter { $0 != TimeZone.current.identifier }.map { WorldClockZone(identifier: $0) }
        }
    }

    func add(_ identifier: String, label: String? = nil) {
        guard TimeZone(identifier: identifier) != nil, !zones.contains(where: { $0.identifier == identifier }) else { return }
        zones.append(WorldClockZone(identifier: identifier, label: label))
    }
    func remove(_ zone: WorldClockZone) { zones.removeAll { $0.id == zone.id } }
    func move(from: IndexSet, to: Int) { zones.move(fromOffsets: from, toOffset: to) }
    func injectDemo(_ ids: [String]) { zones = ids.map { WorldClockZone(identifier: $0) } }
    private func save() { guard !Demo.active else { return }; if let d = try? JSONEncoder().encode(zones) { UserDefaults.standard.set(d, forKey: key) } }

    /// Searchable list of all zones: "Riyadh", "Asia/Riyadh", "GMT+3".
    static let allIdentifiers: [String] = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !$0.hasPrefix("Etc/") }

    /// Zone identifiers for a free-text query (used by the API); the tab uses `WorldClockPlaces.search`.
    static func search(_ q: String) -> [String] { WorldClockPlaces.search(q).map(\.zone) }
}
