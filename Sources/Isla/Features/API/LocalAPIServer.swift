import Foundation
import Network
import SwiftUI
import AppKit

/// Newline-delimited JSON over TCP on 127.0.0.1. Every request carries the token.
///   echo '{"token":"…","command":"status"}' | nc 127.0.0.1 9999
///   echo '{"token":"…","title":"Build","subtitle":"Done","progress":1}' | nc 127.0.0.1 9999
@MainActor
final class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var port: UInt16 = 0
    private init() {}

    func applyPreferences() {
        let prefs = Preferences.shared
        if prefs.localAPIEnabled {
            if !isRunning || port != UInt16(prefs.localAPIPort) { stop(); start(port: UInt16(prefs.localAPIPort)) }
        } else { stop() }
    }

    func start(port: UInt16) {
        guard let p = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: p)
        params.allowLocalEndpointReuse = true
        do {
            let l = try NWListener(using: params)
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.isRunning = true; self?.lastError = nil
                    case .failed(let e): self?.isRunning = false; self?.lastError = e.localizedDescription
                    case .cancelled: self?.isRunning = false
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in Task { @MainActor in self?.accept(conn) } }
            l.start(queue: .main)
            listener = l; self.port = port
        } catch { lastError = error.localizedDescription }
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        isRunning = false
    }

    private func accept(_ conn: NWConnection) {
        connections[ObjectIdentifier(conn)] = conn
        conn.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { Task { @MainActor in self?.connections[ObjectIdentifier(conn)] = nil } }
            if case .failed = state { Task { @MainActor in self?.connections[ObjectIdentifier(conn)] = nil } }
        }
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = buf[buf.startIndex..<nl]; buf.removeSubrange(buf.startIndex...nl)
                    if !line.isEmpty { self.respond(conn, self.handle(Data(line))) }
                }
                if complete || error != nil {
                    if !buf.isEmpty { self.respond(conn, self.handle(buf)) }
                    conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
                } else { self.receive(conn, buffer: buf) }
            }
        }
    }

    private func respond(_ conn: NWConnection, _ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: Commands

    private func handle(_ data: Data) -> [String: Any] {
        guard let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ["ok": false, "error": "invalid json"] }
        guard req["token"] as? String == Preferences.shared.localAPIToken else { return ["ok": false, "error": "bad token"] }
        let vm = NotchViewModel.shared
        let music = MusicManager.shared
        let command = req["command"] as? String
        if command == nil, let title = req["title"] as? String {
            let dur = min(10, max(1, req["duration"] as? Double ?? 4))
            vm.show(message: IslandMessage(title: String(title.prefix(120)), subtitle: (req["subtitle"] as? String).map { String($0.prefix(500)) },
                                           symbol: req["symbol"] as? String, progress: req["progress"] as? Double), duration: dur)
            return ["ok": true]
        }
        switch command {
        case "status":
            return ["ok": true, "state": vm.state == .open ? "open" : "closed", "tab": vm.tab.rawValue, "hidden": vm.isHidden,
                    "hasKeyboardFocus": NSApp.keyWindow is NotchWindow,
                    "music": ["playing": music.isPlaying, "title": music.title, "artist": music.artist, "album": music.album,
                              "elapsed": music.elapsed, "duration": music.duration, "source": music.bundleIdentifier],
                    "timer": ["mode": TimerManager.shared.mode.rawValue, "running": TimerManager.shared.isRunning, "remaining": TimerManager.shared.remaining],
                    "battery": ["level": BatteryMonitor.shared.level, "charging": BatteryMonitor.shared.isCharging],
                    "keepAwake": KeepAwakeManager.shared.isActive,
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"]
        case "open": vm.open(tab: PanelTab(rawValue: req["tab"] as? String ?? ""), focus: req["focus"] as? Bool ?? false); return ["ok": true]
        case "close": vm.close(); return ["ok": true]
        case "toggle": vm.toggle(); return ["ok": true]
        case "hide": vm.isHidden = true; return ["ok": true]
        case "show": vm.isHidden = false; return ["ok": true]
        case "music":
            switch req["action"] as? String {
            case "play": music.play()
            case "pause": music.pause()
            case "toggle": music.togglePlayPause()
            case "next": music.next()
            case "previous": music.previous()
            case "seek": if let s = req["seconds"] as? Double { music.seek(to: s) }
            default: return ["ok": false, "error": "unknown music action"]
            }
            return ["ok": true]
        case "timer":
            switch req["action"] as? String {
            case "countdown": TimerManager.shared.startCountdown(minutes: Int(req["minutes"] as? Double ?? 10))
            case "pomodoro": TimerManager.shared.startPomodoro()
            case "stopwatch": TimerManager.shared.startStopwatch()
            case "pause": TimerManager.shared.pause()
            case "resume": TimerManager.shared.resume()
            case "stop": TimerManager.shared.stop()
            default: return ["ok": false, "error": "unknown timer action"]
            }
            return ["ok": true]
        case "keepawake":
            let minutes = Int(req["minutes"] as? Double ?? 0)
            if let on = req["on"] as? Bool { on ? KeepAwakeManager.shared.acquire(minutes: minutes) : KeepAwakeManager.shared.release() }
            else if minutes > 0 { KeepAwakeManager.shared.acquire(minutes: minutes) } else { KeepAwakeManager.shared.toggle() }
            return ["ok": true, "active": KeepAwakeManager.shared.isActive, "status": KeepAwakeManager.shared.statusText]
        case "screenshot":
            let mode = ScreenshotManager.Mode(rawValue: req["mode"] as? String ?? "region") ?? .region
            ScreenshotManager.shared.capture(mode)
            return ["ok": true]
        case "meeting":
            switch req["action"] as? String {
            case "test": CalendarManager.shared.testAlert()
            case "dismiss": MeetingAlertController.shared.dismiss()
            case "join": MeetingAlertController.shared.join()
            default:
                if let ev = CalendarManager.shared.nextEvent {
                    return ["ok": true, "title": ev.title ?? "", "start": ISO8601DateFormatter().string(from: ev.startDate), "join": CalendarManager.joinURL(for: ev)?.absoluteString ?? ""]
                }
                return ["ok": true, "title": ""]
            }
            return ["ok": true]
        case "clipboard":
            let n = Int(req["limit"] as? Double ?? 10)
            return ["ok": true, "items": ClipboardManager.shared.items.prefix(n).map { ["kind": $0.kind.rawValue, "text": $0.kind == .image ? "" : $0.text, "date": ISO8601DateFormatter().string(from: $0.date), "pinned": $0.pinned] }]
        case "shelf":
            if let path = req["add"] as? String, FileManager.default.fileExists(atPath: path) { ShelfManager.shared.add(URL(fileURLWithPath: path)) }
            return ["ok": true, "items": ShelfManager.shared.items.map(\.url.path)]
        case "volume":
            if let v = req["value"] as? Double { VolumeMonitor.shared.setVolume(Float(v)); vm.show(.volume(v, muted: v == 0)) }
            return ["ok": true, "value": VolumeMonitor.shared.volume, "muted": VolumeMonitor.shared.muted]
        case "brightness":
            if let v = req["value"] as? Double { BrightnessMonitor.shared.set(Float(v)) }
            return ["ok": true, "value": BrightnessMonitor.shared.current ?? -1]
        case "snapshot":
            // Developer aid: render the island view to a PNG (no screen-recording permission needed).
            let wantSettings = req["window"] as? String == "settings"
            let wantMeeting = req["window"] as? String == "meeting"
            guard let path = req["path"] as? String,
                  let window = NSApp.windows.first(where: { wantSettings ? $0.identifier?.rawValue == "isla.settings" : wantMeeting ? ($0.contentView is NSHostingView<MeetingAlertView>) : $0 is NotchWindow }), let view = window.contentView else {
                return ["ok": false, "error": "no window"]
            }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return ["ok": false, "error": "no rep"] }
            view.cacheDisplay(in: view.bounds, to: rep)
            let composed = NSImage(size: view.bounds.size)
            composed.lockFocus()
            NSColor(calibratedWhite: 0.82, alpha: 1).setFill(); view.bounds.fill()
            rep.draw(in: view.bounds)
            composed.unlockFocus()
            guard let tiff = composed.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return ["ok": false] }
            try? png.write(to: URL(fileURLWithPath: path))
            return ["ok": true, "path": path, "width": view.bounds.width, "height": view.bounds.height]
        case "settings":
            if req["close"] as? Bool == true { SettingsWindowController.shared.close() }
            else { SettingsWindowController.shared.show(tab: SettingsTab(rawValue: req["tab"] as? String ?? "")) }
            return ["ok": true]
        case "debug":
            let settings = NSApp.windows.first { $0.identifier?.rawValue == "isla.settings" }
            var hit = "none"
            if let s = settings, let cv = s.contentView {
                let pt = CGPoint(x: cv.bounds.midX + 100, y: cv.bounds.midY)
                hit = String(describing: type(of: cv.hitTest(pt) as Any))
            }
            return ["ok": true, "appActive": NSApp.isActive, "keyWindow": NSApp.keyWindow?.identifier?.rawValue ?? String(describing: NSApp.keyWindow.map { type(of: $0) }),
                    "notchFrame": NSStringFromRect(NSApp.windows.first { $0 is NotchWindow }?.frame ?? .zero),
                    "settingsVisible": settings?.isVisible ?? false, "settingsKey": settings?.isKeyWindow ?? false,
                    "settingsFrame": settings.map { NSStringFromRect($0.frame) } ?? "", "settingsHit": hit,
                    "windows": NSApp.windows.map { "\(type(of: $0)) lvl=\($0.level.rawValue) vis=\($0.isVisible)" }]
        case "tab":
            if let t = PanelTab(rawValue: req["name"] as? String ?? "") { vm.tab = t }
            return ["ok": true, "tab": vm.tab.rawValue]
        case "hud":
            switch req["kind"] as? String {
            case "volume": vm.show(.volume(req["value"] as? Double ?? 0.5, muted: false))
            case "brightness": vm.show(.brightness(req["value"] as? Double ?? 0.5))
            case "caps": vm.show(.capsLock(true))
            case "battery": vm.show(.battery(level: 83, charging: true, pluggedIn: true, low: false), duration: 3)
            default: break
            }
            return ["ok": true]
        default:
            return ["ok": false, "error": "unknown command", "commands": ["status", "open", "close", "toggle", "hide", "show", "tab", "music", "timer", "keepawake", "screenshot", "meeting", "clipboard", "shelf", "volume", "brightness", "settings", "snapshot", "(no command + title → message)"]]
        }
    }
}
