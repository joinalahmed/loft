import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar and joins every Space.
final class NotchWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .mainMenu + 3
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    // Text fields inside the panel need key status; `.nonactivatingPanel` keeps the app itself inactive.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func applySharing(hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
    }
}


/// Hosting view that only accepts mouse events on the island itself. The window is wider than the
/// island (so the panel can grow), and relying on per-pixel transparency alone proved unreliable:
/// clicks in the invisible margin must reach the app underneath.
final class IslandHostingView: NSHostingView<NotchRootView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let vm = MainActor.assumeIsolated { NotchViewModel.shared }
        guard !MainActor.assumeIsolated({ vm.isHidden }) else { return nil }
        var p = convert(point, from: superview)
        if !isFlipped { p.y = bounds.height - p.y }
        let frame = vm.islandFrame.isEmpty ? bounds : vm.islandFrame.insetBy(dx: -4, dy: -4)
        return frame.contains(p) ? super.hitTest(point) : nil
    }
}
