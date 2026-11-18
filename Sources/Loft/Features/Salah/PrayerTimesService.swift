import Foundation
import SwiftUI
import AppKit
import AVFoundation

/// One entry of the daily timetable. Sunrise is listed for reference but is not a prayer.
struct PrayerTime: Identifiable, Equatable {
    let key: String        // fajr, sunrise, dhuhr, asr, maghrib, isha
    let date: Date
    let day: String        // yyyy-MM-dd the timetable belongs to
    var id: String { day + "|" + key }
    var isPrayer: Bool { key != "sunrise" }
    var name: String { key.prefix(1).uppercased() + key.dropFirst() }
    var symbol: String {
        switch key {
        case "fajr": "moon.haze.fill"
        case "sunrise": "sunrise.fill"
        case "dhuhr": "sun.max.fill"
        case "asr": "sun.min.fill"
        case "maghrib": "sunset.fill"
        default: "moon.stars.fill"
        }
    }
}

/// Salah times from ummahapi.com for a city (geocoded once through Open-Meteo, like the weather
/// tab, so no location permission is needed). Optionally keeps a block in the calendar for every
/// upcoming prayer.
@MainActor
final class PrayerTimesService: ObservableObject {
    static let shared = PrayerTimesService()
    static let order = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
    static let methods: [(key: String, name: String)] = [
        ("UmmAlQura", "Umm al-Qura, Makkah"), ("MuslimWorldLeague", "Muslim World League"), ("Egyptian", "Egyptian General Authority"),
        ("Karachi", "Karachi"), ("Dubai", "Dubai"), ("MoonsightingCommittee", "Moonsighting Committee"), ("NorthAmerica", "ISNA, North America"),
        ("Kuwait", "Kuwait"), ("Qatar", "Qatar"), ("Singapore", "Singapore"), ("Turkey", "Diyanet, Turkey"), ("Tehran", "Tehran"), ("JAKIM", "JAKIM, Malaysia"),
    ]
    static let blockMinutes = 30
    static let blockDays = 14           // how far ahead blocks are added

    /// Calendar block for a prayer: 30 minutes from the first xx:00, xx:15, xx:30 or xx:45 at or
    /// after the prayer time (Asr at 2:58 → 3:00–3:30).
    static func block(for prayer: Date) -> (start: Date, minutes: Int) {
        let quarter: TimeInterval = 15 * 60
        let t = prayer.timeIntervalSince1970
        return (Date(timeIntervalSince1970: (t / quarter).rounded(.up) * quarter), blockMinutes)
    }
    static func blockTitle(_ p: PrayerTime) -> String { "\(p.name) Salah" }
    /// True for events this service created, so they do not also raise a meeting alert.
    static func isBlock(_ ev: MeetingEvent) -> Bool {
        ev.title.hasSuffix(" Salah") && order.contains(String(ev.title.dropLast(6)).lowercased())
    }

    @Published private(set) var today: [PrayerTime] = []
    @Published private(set) var tomorrow: [PrayerTime] = []
    /// Today and the following `blockDays` days, in order.
    private var schedule: [PrayerTime] = []
    private var alertTimer: Timer?
    private var alerted = Set<String>()
    @Published private(set) var place = ""
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    /// Ids of prayers that already have a calendar block (so deleting one by hand sticks).
    @Published private(set) var blocked: Set<String>
    @Published private(set) var blockError: String?

    private var fetchedKey = ""
    private var timer: Timer?
    private var syncing = false
    private var blocksSyncedDay = ""
    private var prefs: Preferences { Preferences.shared }

