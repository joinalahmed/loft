import AppKit
import SwiftUI
import Combine

/// Now Playing source. Primary path: the MediaRemote adapter run inside /usr/bin/perl
/// (Apple-signed, so mediaremoted still talks to it on macOS 15.4+). Fallback: AppleScript
/// polling of Spotify / Music.
@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager()

    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: Color?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var bundleIdentifier = ""
    @Published private(set) var isActive = false
    @Published private(set) var usingAdapter = false
    @Published private(set) var rate: Double = 1

    private var elapsedAtUpdate: Double = 0
    private var updatedAt = Date()
    private var process: Process?
    private var buffer = Data()
    private var pollTimer: Timer?
    private var idleTask: Task<Void, Never>?
    private var lastArtworkHash = 0
    private let prefs = Preferences.shared

    var elapsed: Double {
        guard isPlaying else { return elapsedAtUpdate }
        return min(duration > 0 ? duration : .infinity, elapsedAtUpdate + Date().timeIntervalSince(updatedAt) * rate)
    }

    var sourceName: String {
        guard !bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return "" }
        return FileManager.default.displayName(atPath: url.path)
    }

    var sourceIcon: NSImage? {
        guard !bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private init() {}

    // MARK: Lifecycle

    func start() {
        if let paths = adapterPaths(), adapterWorks(paths) {
            usingAdapter = true
            startStream(paths)
        } else {
            usingAdapter = false
            Log.music.warning("MediaRemote adapter unavailable, using AppleScript polling")
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pollAppleScript() }
            }
            pollAppleScript()
        }
    }

    func shutdown() {
        process?.terminate()
        process = nil
        pollTimer?.invalidate()
    }

    private func adapterPaths() -> (script: String, framework: String)? {
        guard let script = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let fw = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: fw) else { return nil }
        return (script, fw)
    }

    private func adapterWorks(_ p: (script: String, framework: String)) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [p.script, p.framework, "get"]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    private func startStream(_ p: (script: String, framework: String)) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [p.script, p.framework, "stream", "--debounce=80"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data) }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.process != nil else { return }
                Log.music.error("adapter stream exited; restarting in 3s")
                try? await Task.sleep(for: .seconds(3))
                if let paths = self.adapterPaths() { self.startStream(paths) }
            }
        }
        do { try proc.run(); process = proc } catch { Log.music.error("adapter launch failed: \(error.localizedDescription)") }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            apply(update: obj)
        }
    }

    // MARK: Adapter payload

    private func apply(update: [String: Any]) {
        let diff = update["diff"] as? Bool ?? false
        guard let payload = update["payload"] as? [String: Any] else {
            if !diff { clearTrack() }
            return
        }
        if !diff && payload.isEmpty { clearTrack(); return }

        func str(_ k: String) -> String?? {
            if let v = payload[k] { return v is NSNull ? .some(nil) : .some(v as? String) }
            return nil
        }
        if let v = str("title") { title = v ?? "" }
        if let v = str("artist") { artist = v ?? "" }
        if let v = str("album") { album = v ?? "" }
        if let v = str("bundleIdentifier") { bundleIdentifier = v ?? "" }
        if let v = payload["duration"] { duration = (v as? Double) ?? 0 }
        if let v = payload["playbackRate"] as? Double { rate = v == 0 ? 1 : v }
        if var v = payload["playing"] as? Bool {
            // Some browsers report a positive rate with a stale "paused" flag; trust the rate.
            if !v, let r = payload["playbackRate"] as? Double, r > 0, (payload["elapsedTime"] as? Double).map({ $0 > 0 }) ?? false { v = true }
            if v != isPlaying && !v { elapsedAtUpdate = elapsed }
            isPlaying = v
            updatedAt = Date()
        }
        if let v = payload["elapsedTime"] as? Double {
            elapsedAtUpdate = v
            updatedAt = Date()
            if let ts = payload["timestamp"] as? String, let d = ISO8601DateFormatter.flexible.date(from: ts) {
                updatedAt = d
            }
        }
        if let v = payload["artworkData"] {
            if let s = v as? String, let data = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                setArtwork(data)
            } else if v is NSNull { artwork = nil; accentColor = nil; lastArtworkHash = 0 }
        }
        if !diff && payload["artworkData"] == nil { artwork = nil; accentColor = nil; lastArtworkHash = 0 }
        if title.isEmpty && !isPlaying { isActive = false } else { refreshActive() }
    }

    private func setArtwork(_ data: Data) {
        let h = data.hashValue
        guard h != lastArtworkHash, let img = NSImage(data: data) else { return }
        lastArtworkHash = h
        let small = img.resized(maxDimension: 320)
        artwork = small
        if let avg = small.averageColor { accentColor = Color(nsColor: avg) }
    }

    private func clearTrack() {
        title = ""; artist = ""; album = ""; duration = 0; elapsedAtUpdate = 0
        isPlaying = false; artwork = nil; accentColor = nil; lastArtworkHash = 0
        isActive = false
    }

    private func refreshActive() {
        idleTask?.cancel()
        if isPlaying {
            isActive = true
        } else if !title.isEmpty {
            isActive = true
            guard prefs.hideMusicWhenPaused else { return }
            idleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, !self.isPlaying else { return }
                withAnimation { self.isActive = false }
            }
        } else { isActive = false }
    }

    // MARK: Controls

    func togglePlayPause() { command(2) }
    func play() { command(0) }
    func pause() { command(1) }
    func next() { command(4) }
    func previous() { command(5) }
    func skip(seconds: Double) { seek(to: max(0, min(duration, elapsed + seconds))) }

    func seek(to seconds: Double) {
        elapsedAtUpdate = seconds; updatedAt = Date()
        if usingAdapter, let p = adapterPaths() {
            runAdapter(p, ["seek", String(Int(seconds * 1_000_000))])
        } else {
            script("set player position to \(seconds)")
        }
    }

    private func command(_ id: Int) {
        if usingAdapter, let p = adapterPaths() {
            runAdapter(p, ["send", String(id)])
        } else {
            switch id {
            case 2: script("playpause")
            case 0: script("play")
            case 1: script("pause")
            case 4: script("next track")
            case 5: script("previous track")
            default: break
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pollAppleScript() }
        }
    }

    private func runAdapter(_ p: (script: String, framework: String), _ args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [p.script, p.framework] + args
        proc.standardOutput = FileHandle.nullDevice; proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    // MARK: AppleScript fallback

    private var fallbackApp: String? {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil { return "Spotify" }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first != nil { return "Music" }
        return nil
    }

    private func script(_ body: String) {
        guard let app = fallbackApp else { return }
        Task.detached { _ = AppleScriptRunner.run("tell application \"\(app)\" to \(body)") }
    }

    private func pollAppleScript() {
        guard let app = fallbackApp else { if isActive { clearTrack() }; return }
        let src = """
        tell application "\(app)"
            if player state is stopped then return "stopped"
            set s to player state as string
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            return s & "\n" & t & "\n" & a & "\n" & al & "\n" & d & "\n" & p
        end tell
        """
        Task.detached { [weak self] in
            guard let out = AppleScriptRunner.run(src) else { return }
            await MainActor.run { self?.applyAppleScript(out, app: app) }
        }
    }

    private func applyAppleScript(_ out: String, app: String) {
        let parts = out.components(separatedBy: "\n")
        guard parts.count >= 6 else { if out == "stopped" { clearTrack() }; return }
        bundleIdentifier = app == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        isPlaying = parts[0] == "playing"
        let changed = title != parts[1] || artist != parts[2]
        title = parts[1]; artist = parts[2]; album = parts[3]
        let d = Double(parts[4]) ?? 0
        duration = app == "Spotify" ? d / 1000 : d
        elapsedAtUpdate = Double(parts[5]) ?? 0
        updatedAt = Date()
        refreshActive()
        if changed { fetchFallbackArtwork(app: app) }
    }

    private func fetchFallbackArtwork(app: String) {
        if app == "Spotify" {
            Task.detached { [weak self] in
                guard let urlStr = AppleScriptRunner.run("tell application \"Spotify\" to return artwork url of current track"),
                      let url = URL(string: urlStr), let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                await MainActor.run { self?.setArtwork(data) }
            }
        } else {
            Task.detached { [weak self] in
                let s = "tell application \"Music\" to return raw data of artwork 1 of current track"
                guard let data = AppleScriptRunner.runData(s) else { return }
                await MainActor.run { self?.setArtwork(data) }
            }
        }
    }
}

enum AppleScriptRunner {
    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
    static func runData(_ source: String) -> Data? {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }
        return result.data
    }
}

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
