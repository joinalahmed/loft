import SwiftUI

/// The single view hosted in the notch window. Draws the black island, animates
/// between the resting pill and the expanded panel, and routes hover/click.
struct NotchRootView: View {
    @ObservedObject var vm = NotchViewModel.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var music = MusicManager.shared
    @State private var dropHighlight = false

    private var isOpen: Bool { vm.state == .open }

    private var shape: NotchShape {
        NotchShape(topCornerRadius: vm.topRadius, bottomCornerRadius: vm.bottomRadius)
    }

    private var tint: Color {
        guard prefs.accentTinting, let c = music.accentColor else { return .white }
        return c.ensureMinimumBrightness(0.65)
    }

    var body: some View {
        ZStack(alignment: .top) {
            island
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 0)
        .opacity(vm.isHidden ? 0 : (vm.suppressed && !vm.isHovering && !isOpen && vm.transient == nil) ? 0.001 : (prefs.invisibleUntilHover && !vm.isHovering && !isOpen && vm.transient == nil && !music.isPlaying ? 0.001 : 1))
        .preferredColorScheme(.dark)
        .environment(\.islandTint, tint)
        .onDrop(of: [.fileURL, .url, .image, .utf8PlainText], isTargeted: $dropHighlight) { providers in
            guard prefs.shelfEnabled else { return false }
            ShelfManager.shared.ingest(providers)
            vm.open(tab: .shelf)
            return true
        }
        .onChange(of: dropHighlight) { _, targeted in
            vm.isDragTargeted = targeted
            if targeted, prefs.shelfEnabled { vm.open(tab: .shelf) }
        }
    }

    private var island: some View {
        VStack(spacing: 0) {
            CompactRowView()
                .frame(height: vm.closedHeight)
            if isOpen {
                PanelContentView()
                    .frame(width: vm.openSize.width - vm.topRadius * 2 - 24, height: vm.openSize.height - vm.closedHeight - 12)
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity).animation(.smooth(duration: 0.3).delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .padding(.horizontal, vm.topRadius)
        .padding(.horizontal, isOpen ? 12 : 0)
        .frame(width: isOpen ? vm.openSize.width : nil, alignment: .top)
        .background(Color.black)
        .overlay(alignment: .top) {
            // Hairline that hides sub-pixel seams between island and bezel.
            Rectangle().fill(.black).frame(height: 1).padding(.horizontal, vm.topRadius)
        }
        .clipShape(shape)
        .shadow(color: (isOpen || vm.isHovering || vm.transient != nil) && prefs.enableShadow ? .black.opacity(0.55) : .clear,
                radius: isOpen ? 10 : 5, y: 2)
        .contentShape(shape)
        .onHover { vm.hoverChanged($0) }
        .onTapGesture {
            guard !isOpen else { return }
            if vm.transient == nil, CalendarManager.shared.imminentEvent != nil { vm.open(tab: .calendar, focus: true) } else { vm.open(focus: true) }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { vm.islandFrame = $0 }
        .contextMenu {
            Button("Settings…") { SettingsWindowController.shared.show() }
            Button(vm.isHidden ? "Show Loft" : "Hide Loft (⌥Space)") { vm.isHidden.toggle() }
            Divider()
            Button("Quit Loft") { NSApp.terminate(nil) }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: isOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.transient)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: music.isActive)
    }
}

private struct IslandTintKey: EnvironmentKey { static let defaultValue: Color = .white }
extension EnvironmentValues {
    var islandTint: Color {
        get { self[IslandTintKey.self] }
        set { self[IslandTintKey.self] = newValue }
    }
}
