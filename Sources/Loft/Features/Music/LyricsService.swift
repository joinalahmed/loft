import Foundation
import Combine

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
    static func == (a: LyricLine, b: LyricLine) -> Bool { a.time == b.time && a.text == b.text }
}

/// Time-synced lyrics from LRCLIB (free, no key). Cached per track for the session.
@MainActor
final class LyricsService: ObservableObject {
    static let shared = LyricsService()
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plain: String?
    @Published private(set) var loading = false
    @Published private(set) var unavailable = false
    private var cache: [String: ([LyricLine], String?)] = [:]
    private var currentKey = ""
    private var task: Task<Void, Never>?
    private init() {}

    func track(title: String, artist: String, album: String, duration: Double) {
        let key = "\(title)|\(artist)|\(Int(duration))"
        guard key != currentKey else { return }
        currentKey = key
        lines = []; plain = nil; unavailable = false
        guard !title.isEmpty, Preferences.shared.lyricsEnabled else { return }
        if let hit = cache[key] { lines = hit.0; plain = hit.1; unavailable = hit.0.isEmpty && hit.1 == nil; return }
        task?.cancel()
        loading = true
        task = Task { [weak self] in
            var comps = URLComponents(string: "https://lrclib.net/api/get")!
            var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
            if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
            if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
            comps.queryItems = items
            var req = URLRequest(url: comps.url!)
            req.setValue("Loft/0.1 (https://github.com/joinalahmed/loft)", forHTTPHeaderField: "User-Agent")
            var parsed: [LyricLine] = []; var plainText: String?
            if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let synced = obj["syncedLyrics"] as? String { parsed = Self.parse(synced) }
                plainText = obj["plainLyrics"] as? String
            }
            guard let self, !Task.isCancelled, self.currentKey == key else { return }
            self.cache[key] = (parsed, plainText)
            self.lines = parsed; self.plain = plainText
            self.unavailable = parsed.isEmpty && plainText == nil
            self.loading = false
        }
    }

    func currentIndex(at t: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var idx: Int?
        for (i, l) in lines.enumerated() where l.time <= t + 0.2 { idx = i }
        return idx
    }

    static func parse(_ lrc: String) -> [LyricLine] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)"#)
        var out: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            guard let m = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { continue }
            let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
            let text = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            out.append(LyricLine(time: min * 60 + sec, text: text.isEmpty ? "♪" : text))
        }
        return out.sorted { $0.time < $1.time }
    }
}
