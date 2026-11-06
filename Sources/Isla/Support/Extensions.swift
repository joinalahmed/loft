import SwiftUI
import AppKit
import CoreImage

extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

extension NSImage {
    /// Average colour, used for tinting the music island.
    var averageColor: NSColor? {
        guard let tiff = tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let extent = ci.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let output = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return NSColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255, alpha: 1)
    }

    func resized(maxDimension: CGFloat) -> NSImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let image = NSImage(size: newSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }
}

extension Color {
    /// Lifts very dark colours so tinted text stays legible on black.
    func ensureMinimumBrightness(_ minimum: CGFloat) -> Color {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if b < minimum { return Color(hue: Double(h), saturation: Double(s * 0.8), brightness: Double(minimum)) }
        return self
    }
}

extension TimeInterval {
    var clockString: String {
        let total = Int(max(0, self.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension Date {
    var shortTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: self)
    }
}

extension URL {
    var isDirectoryURL: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

extension Notification.Name {
    static let islaOpenPanel = Notification.Name("isla.openPanel")
    static let islaClosePanel = Notification.Name("isla.closePanel")
    static let islaScreenChanged = Notification.Name("isla.screenChanged")
}
