import AppKit

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
