import SwiftUI

/// Tab strip shown in the top row while the panel is open. Adaptive: fits as many tabs as the
/// width allows, always keeps the selected tab with its full label, and folds the rest into a
/// "more" menu. Right-click a tab to move or hide it.
struct PanelHeaderView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var keepAwake = KeepAwakeManager.shared
    @Environment(\.islandTint) private var tint

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                tabStrip(fitting: geo.size.width)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            HStack(spacing: 2) {
                HeaderIcon(symbol: "command", help: "Command palette (⌘K)") { vm.userInteracted(); vm.paletteVisible.toggle() }
                HeaderIcon(symbol: "camera.viewfinder", help: "Capture region (⌃⌥⇧4)") { ScreenshotManager.shared.capture(.region) }
                    .contextMenu {
                        Button("Capture Region") { ScreenshotManager.shared.capture(.region) }
                        Button("Capture Window") { ScreenshotManager.shared.capture(.window) }
                        Button("Capture Full Screen") { ScreenshotManager.shared.capture(.full) }
                        Divider()
                        Button("Copy Text from Screen (OCR)") { ToolsManager.shared.captureText() }
                        Button("Pick a Colour") { ToolsManager.shared.pickColor() }
                    }
                HeaderIcon(symbol: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                           help: "Keep awake: \(keepAwake.statusText) · right-click for durations",
                           active: keepAwake.isActive) { keepAwake.toggle() }
                    .contextMenu {
                        ForEach(KeepAwakeManager.durations, id: \.minutes) { d in
                            Button(d.title) { keepAwake.acquire(minutes: d.minutes) }
                        }
                        if keepAwake.isActive { Divider(); Button("Turn Off") { keepAwake.release() } }
                    }
                HeaderIcon(symbol: "gearshape.fill", help: "Settings") { SettingsWindowController.shared.show() }
            }
            .padding(.horizontal, 3)
            .background(.white.opacity(0.06), in: Capsule())
            .fixedSize()
        }
        .padding(.horizontal, 2)
        .frame(height: vm.closedHeight)
    }

    // Width estimates (pt) for the fitting pass; cheaper and steadier than measuring.
    private func width(of tab: PanelTab, selected: Bool) -> CGFloat {
        selected ? 36 + CGFloat(tab.title.count) * 6.6 : 28
    }

    private func visibleTabs(fitting available: CGFloat) -> (shown: [PanelTab], overflow: [PanelTab]) {
        let all = prefs.enabledTabs
        let selected = all.contains(vm.tab) ? vm.tab : .home
        var budget = available - 8                                   // strip padding
        var shown: [PanelTab] = []
        let total = all.reduce(0) { $0 + width(of: $1, selected: $1 == selected) + 2 }
        let needsMore = total > budget
        if needsMore { budget -= 30 }                                // room for the "more" button
        budget -= width(of: selected, selected: true) + 2            // selected tab is always shown
        for tab in all where tab != selected {
            let w = width(of: tab, selected: false) + 2
            if w <= budget { shown.append(tab); budget -= w } else { break }
        }
        // Keep the user's order with the selected tab in its own slot.
        var ordered = all.filter { shown.contains($0) || $0 == selected }
        if !ordered.contains(selected) { ordered.append(selected) }
        let overflow = all.filter { !ordered.contains($0) }
        return (ordered, overflow)
    }

    @ViewBuilder private func tabStrip(fitting available: CGFloat) -> some View {
        let parts = visibleTabs(fitting: available)
        HStack(spacing: 2) {
            ForEach(parts.shown) { tab in
                TabButton(tab: tab, selected: vm.tab == tab, tint: tint) {
                    withAnimation(.smooth(duration: 0.25)) { vm.tab = tab }
                }
                .contextMenu {
                    Button("Move Left") { prefs.move(tab, by: -1) }.disabled(prefs.enabledTabs.first == tab)
                    Button("Move Right") { prefs.move(tab, by: 1) }.disabled(prefs.enabledTabs.last == tab)
                    if tab != .home {
                        Divider()
                        Button("Hide \(tab.title)") { if vm.tab == tab { vm.tab = .home }; prefs.setTab(tab, enabled: false) }
                    }
                    Divider()
                    Button("Choose Tabs…") { SettingsWindowController.shared.show(tab: .features) }
                }
            }
            if !parts.overflow.isEmpty {
                Menu {
                    ForEach(parts.overflow) { tab in
                        Button { withAnimation(.smooth(duration: 0.25)) { vm.tab = tab } } label: { Label(tab.title, systemImage: tab.symbol) }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7)).frame(width: 26, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26).help("More tabs")
            }
        }
        .padding(3)
        .background(.white.opacity(0.06), in: Capsule())
        .animation(.smooth(duration: 0.25), value: parts.shown)
    }
}

struct TabButton: View {
    let tab: PanelTab
    let selected: Bool
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                if selected {
                    Text(tab.title).font(.system(size: 11, weight: .semibold)).fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(selected ? .black : (hover ? .white : .white.opacity(0.65)))
            .padding(.horizontal, selected ? 10 : 8).frame(height: 22)
            .background {
                if selected { Capsule().fill(tint).shadow(color: tint.opacity(0.35), radius: 6, y: 1) }
                else if hover { Capsule().fill(.white.opacity(0.12)) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tab.title)
    }
}

struct HeaderIcon: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .yellow : (hover ? .white : .white.opacity(0.7)))
                .frame(width: 22, height: 22)
                .background(hover ? .white.opacity(0.12) : .clear, in: Circle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }.help(help)
    }
}

/// Body of the expanded panel. Switches on the selected tab.
struct PanelContentView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        ZStack {
            Group {
                switch vm.tab {
                case .home: HomeTabView()
                case .music: MusicTabView()
                case .shelf: ShelfTabView()
                case .clipboard: ClipboardTabView()
                case .timer: TimerTabView()
                case .calendar: CalendarTabView()
                case .reminders: RemindersTabView()
                case .notes: NotesTabView()
                case .terminal: TerminalTabView()
                case .launcher: LauncherTabView()
                case .stocks: StocksTabView()
                case .system: SystemTabView()
                case .mirror: MirrorTabView()
                case .weather: WeatherTabView()
                }
            }
            .id(vm.tab)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            if vm.paletteVisible {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(.smooth(duration: 0.22), value: vm.tab)
        .animation(.smooth(duration: 0.2), value: vm.paletteVisible)
        .onReceive(NotificationCenter.default.publisher(for: .islaClosePanel)) { _ in vm.paletteVisible = false }
    }
}

/// Reusable rounded card for panel content.
struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.055)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            }
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.white.opacity(0.06)).frame(width: 44, height: 44)
                Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            if let subtitle { Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 260) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SmallIconButton: View {
    let symbol: String
    var size: CGFloat = 12
    var help: String = ""
    var tint: Color = .white
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(hover ? tint : tint.opacity(0.75))
                .frame(width: size + 14, height: size + 14)
                .background(hover ? .white.opacity(0.12) : .clear, in: Circle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }.help(help)
    }
}
