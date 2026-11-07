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
        // The header shares its row with the hardware notch, so nothing may be drawn under it:
        // tabs flow left of the notch, continue right of it, and the tools sit at the far right.
        GeometryReader { geo in
            let gap = vm.metrics.hasNotch ? vm.notchWidth + 12 : 0
            let toolCount = 1 + (prefs.headerPalette ? 1 : 0) + (prefs.headerScreenshot ? 1 : 0) + (prefs.headerKeepAwake ? 1 : 0)
            let toolsWidth: CGFloat = CGFloat(toolCount) * 24 + 6 + 8
            let leftWidth = max(60, (geo.size.width - gap) / 2 - 4)
            let rightWidth = max(0, geo.size.width - leftWidth - gap - toolsWidth - 8)
            let parts = layout(leftWidth: leftWidth, rightWidth: rightWidth)
            HStack(spacing: 0) {
                strip(parts.left, more: parts.right.isEmpty && !parts.overflow.isEmpty ? parts.overflow : [], label: parts.label)
                    .frame(width: leftWidth, alignment: .leading)
                Spacer(minLength: gap)
                if !parts.right.isEmpty {
                    strip(parts.right, more: parts.overflow, label: parts.label)
                        .frame(width: rightWidth, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                tools.frame(width: toolsWidth, alignment: .trailing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 2)
        .frame(height: vm.closedHeight)
    }

    private var tools: some View {
            HStack(spacing: 2) {
                if prefs.headerPalette {
                    HeaderIcon(symbol: "command", help: "Command palette (⌘K)") { vm.userInteracted(); vm.paletteVisible.toggle() }
                }
                if prefs.headerScreenshot {
                HeaderIcon(symbol: "camera.viewfinder", help: "Capture region (⌃⌥⇧4)") { ScreenshotManager.shared.capture(.region) }
                    .contextMenu {
                        Button("Capture Region") { ScreenshotManager.shared.capture(.region) }
                        Button("Capture Window") { ScreenshotManager.shared.capture(.window) }
                        Button("Capture Full Screen") { ScreenshotManager.shared.capture(.full) }
                        Divider()
                        Button("Copy Text from Screen (OCR)") { ToolsManager.shared.captureText() }
                        Button("Pick a Colour") { ToolsManager.shared.pickColor() }
                    }
                }
                if prefs.headerKeepAwake {
                HeaderIcon(symbol: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                           help: "Keep awake: \(keepAwake.statusText) · right-click for durations",
                           active: keepAwake.isActive) { keepAwake.toggle() }
                    .contextMenu {
                        ForEach(KeepAwakeManager.durations, id: \.minutes) { d in
                            Button(d.title) { keepAwake.acquire(minutes: d.minutes) }
                        }
                        if keepAwake.isActive { Divider(); Button("Turn Off") { keepAwake.release() } }
                    }
                }
                HeaderIcon(symbol: "gearshape.fill", help: "Settings") { SettingsWindowController.shared.show() }
            }
            .padding(.horizontal, 3)
            .background(.white.opacity(0.06), in: Capsule())
            .fixedSize()
    }

    // Width estimates (pt) for the fitting pass; cheaper and steadier than measuring.
    private func width(of tab: PanelTab, selected: Bool) -> CGFloat {
        selected ? 36 + CGFloat(tab.title.count) * 6.6 : 28
    }

    /// Distributes tabs over the two areas beside the notch. The selected tab is always visible
    /// (with its label when there is room), everything that does not fit goes into a menu.
    private func layout(leftWidth: CGFloat, rightWidth: CGFloat) -> (left: [PanelTab], right: [PanelTab], overflow: [PanelTab], label: Bool) {
        let all = prefs.enabledTabs
        let selected = all.contains(vm.tab) ? vm.tab : .home
        func fit(label: Bool) -> ([PanelTab], [PanelTab], [PanelTab]) {
            var remaining = all
            var left: [PanelTab] = [], right: [PanelTab] = []
            // Selected first so it is never pushed out.
            var leftBudget = leftWidth - 8, rightBudget = rightWidth > 40 ? rightWidth - 8 : 0
            var usedLeft = false
            for tab in [selected] + remaining.filter({ $0 != selected }) {
                let w = width(of: tab, selected: label && tab == selected) + 2
                if w <= leftBudget - (usedLeft ? 0 : 0) { left.append(tab); leftBudget -= w }
                else if w <= rightBudget { right.append(tab); rightBudget -= w }
                else { break }
                usedLeft = true
                remaining.removeAll { $0 == tab }
            }
            var overflow = all.filter { !left.contains($0) && !right.contains($0) }
            // Make room for the "more" button where it will be drawn.
            if !overflow.isEmpty {
                if right.isEmpty {
                    while leftBudget < 30, left.count > 1 { let t = left.removeLast(); overflow.insert(t, at: 0); leftBudget += width(of: t, selected: false) + 2 }
                } else {
                    while rightBudget < 30, right.count > 0 { let t = right.removeLast(); overflow.insert(t, at: 0); rightBudget += width(of: t, selected: false) + 2 }
                }
            }
            // Restore the user's order inside each segment.
            left = all.filter { left.contains($0) }; right = all.filter { right.contains($0) }
            overflow = all.filter { !left.contains($0) && !right.contains($0) }
            return (left, right, overflow)
        }
        var label = true
        var (left, right, overflow) = fit(label: true)
        if left.count + right.count < min(5, all.count) { label = false; (left, right, overflow) = fit(label: false) }
        return (left, right, overflow, label)
    }

    @ViewBuilder private func strip(_ tabs: [PanelTab], more: [PanelTab], label: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                TabButton(tab: tab, selected: vm.tab == tab, showLabel: label, tint: tint) {
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
                    Button("Choose Tabs…") { SettingsWindowController.shared.show(tab: .tools) }
                }
            }
            if !more.isEmpty {
                Menu {
                    ForEach(more) { tab in
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
        .animation(.smooth(duration: 0.25), value: tabs)
    }
}

struct TabButton: View {
    let tab: PanelTab
    let selected: Bool
    var showLabel = true
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                if selected && showLabel {
                    Text(tab.title).font(.system(size: 11, weight: .semibold)).fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(selected ? .black : (hover ? .white : .white.opacity(0.65)))
            .padding(.horizontal, selected && showLabel ? 10 : 8).frame(height: 22)
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
