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
            PaletteAction(title: "Clear clipboard history", symbol: "trash", keywords: "clipboard") { ClipboardManager.shared.clear() },
            PaletteAction(title: "Clear shelf", symbol: "tray", keywords: "shelf files") { ShelfManager.shared.clear() },
            PaletteAction(title: "Toggle clock in pill", symbol: "clock", keywords: "time") { prefs.showClockInPill.toggle() },
            PaletteAction(title: "Hide Isla", symbol: "eye.slash", keywords: "hide") { vm.isHidden = true },
            PaletteAction(title: "Settings…", symbol: "gearshape", keywords: "preferences") { SettingsWindowController.shared.show() },
            PaletteAction(title: "Lock screen", symbol: "lock.fill", keywords: "lock") { lockScreen() },
            PaletteAction(title: "Empty Trash", symbol: "trash.slash", keywords: "finder") { _ = AppleScriptRunner.run("tell application \"Finder\" to empty trash") },
            PaletteAction(title: "Quit Isla", symbol: "power", keywords: "exit") { NSApp.terminate(nil) },
        ]
        return list
    }

    private var filtered: [PaletteAction] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return actions }
        return actions.filter { fuzzy($0.title.lowercased(), q) || $0.keywords.contains(q) }
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

    private func lockScreen() {
        // Same as ⌃⌘Q.
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: false)
        down?.flags = [.maskCommand, .maskControl]; up?.flags = [.maskCommand, .maskControl]
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
}
