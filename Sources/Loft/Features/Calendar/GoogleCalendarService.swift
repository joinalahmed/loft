import Foundation
import AppKit
import SwiftUI
import Network
import CryptoKit
import Combine

/// Direct Google Calendar sync over OAuth 2.0 (installed-app flow with PKCE and a loopback
/// redirect), independent of the accounts added to macOS. Needs an OAuth client of type
/// "Desktop app" from Google Cloud Console; the refresh token lives in the Keychain.
@MainActor
final class GoogleCalendarService: ObservableObject {
    static let shared = GoogleCalendarService()
    @Published private(set) var events: [MeetingEvent] = []
    @Published private(set) var calendars: [GoogleCalendar] = []
    /// Remembered outside the keychain so launch never waits on a keychain prompt.
    @Published private(set) var isConnected = false { didSet { UserDefaults.standard.set(isConnected, forKey: "googleConnected") } }
    @Published private(set) var isConnecting = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSync: Date?
    @Published var accountEmail: String { didSet { UserDefaults.standard.set(accountEmail, forKey: "googleAccountEmail") } }

    /// True once the user has granted the event-editing scope (older connections are read-only).
    @Published private(set) var canWrite: Bool { didSet { UserDefaults.standard.set(canWrite, forKey: "googleCanWrite") } }

    struct GoogleCalendar: Identifiable, Equatable { let id: String; let name: String; let color: Color; let primary: Bool; var writable = false }

    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var listener: NWListener?
    private var pendingVerifier = ""
    private var pendingState = ""
    private var refreshTimer: Timer?
    private let scopes = "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/userinfo.email"
    private var prefs: Preferences { Preferences.shared }

