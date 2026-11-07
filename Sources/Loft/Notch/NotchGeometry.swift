import AppKit

extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }

    /// Exact size of the hardware notch, if this display has one.
    var hardwareNotchSize: CGSize? {
        guard let left = auxiliaryTopLeftArea?.width, let right = auxiliaryTopRightArea?.width,
              safeAreaInsets.top > 0 else { return nil }
        return CGSize(width: frame.width - left - right, height: safeAreaInsets.top)
    }

    var menuBarHeight: CGFloat { max(0, frame.maxY - visibleFrame.maxY) }

    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }

    static var screenWithMouse: NSScreen? {
        let loc = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(loc, $0.frame, false) }
    }

    /// Screen Loft should live on: the built-in notched display when present, else the main screen.
    static var preferredNotchScreen: NSScreen? {
        screens.first { $0.hasNotch } ?? screens.first { $0.isBuiltIn } ?? main ?? screens.first
    }
}

/// Everything the UI needs to know about the pill's resting size on a given screen.
struct NotchMetrics: Equatable {
    var hasNotch: Bool
    var closedSize: CGSize       // visible black area when idle
    var menuBarHeight: CGFloat

    static func measure(_ screen: NSScreen, scale: CGFloat) -> NotchMetrics {
        if let size = screen.hardwareNotchSize {
            // +2 covers anti-aliased edges so no bright sliver shows around the real notch.
            return NotchMetrics(hasNotch: true,
                                closedSize: CGSize(width: (size.width + 2) * max(1, scale), height: size.height),
                                menuBarHeight: screen.menuBarHeight)
        }
        let h = max(24, screen.menuBarHeight - 2)
        return NotchMetrics(hasNotch: false,
                            closedSize: CGSize(width: 190 * scale, height: h),
                            menuBarHeight: screen.menuBarHeight)
    }
}