    private init() {
        blocked = Set(UserDefaults.standard.stringArray(forKey: "salahBlocked") ?? [])
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshIfNeeded() } }
        timer?.tolerance = 60
    }

    /// City for the timetable; falls back to the weather city so one setting covers both.
    var city: String {
        let own = prefs.salahCity.trimmingCharacters(in: .whitespaces)
        return own.isEmpty ? prefs.weatherCity.trimmingCharacters(in: .whitespaces) : own
    }

    /// The next prayer still ahead (tomorrow's Fajr after Isha).
    func next(after now: Date = Date()) -> PrayerTime? { (today + tomorrow).first { $0.isPrayer && $0.date > now } }
    /// The prayer whose time has most recently begun.
    func current(at now: Date = Date()) -> PrayerTime? { today.last { $0.isPrayer && $0.date <= now } }

    func injectDemo() {
        let cal = Calendar.current, f = Self.dayFormatter
        func table(_ offset: Int) -> [PrayerTime] {
            let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
            let times = [(5, 6), (6, 24), (11, 52), (14, 58), (17, 19), (18, 49)]
            return zip(Self.order, times).map { PrayerTime(key: $0, date: cal.date(bySettingHour: $1.0, minute: $1.1, second: 0, of: day)!, day: f.string(from: day)) }
        }
        schedule = (0...Self.blockDays).flatMap(table)
        today = table(0); tomorrow = table(1); place = "Riyadh, SA"; error = nil; loading = false; blocked = []
        scheduleAlert()
    }

    func refreshIfNeeded(force: Bool = false) {
        guard !Demo.active, prefs.salahEnabled else { return }
        let city = self.city
        guard !city.isEmpty else { today = []; tomorrow = []; return }
        let dayKey = Self.dayFormatter.string(from: Date())
        let key = [city.lowercased(), prefs.salahMethod, prefs.salahMadhab, dayKey].joined(separator: "|")
        if !force, key == fetchedKey, !today.isEmpty {
            scheduleAlert()
            // The calendar is checked once a day (and at launch); a failed check retries on the next tick.
            if blocksSyncedDay != dayKey { Task { await syncBlocks() } }
            return
        }
        guard !loading else { return }
        loading = true; error = nil
        Task {
            do {
                let geo = try await geocode(city)
                let cal = Calendar.current
                let first = cal.startOfDay(for: Date())
                let last = cal.date(byAdding: .day, value: Self.blockDays, to: first)!
                var all = try await fetchMonth(lat: geo.lat, lng: geo.lng, containing: first)
                if !cal.isDate(first, equalTo: last, toGranularity: .month) { all += try await fetchMonth(lat: geo.lat, lng: geo.lng, containing: last) }
                let f = Self.dayFormatter
                let (d0, d1, dN) = (f.string(from: first), f.string(from: cal.date(byAdding: .day, value: 1, to: first)!), f.string(from: last))
                let t0 = all.filter { $0.day == d0 }
                guard t0.count == Self.order.count else { throw fail("Prayer times came back incomplete") }
                schedule = all.filter { $0.day >= d0 && $0.day <= dN }
                today = t0; tomorrow = all.filter { $0.day == d1 }; place = geo.name; fetchedKey = key
            } catch { self.error = error.localizedDescription }
            loading = false
            scheduleAlert()
            await syncBlocks()
        }
    }

    // MARK: Network

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private func fail(_ message: String) -> NSError { NSError(domain: "Loft", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

    /// City → coordinates, remembered so the lookup happens once per city.
    private func geocode(_ city: String) async throws -> (lat: Double, lng: Double, name: String) {
        let cacheKey = "salahGeo"
        if let c = UserDefaults.standard.dictionary(forKey: cacheKey), c["city"] as? String == city.lowercased(),
           let lat = c["lat"] as? Double, let lng = c["lng"] as? Double, let name = c["name"] as? String { return (lat, lng, name) }
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        let (data, _) = try await URLSession.shared.data(from: geo.url!)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let r = (obj["results"] as? [[String: Any]])?.first,
              let lat = r["latitude"] as? Double, let lng = r["longitude"] as? Double else { throw fail("City not found") }
        let name = [r["name"] as? String, r["country_code"] as? String].compactMap { $0 }.joined(separator: ", ")
        UserDefaults.standard.set(["city": city.lowercased(), "lat": lat, "lng": lng, "name": name], forKey: cacheKey)
        return (lat, lng, name)
    }

    /// The whole month's timetable in one request.
    private func fetchMonth(lat: Double, lng: Double, containing date: Date) async throws -> [PrayerTime] {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        var c = URLComponents(string: "https://ummahapi.com/api/prayer-times/month")!
        c.queryItems = [.init(name: "lat", value: String(format: "%.4f", lat)), .init(name: "lng", value: String(format: "%.4f", lng)),
                        .init(name: "month", value: String(parts.month ?? 1)), .init(name: "year", value: String(parts.year ?? 2026)),
                        .init(name: "method", value: prefs.salahMethod), .init(name: "madhab", value: prefs.salahMadhab),
                        .init(name: "highLatitudeRule", value: "recommended")]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["success"] as? Bool == true, let d = obj["data"] as? [String: Any], let days = d["days"] as? [[String: Any]] else {
            throw fail("Prayer times are unavailable right now")
        }
        let iso = ISO8601DateFormatter()
        return days.flatMap { entry -> [PrayerTime] in
            guard let day = entry["date"] as? String, let times = entry["prayer_datetimes"] as? [String: String] else { return [] }
            return Self.order.compactMap { key in times[key].flatMap(iso.date(from:)).map { PrayerTime(key: key, date: $0, day: day) } }
        }
    }

    // MARK: Alert at prayer time

    /// Arms a one-shot timer for the next prayer; re-armed after every alert and every refresh.
    private func scheduleAlert() {
        alertTimer?.invalidate(); alertTimer = nil
        guard prefs.salahEnabled, prefs.salahFullScreenAlert, let p = schedule.first(where: { $0.isPrayer && $0.date > Date() }) else { return }
        prefetchAyah()
        let t = Timer(fire: p.date, interval: 0, repeats: false) { [weak self] _ in Task { @MainActor in self?.alert(p) } }
        RunLoop.main.add(t, forMode: .common)
        alertTimer = t
    }

    private func alert(_ p: PrayerTime) {
        defer { scheduleAlert() }
        // A timer that fires late (the Mac was asleep) should not announce a prayer long past.
        guard prefs.salahFullScreenAlert, !alerted.contains(p.id), Date().timeIntervalSince(p.date) < 600 else { return }
        alerted.insert(p.id)
        showAlert(p)
    }

    func showAlert(_ p: PrayerTime) {
        if prefs.meetingAlertSound { NSSound(named: "Glass")?.play() }
        let following = schedule.first { $0.isPrayer && $0.date > p.date }
        let ayah = nextAyah
        nextAyah = nil
        let timetable = schedule.filter { $0.day == p.day }
        var alert = FullScreenAlert(eyebrow: "Salah", accent: SalahAlertView.theme(for: p.key).accent, symbol: p.symbol, title: "Time for \(p.name)",
                                    detail: p.date.shortTime, footnote: nil, countdown: nil, actions: [], autoDismiss: 120)
        alert.custom = AnyView(SalahAlertView(prayer: p, today: timetable.isEmpty ? today : timetable, following: following, place: place, ayah: ayah))
        alert.onDismiss = { [weak self] in self?.stopPlayback() }
        FullScreenAlertController.shared.show(alert)
        prefetchAyah()
    }

    /// Preview from the tab or API: waits briefly for an ayah so the preview shows the real thing.
    func testAlert() {
        Task {
            if nextAyah == nil { nextAyah = await fetchAyah() }
            if let p = next() ?? today.last { showAlert(p) }
        }
    }

    // MARK: Ayah for the alert

    struct Ayah { let surah: Int; let ayah: Int; let surahName: String; let arabic: String; let translation: String }
    /// Fetched ahead of time so the alert appears on the minute, with no network wait.
    private var nextAyah: Ayah?
    private var player: AVPlayer?
    private var playingKey = ""
    private var endObserver: NSObjectProtocol?
    @Published private(set) var playing = false
    @Published private(set) var audioLoading = false

    private func prefetchAyah() {
        guard nextAyah == nil, prefs.salahFullScreenAlert else { return }
        Task { if nextAyah == nil { nextAyah = await fetchAyah() } }
    }

    private func fetchAyah() async -> Ayah? {
        if Demo.active {
            return Ayah(surah: 94, ayah: 5, surahName: "Ash-Sharh", arabic: "فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا", translation: "For indeed, with hardship [will be] ease.")
        }
        var req = URLRequest(url: URL(string: "https://ummahapi.com/api/quran/random")!); req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let d = obj["data"] as? [String: Any],
              let surah = d["surah"] as? [String: Any], let verse = d["verse"] as? [String: Any],
              let number = surah["number"] as? Int, let ayah = verse["ayah"] as? Int, let arabic = verse["arabic"] as? String else { return nil }
        let translation = (verse["translations"] as? [String: String])?["sahih_international"] ?? ""
        return Ayah(surah: number, ayah: ayah, surahName: surah["name_english"] as? String ?? "Surah \(number)", arabic: arabic, translation: translation)
    }

    /// Plays the recitation (first reciter the audio endpoint lists); a second press stops it.
    func togglePlayback(_ a: Ayah) {
        let key = "\(a.surah):\(a.ayah)"
        if playingKey == key { stopPlayback(); return }
        playingKey = key; audioLoading = true
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://ummahapi.com/api/quran/audio/\(a.surah)/\(a.ayah)")!),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let d = obj["data"] as? [String: Any],
                  let first = (d["reciters"] as? [[String: Any]])?.first, let link = first["audio_url"] as? String,
                  let url = URL(string: link), url.scheme == "https" else { if playingKey == key { stopPlayback() }; return }
            guard playingKey == key, FullScreenAlertController.shared.current != nil else { return }
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            player = p; audioLoading = false; playing = true
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stopPlayback() }
            }
            p.play()
            // Hold the alert up while the recitation runs (long ayat take a few minutes).
            let seconds = (try? await item.asset.load(.duration).seconds) ?? 0
            if seconds.isFinite, seconds > 0, player === p { FullScreenAlertController.shared.extendAutoDismiss(max(120, seconds + 20)) }
        }
    }

    private func stopPlayback() {
        player?.pause(); player = nil; playingKey = ""; playing = false; audioLoading = false
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    // MARK: Calendar blocks

    /// Calendar the blocks go to: the one picked in the tab, else the usual default.
    var blockTargetID: String {
        let cal = CalendarManager.shared
        let picked = prefs.salahCalendarTarget
        return cal.targets.contains { $0.id == picked } ? picked : cal.defaultTargetID
    }

    /// Adds a block for every prayer in the next two weeks that has none yet.
    /// `force` skips the preference check (demo screenshots only).
    func syncBlocks(force: Bool = false) async {
        guard prefs.salahEnabled, prefs.salahCalendarBlocks || force, !syncing else { return }
        let cal = CalendarManager.shared
        let target = blockTargetID
        guard !target.isEmpty else { blockError = "No calendar to add blocks to."; return }
        syncing = true; defer { syncing = false }
        // Right after launch, give Google a moment to load so existing blocks are recognised.
        let google = GoogleCalendarService.shared
        var waits = 0
        while !Demo.active, google.isConnected, google.lastSync == nil, waits < 20 { try? await Task.sleep(for: .milliseconds(500)); waits += 1 }
        let now = Date()
        var failure: String?
        var changed = 0

        // Reconcile what is already in the calendar: keep blocks that match, replace ones with an
        // older shape or a time that has since shifted, and drop duplicates.
        let dayStart = Calendar.current.startOfDay(for: now)
        let existing = await cal.events(from: dayStart, to: Calendar.current.date(byAdding: .day, value: Self.blockDays + 1, to: dayStart)!)
        var kept = Set<String>()
        // The same event can arrive through macOS and the direct Google connection; count it once.
        var seen = Set<String>()
        for ev in existing where seen.insert(ev.dedupeKey).inserted && Self.isBlock(ev) && ev.startDate > now && !ev.canceled {
            guard let p = schedule.first(where: { $0.isPrayer && Self.blockTitle($0) == ev.title && abs(ev.startDate.timeIntervalSince($0.date)) < 45 * 60 }) else { continue }
            let want = Self.block(for: p.date)
            let fits = abs(ev.startDate.timeIntervalSince(want.start)) < 30 && abs(ev.endDate.timeIntervalSince(ev.startDate) - Double(want.minutes * 60)) < 30
            if fits && !kept.contains(p.id) { kept.insert(p.id); blocked.insert(p.id); continue }
            guard cal.canDelete(ev) else { if fits { continue }; kept.insert(p.id); continue }   // not ours to change: leave it, add nothing beside it
            if let err = await cal.delete(ev, reload: false) { failure = err; break }
            changed += 1
            if !kept.contains(p.id) { blocked.remove(p.id) }
        }

        if failure == nil {
            for p in schedule where p.isPrayer && p.date > now && !blocked.contains(p.id) && !kept.contains(p.id) {
                let block = Self.block(for: p.date)
                let draft = CalendarManager.Draft(title: Self.blockTitle(p), day: block.start, start: block.start, minutes: block.minutes, targetID: target)
                if let err = await cal.add(draft, remember: false, reload: false) { failure = err; break }
                blocked.insert(p.id); changed += 1
                // Saved as we go, so quitting mid-way never leads to duplicates later.
                if !Demo.active { UserDefaults.standard.set(Array(blocked), forKey: "salahBlocked") }
            }
        }
        if changed > 0 { cal.reload() }
        blockError = failure
        if failure == nil { blocksSyncedDay = Self.dayFormatter.string(from: now) }
        // Keep the remembered ids short: only yesterday onwards matters.
        let floor = Self.dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: now)!)
        blocked = blocked.filter { $0 >= floor }
        if !Demo.active { UserDefaults.standard.set(Array(blocked), forKey: "salahBlocked") }
    }
}