    /// The pasted value often carries duplicates, newlines or a label; keep only the first real ID.
    static func sanitizeClientID(_ raw: String) -> String {
        let pattern = #"[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com"#
        if let r = raw.range(of: pattern, options: .regularExpression) { return String(raw[r]) }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var clientID: String { Self.sanitizeClientID(prefs.googleClientID) }
    var clientSecret: String {
        let s = prefs.googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: #"GOCSPX-[A-Za-z0-9_\-]+"#, options: .regularExpression) { return String(s[r]) }
        return s
    }

    private init() {
        accountEmail = UserDefaults.standard.string(forKey: "googleAccountEmail") ?? ""
        let d = UserDefaults.standard
        let connected = d.object(forKey: "googleConnected") != nil ? d.bool(forKey: "googleConnected") : !(d.string(forKey: "googleAccountEmail") ?? "").isEmpty
        canWrite = connected && UserDefaults.standard.bool(forKey: "googleCanWrite")
        isConnected = connected
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.sync() } }
        if isConnected { sync() }
    }

    // MARK: Connect / disconnect

    func connect() {
        let clientID = self.clientID
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { lastError = "That does not look like an OAuth client ID (…apps.googleusercontent.com)."; return }
        lastError = nil; isConnecting = true
        pendingVerifier = Self.randomString(64)
        pendingState = Self.randomString(16)
        let challenge = Data(SHA256.hash(data: Data(pendingVerifier.utf8))).base64URL
        do {
            let l = try NWListener(using: .tcp, on: .any)
            l.newConnectionHandler = { [weak self] conn in Task { @MainActor in self?.handleRedirect(conn) } }
            l.stateUpdateHandler = { [weak self] state in
                guard case .ready = state, let port = l.port?.rawValue else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.redirectPort = port
                    var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                    c.queryItems = [
                        .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: "http://127.0.0.1:\(port)"),
                        .init(name: "response_type", value: "code"), .init(name: "scope", value: self.scopes),
                        .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
                        .init(name: "state", value: self.pendingState),
                    ]
                    if !self.accountEmail.isEmpty { c.queryItems?.append(.init(name: "login_hint", value: self.accountEmail)) }
                    NSWorkspace.shared.open(c.url!)
                }
            }
            l.start(queue: .main)
            listener = l
            // Give up after five minutes so the port is not held forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                guard let self, self.isConnecting else { return }
                self.listener?.cancel(); self.listener = nil; self.isConnecting = false
                self.lastError = "Sign-in timed out."
            }
        } catch { lastError = error.localizedDescription; isConnecting = false }
    }

    private func handleRedirect(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return }
                let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                let line = request.components(separatedBy: "\r\n").first ?? ""
                let path = line.components(separatedBy: " ").dropFirst().first ?? "/"
                let comps = URLComponents(string: "http://127.0.0.1" + path)
                let code = comps?.queryItems?.first { $0.name == "code" }?.value
                let state = comps?.queryItems?.first { $0.name == "state" }?.value
                let ok = code != nil && state == self.pendingState
                let body = ok
                    ? "<html><body style='font-family:-apple-system;background:#111;color:#eee;display:flex;height:100vh;align-items:center;justify-content:center'><div style='text-align:center'><div style='font-size:40px'>✓</div><h2>Loft is connected to Google Calendar</h2><p>You can close this tab.</p></div></body></html>"
                    : "<html><body style='font-family:-apple-system'><h2>Sign-in failed</h2><p>\(comps?.queryItems?.first { $0.name == "error" }?.value ?? "no code")</p></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
                self.listener?.cancel(); self.listener = nil
                guard ok, let code else { self.isConnecting = false; self.lastError = "Google did not return a code."; return }
                await self.exchange(code: code)
            }
        }
    }

    private func exchange(code: String) async {
        let port = redirectPort   // the redirect URI must match the one in the auth request exactly
        var form = ["code": code, "client_id": clientID, "code_verifier": pendingVerifier,
                    "grant_type": "authorization_code", "redirect_uri": "http://127.0.0.1:\(port)"]
        let secret = clientSecret
        if !secret.isEmpty { form["client_secret"] = secret }
        guard let obj = await Self.post("https://oauth2.googleapis.com/token", form: form) else { isConnecting = false; lastError = "Token exchange failed."; return }
        if let err = obj["error_description"] as? String ?? obj["error"] as? String { isConnecting = false; lastError = err; return }
        guard let access = obj["access_token"] as? String else { isConnecting = false; lastError = "No access token."; return }
        if let refresh = obj["refresh_token"] as? String { await Keychain.setAsync(refresh, for: "google.refreshToken") }
        accessToken = access
        accessExpiry = Date().addingTimeInterval((obj["expires_in"] as? Double ?? 3600) - 60)
        isConnected = true; isConnecting = false
        // Google lets the user untick individual permissions, so trust only what was granted.
        let granted = (obj["scope"] as? String ?? "").split(separator: " ")
        canWrite = granted.contains { $0.hasSuffix("/auth/calendar.events") || $0.hasSuffix("/auth/calendar") }
        if let info = await Self.get("https://www.googleapis.com/oauth2/v3/userinfo", token: access), let email = info["email"] as? String { accountEmail = email }
        sync()
        NotchViewModel.shared.show(message: IslandMessage(title: "Google Calendar connected", subtitle: accountEmail, symbol: "calendar.badge.checkmark", tint: .green), duration: 4)
    }

    private var redirectPort: UInt16 = 0

    func disconnect() {
        Task.detached {
            if let t = Keychain.get("google.refreshToken") { _ = await Self.post("https://oauth2.googleapis.com/revoke", form: ["token": t]) }
            Keychain.delete("google.refreshToken")
        }
        accessToken = nil; isConnected = false; canWrite = false; events = []; calendars = []; accountEmail = ""; lastSync = nil
        CalendarManager.shared.mergeSources()
    }

    // MARK: Sync

    private var tokenTask: Task<String?, Never>?

    /// One refresh at a time, so several callers at launch cause at most one keychain prompt.
    private func validToken() async -> String? {
        if let t = accessToken, Date() < accessExpiry { return t }
        if let task = tokenTask { return await task.value }
        let task = Task { await self.refreshAccessToken() }
        tokenTask = task
        let token = await task.value
        tokenTask = nil
        return token
    }

    private func refreshAccessToken() async -> String? {
        guard let refresh = await Keychain.getAsync("google.refreshToken") else {
            lastError = "Loft could not read the Google sign-in from the keychain. Allow access, or reconnect in Settings."
            return nil
        }
        var form = ["refresh_token": refresh, "client_id": clientID, "grant_type": "refresh_token"]
        let secret = clientSecret
        if !secret.isEmpty { form["client_secret"] = secret }
        guard let obj = await Self.post("https://oauth2.googleapis.com/token", form: form), let access = obj["access_token"] as? String else {
            lastError = "Could not refresh the Google token. Reconnect in Settings."
            return nil
        }
        accessToken = access
        accessExpiry = Date().addingTimeInterval((obj["expires_in"] as? Double ?? 3600) - 60)
        return access
    }

    func sync() {
        guard isConnected, prefs.calendarEnabled else { return }
        Task { [weak self] in
            guard let self, let token = await self.validToken() else { return }
            guard let list = await Self.get("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader", token: token),
                  let items = list["items"] as? [[String: Any]] else { return }
            let cals = items.compactMap { c -> GoogleCalendar? in
                guard let id = c["id"] as? String, c["selected"] as? Bool ?? true, c["hidden"] as? Bool != true else { return nil }
                return GoogleCalendar(id: id, name: c["summaryOverride"] as? String ?? c["summary"] as? String ?? id,
                                      color: Color(hex: c["backgroundColor"] as? String ?? "#4285F4") ?? .blue, primary: c["primary"] as? Bool ?? false,
                                      writable: ["owner", "writer"].contains(c["accessRole"] as? String ?? ""))
            }
            let dayStart = Calendar.current.startOfDay(for: Date())
            let dayEnd = Calendar.current.date(byAdding: .day, value: 2, to: dayStart)!
            self.calendars = cals
            self.events = await Self.fetch(from: dayStart, to: dayEnd, calendars: cals, token: token)
            self.lastSync = Date(); self.lastError = nil
            CalendarManager.shared.mergeSources()
        }
    }

    /// Events in a range across the given calendars, sorted by start.
    private static func fetch(from start: Date, to end: Date, calendars: [GoogleCalendar], token: String) async -> [MeetingEvent] {
        let iso = ISO8601DateFormatter()
        var all: [MeetingEvent] = []
        for cal in calendars {
            var c = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cal.id)/events")!
            c.queryItems = [.init(name: "timeMin", value: iso.string(from: start)), .init(name: "timeMax", value: iso.string(from: end)),
                            .init(name: "singleEvents", value: "true"), .init(name: "orderBy", value: "startTime"), .init(name: "maxResults", value: "250")]
            guard let obj = await Self.get(c.url!.absoluteString, token: token), let items = obj["items"] as? [[String: Any]] else { continue }
            for e in items { if let ev = Self.event(from: e, calendar: cal) { all.append(ev) } }
        }
        return all.sorted { $0.startDate < $1.startDate }
    }

    /// On-demand range query for the month view; empty when not connected.
    func events(from start: Date, to end: Date) async -> [MeetingEvent] {
        guard isConnected, let token = await validToken() else { return [] }
        if calendars.isEmpty { sync() }
        return await Self.fetch(from: start, to: end, calendars: calendars, token: token)
    }

    private static func event(from e: [String: Any], calendar: GoogleCalendar) -> MeetingEvent? {
        guard let id = e["id"] as? String, let start = e["start"] as? [String: Any], let end = e["end"] as? [String: Any] else { return nil }
        let iso = ISO8601DateFormatter(); let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.timeZone = .current
        func date(_ d: [String: Any]) -> (Date, Bool)? {
            if let s = d["dateTime"] as? String, let x = iso.date(from: s) ?? isoFrac.date(from: s) { return (x, false) }
            if let s = d["date"] as? String, let x = day.date(from: s) { return (x, true) }
            return nil
        }
        guard let (s, allDay) = date(start), let (en, _) = date(end) else { return nil }
        var url: URL? = (e["hangoutLink"] as? String).flatMap(URL.init(string:))
        if url == nil, let conf = e["conferenceData"] as? [String: Any], let points = conf["entryPoints"] as? [[String: Any]] {
            url = points.first { $0["entryPointType"] as? String == "video" }.flatMap { ($0["uri"] as? String).flatMap(URL.init(string:)) }
        }
        if url == nil, let link = e["htmlLink"] as? String, let l = URL(string: link), (e["location"] as? String)?.hasPrefix("http") == true, let loc = URL(string: e["location"] as! String) { url = loc; _ = l }
        let attendees = e["attendees"] as? [[String: Any]] ?? []
        let declined = attendees.first { $0["self"] as? Bool == true }?["responseStatus"] as? String == "declined"
        return MeetingEvent(id: "g:" + id, title: e["summary"] as? String ?? "(No title)", startDate: s, endDate: en, isAllDay: allDay,
                            location: e["location"] as? String, notes: e["description"] as? String, url: url,
                            calendarTitle: calendar.name, color: calendar.color, attendeeCount: attendees.count,
                            declined: declined, canceled: e["status"] as? String == "cancelled", source: .google,
                            calendarID: calendar.id, editable: calendar.writable)
    }

    // MARK: Writing

    private static func eventsURL(_ calendarID: String, event: String? = nil) -> String {
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "/")
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        return "https://www.googleapis.com/calendar/v3/calendars/\(enc(calendarID))/events" + (event.map { "/" + enc($0) } ?? "")
    }

    /// Creates an event; returns an error message, or nil on success.
    func createEvent(title: String, start: Date, end: Date, allDay: Bool, location: String?, calendarID: String) async -> String? {
        guard canWrite, let token = await validToken() else { return "Reconnect Google to allow adding events." }
        var body: [String: Any] = ["summary": title]
        if let location, !location.isEmpty { body["location"] = location }
        if allDay {
            let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.timeZone = .current; day.locale = Locale(identifier: "en_US_POSIX")
            let cal = Calendar.current
            body["start"] = ["date": day.string(from: start)]
            body["end"] = ["date": day.string(from: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!)]   // exclusive
        } else {
            let iso = ISO8601DateFormatter()
            body["start"] = ["dateTime": iso.string(from: start), "timeZone": TimeZone.current.identifier]
            body["end"] = ["dateTime": iso.string(from: end), "timeZone": TimeZone.current.identifier]
        }
        return await write("POST", Self.eventsURL(calendarID), token: token, json: body)
    }

    /// Deletes one event (a single occurrence when it repeats); returns an error message, or nil.
    func deleteEvent(_ ev: MeetingEvent) async -> String? {
        guard ev.source == .google, let calendarID = ev.calendarID else { return "This event cannot be deleted from Loft." }
        guard canWrite, let token = await validToken() else { return "Reconnect Google to allow editing events." }
        return await write("DELETE", Self.eventsURL(calendarID, event: String(ev.id.dropFirst(2))), token: token, json: nil)
    }

    private func write(_ method: String, _ url: String, token: String, json: [String: Any]?) async -> String? {
        var req = URLRequest(url: URL(string: url)!); req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try? JSONSerialization.data(withJSONObject: json) }
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else { return "Could not reach Google Calendar." }
        if (200..<300).contains(code) || (method == "DELETE" && code == 410) { return nil }
        let message = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
        if code == 403, message?.localizedCaseInsensitiveContains("scope") == true || message?.localizedCaseInsensitiveContains("insufficient") == true {
            canWrite = false
            return "Google has not granted Loft permission to edit events. Reconnect to allow it."
        }
        return message ?? "Google Calendar returned an error (\(code))."
    }

    // MARK: HTTP

    private static func post(_ url: String, form: [String: String]) async -> [String: Any]? {
        var req = URLRequest(url: URL(string: url)!); req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents(); c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = Data((c.percentEncodedQuery ?? "").utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func get(_ url: String, token: String) async -> [String: Any]? {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
