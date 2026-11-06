import SwiftUI

/// Tab strip shown in the top row while the panel is open.
struct PanelHeaderView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var keepAwake = KeepAwakeManager.shared
    @Environment(\.islandTint) private var tint

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(prefs.enabledTabs) { tab in
                    TabButton(tab: tab, selected: vm.tab == tab, tint: tint) {
                        withAnimation(.smooth(duration: 0.25)) { vm.tab = tab }
                    }
                }
            }
            Spacer(minLength: vm.notchWidth * 0.25)
            HStack(spacing: 10) {
                HeaderIcon(symbol: "command", help: "Command palette (⌘K)") { vm.userInteracted(); vm.paletteVisible.toggle() }
                HeaderIcon(symbol: "camera.viewfinder", help: "Capture region (⌃⌥⇧4)") { ScreenshotManager.shared.capture(.region) }
                    .contextMenu {
                        Button("Capture Region") { ScreenshotManager.shared.capture(.region) }
                        Button("Capture Window") { ScreenshotManager.shared.capture(.window) }
                        Button("Capture Full Screen") { ScreenshotManager.shared.capture(.full) }
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
        }
        .padding(.horizontal, 2)
        .frame(height: vm.closedHeight)
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
                if selected { Text(tab.title).font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(selected ? .black : (hover ? .white : .white.opacity(0.7)))
            .padding(.horizontal, selected ? 9 : 7).frame(height: 22)
            .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(hover ? .white.opacity(0.12) : .clear), in: Capsule())
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
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(.tertiary).multilineTextAlignment(.center) }
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
