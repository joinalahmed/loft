import SwiftUI

struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let keywords: String
    let run: @MainActor () -> Void
}

struct CommandPaletteView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var actions: [PaletteAction] {
        let prefs = Preferences.shared
        var list: [PaletteAction] = prefs.enabledTabs.map { tab in
            PaletteAction(title: "Go to \(tab.title)", symbol: tab.symbol, keywords: "tab \(tab.rawValue)") { vm.tab = tab }
        }
        list += [
            PaletteAction(title: MusicManager.shared.isPlaying ? "Pause" : "Play", symbol: "playpause.fill", keywords: "music") { MusicManager.shared.togglePlayPause() },
            PaletteAction(title: "Next track", symbol: "forward.fill", keywords: "music skip") { MusicManager.shared.next() },
            PaletteAction(title: "Previous track", symbol: "backward.fill", keywords: "music") { MusicManager.shared.previous() },
            PaletteAction(title: "Start focus session", symbol: "brain.head.profile", keywords: "pomodoro timer") { TimerManager.shared.startPomodoro(); vm.tab = .timer },
            PaletteAction(title: "Start 10 minute timer", symbol: "timer", keywords: "countdown") { TimerManager.shared.startCountdown(minutes: 10); vm.tab = .timer },
            PaletteAction(title: "Start stopwatch", symbol: "stopwatch", keywords: "timer") { TimerManager.shared.startStopwatch(); vm.tab = .timer },
            PaletteAction(title: "Stop timer", symbol: "stop.fill", keywords: "timer") { TimerManager.shared.stop() },
            PaletteAction(title: KeepAwakeManager.shared.isActive ? "Let Mac sleep" : "Keep Mac awake", symbol: "cup.and.saucer.fill", keywords: "caffeine awake") { KeepAwakeManager.shared.toggle() },
            PaletteAction(title: "Keep awake for 30 minutes", symbol: "cup.and.saucer", keywords: "caffeine awake") { KeepAwakeManager.shared.acquire(minutes: 30) },
            PaletteAction(title: "Keep awake for 1 hour", symbol: "cup.and.saucer", keywords: "caffeine awake") { KeepAwakeManager.shared.acquire(minutes: 60) },
            PaletteAction(title: "Keep awake for 2 hours", symbol: "cup.and.saucer", keywords: "caffeine awake") { KeepAwakeManager.shared.acquire(minutes: 120) },
            PaletteAction(title: AudioDeviceManager.shared.micMuted ? "Unmute microphone" : "Mute microphone", symbol: "mic.slash.fill", keywords: "mic audio call") { AudioDeviceManager.shared.toggleMicMute() },
            PaletteAction(title: "Open terminal", symbol: "terminal.fill", keywords: "shell zsh command") { vm.tab = .terminal; vm.userInteracted() },
            PaletteAction(title: "Pick a colour from the screen", symbol: "eyedropper.halffull", keywords: "color picker hex") { ToolsManager.shared.pickColor() },
            PaletteAction(title: "Copy text from screen (OCR)", symbol: "text.viewfinder", keywords: "ocr recognize capture") { ToolsManager.shared.captureText() },
            PaletteAction(title: "Eject all external drives", symbol: "eject.fill", keywords: "disk volume usb") { SystemStats.shared.ejectAll() },
            PaletteAction(title: "Screenshot: region", symbol: "camera.viewfinder", keywords: "capture screen") { ScreenshotManager.shared.capture(.region) },
            PaletteAction(title: "Screenshot: window", symbol: "macwindow", keywords: "capture screen") { ScreenshotManager.shared.capture(.window) },
            PaletteAction(title: "Screenshot: full screen", symbol: "rectangle.dashed", keywords: "capture screen") { ScreenshotManager.shared.capture(.full) },
            PaletteAction(title: "Join next meeting", symbol: "video.fill", keywords: "calendar zoom meet teams") {
                if let url = CalendarManager.shared.nextEvent?.joinURL { NSWorkspace.shared.open(url) } else { vm.tab = .calendar }
            },
            PaletteAction(title: "Preview meeting alert", symbol: "bell.badge", keywords: "calendar test") { CalendarManager.shared.testAlert() },
            PaletteAction(title: "Clear clipboard history", symbol: "trash", keywords: "clipboard") { ClipboardManager.shared.clear() },
            PaletteAction(title: "Clear shelf", symbol: "tray", keywords: "shelf files") { ShelfManager.shared.clear() },
            PaletteAction(title: "Toggle clock in pill", symbol: "clock", keywords: "time") { prefs.showClockInPill.toggle() },
            PaletteAction(title: "Hide Loft", symbol: "eye.slash", keywords: "hide") { vm.isHidden = true },
            PaletteAction(title: "Settings…", symbol: "gearshape", keywords: "preferences") { SettingsWindowController.shared.show() },
            PaletteAction(title: "Lock screen", symbol: "lock.fill", keywords: "lock sleep away") { LockScreenManager.shared.lock() },
            PaletteAction(title: "Empty Trash", symbol: "trash.slash", keywords: "finder") { _ = AppleScriptRunner.run("tell application \"Finder\" to empty trash") },
            PaletteAction(title: "Quit Loft", symbol: "power", keywords: "exit") { NSApp.terminate(nil) },
        ]
        return list
    }

    private var filtered: [PaletteAction] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return actions }
        var list = actions.filter { fuzzy($0.title.lowercased(), q) || $0.keywords.contains(q) }
        let raw = query.trimmingCharacters(in: .whitespaces)
        if let result = ToolsManager.evaluateMath(raw) {
            list.insert(PaletteAction(title: "= \(result)", symbol: "equal.circle.fill", keywords: "") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string)
                NotchViewModel.shared.show(message: IslandMessage(title: result, subtitle: "Copied", symbol: "equal.circle.fill"), duration: 1.5)
            }, at: 0)
        }
        if let url = ToolsManager.searchURL(raw) {
            list.append(PaletteAction(title: "Search the web for “\(raw)”", symbol: "magnifyingglass", keywords: "") { NSWorkspace.shared.open(url) })
        }
        if raw.contains("."), !raw.contains(" "), let url = URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)"), url.host != nil {
            list.insert(PaletteAction(title: "Open \(url.host ?? raw)", symbol: "safari", keywords: "") { NSWorkspace.shared.open(url) }, at: 0)
        }
        return list
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Type a command…", text: $query).textFieldStyle(.plain).font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { runSelected() }
                    .onChange(of: query) { _, _ in selection = 0 }
                Text("esc").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, a in
                            HStack(spacing: 10) {
                                Image(systemName: a.symbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                                Text(a.title).font(.system(size: 12, weight: i == selection ? .semibold : .regular))
                                Spacer()
                                if i == selection { Text("↩").font(.system(size: 10)).foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(i == selection ? .white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                            .onTapGesture { selection = i; runSelected() }
                            .onHover { if $0 { selection = i } }
                            .id(i)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: selection) { _, s in withAnimation(nil) { proxy.scrollTo(s) } }
            }
        }
        .padding(8)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { selection = min(filtered.count - 1, selection + 1); return .handled }
        .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
    }

    private func runSelected() {
        guard filtered.indices.contains(selection) else { return }
        let a = filtered[selection]
        vm.paletteVisible = false
        query = ""
        a.run()
    }

    private func fuzzy(_ s: String, _ q: String) -> Bool {
        var it = s.makeIterator()
        for ch in q { var found = false; while let c = it.next() { if c == ch { found = true; break } }; if !found { return false } }
        return true
    }
}
