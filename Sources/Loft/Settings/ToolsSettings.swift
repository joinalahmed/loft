import SwiftUI

/// One place to decide what Loft shows and does: panel tabs (drag to reorder), header buttons,
/// pill features and alerts, and every global shortcut. Off means the feature does not run.
struct ToolsSettings: View {
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var hotkeys = HotKeyManager.shared

    private struct ToolRow: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let binding: Binding<Bool>
    }

    var body: some View {
        SettingsSection(title: "Panel tabs", footer: "Drag to reorder. Home is always first. The strip shows what fits beside the notch; the rest goes into the ••• menu.") {
            List {
                ForEach(prefs.orderedTabs) { tab in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).font(.system(size: 11))
                        Image(systemName: tab.symbol).frame(width: 18).foregroundStyle(.secondary)
                        Text(tab.title)
                        Spacer()
                        if tab == .home {
                            Text("always on").font(.system(size: 10)).foregroundStyle(.tertiary)
                        } else {
                            Toggle("", isOn: Binding(get: { prefs.enabledTabs.contains(tab) }, set: { prefs.setTab(tab, enabled: $0) })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                    }
                    .padding(.vertical, 1)
                    .moveDisabled(tab == .home)
                }
                .onMove { from, to in
                    var order = prefs.orderedTabs
                    order.move(fromOffsets: from, toOffset: to)
                    if let i = order.firstIndex(of: .home), i != 0 { order.remove(at: i); order.insert(.home, at: 0) }
                    prefs.tabOrder = order.map(\.rawValue)
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: CGFloat(PanelTab.allCases.count) * 29 + 12)
        }

        SettingsSection(title: "Header buttons") {
            toolToggle("Command palette", "⌘K inside the panel, ⌃⌥K anywhere", "command", $prefs.headerPalette)
            toolToggle("Screenshot", "Region capture; right-click for window, full screen, OCR, colour picker", "camera.viewfinder", $prefs.headerScreenshot)
            toolToggle("Keep awake", "Toggle; right-click for durations", "cup.and.saucer", $prefs.headerKeepAwake)
            toolToggle("Lock screen", "One tap locks the Mac (also ⌃⌥Q, palette, menu bar)", "lock", $prefs.headerLock)
        }

        SettingsSection(title: "Lock screen", footer: "Widgets float a clock-side strip with Now Playing, the next meeting and battery above the lock screen. macOS only allows this on some versions; use Preview to check on yours.") {
            toolToggle("Pause music when the screen locks", "Resumes on unlock if enabled below", "pause.circle", $prefs.pauseMusicOnLock)
            toolToggle("Resume music on unlock", "Only what Loft paused", "play.circle", $prefs.resumeMusicOnUnlock)
            toolToggle("Turn keep-awake off when locking", "A locked Mac may sleep", "cup.and.saucer", $prefs.releaseKeepAwakeOnLock)
            toolToggle("Welcome-back island", "Time away and the next meeting after unlocking", "lock.open", $prefs.welcomeBackIsland)
            toolToggle("Lock-screen widgets (experimental)", "Now Playing, next meeting, battery above the lock screen", "lock.display", $prefs.lockScreenWidgets)
            HStack {
                Button("Preview widgets for 5 s") { LockScreenManager.shared.previewWidgets() }
                Button("Lock now") { LockScreenManager.shared.lock() }
            }.controlSize(.small)
        }

        SettingsSection(title: "Pill & alerts", footer: "Things Loft shows without opening the panel.") {
            toolToggle("Now Playing live activity", "Artwork and audio bars while music plays", "music.note", $prefs.musicLiveActivity)
            toolToggle("Volume / brightness HUD", "Replaces the macOS overlay", "speaker.wave.2", $prefs.hudEnabled)
            toolToggle("Caps Lock indicator", "Needs Accessibility", "capslock", $prefs.capsLockHUD)
            toolToggle("Battery islands", "Charger, low, critical, fully charged", "battery.75percent", $prefs.batteryAlerts)
            toolToggle("Meeting countdown & alerts", "Pill countdown and the full-screen pop-up", "video", $prefs.meetingAlertsEnabled)
            toolToggle("Timer alerts full screen", "When a timer or focus session ends", "timer", $prefs.timerFullScreenAlert)
            toolToggle("Reminder alerts", "When a reminder with a time is due", "checklist", $prefs.reminderAlerts)
            toolToggle("Mic / camera privacy dots", "Orange mic, green camera", "mic", $prefs.privacyIndicator)
            toolToggle("Call island", "Timer and mute button during calls", "phone", $prefs.callIsland)
            toolToggle("Download progress", "Watches ~/Downloads (asks for access)", "arrow.down.circle", $prefs.downloadsEnabled)
            toolToggle("Clock in the pill", "When nothing else is showing", "clock", $prefs.showClockInPill)
            toolToggle("Lyrics button", "Synced lyrics from LRCLIB in the Music tab", "quote.bubble", $prefs.lyricsEnabled)
        }

        SettingsSection(title: "Keyboard shortcuts", footer: "Disabled shortcuts are released immediately so other apps can use them.") {
            ForEach(hotkeys.bindings, id: \.id) { b in
                let parts = b.title.components(separatedBy: "  ")
                HStack(spacing: 10) {
                    Text(parts.first ?? "").font(.system(size: 12, weight: .semibold, design: .rounded)).frame(width: 80, alignment: .leading)
                        .padding(.horizontal, 6).frame(height: 22).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Text(parts.dropFirst().joined(separator: " ")).font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: Binding(get: { !prefs.disabledHotkeys.contains(Int(b.id)) },
                                            set: { on in
                                                var set = Set(prefs.disabledHotkeys)
                                                if on { set.remove(Int(b.id)) } else { set.insert(Int(b.id)) }
                                                prefs.disabledHotkeys = Array(set).sorted()
                                                hotkeys.applyPreferences()
                                            })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }
        }
    }

    @ViewBuilder private func toolToggle(_ title: String, _ detail: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: on).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}
