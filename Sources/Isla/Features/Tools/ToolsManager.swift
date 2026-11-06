import AppKit
import SwiftUI
import Vision
import Combine

/// Small utilities surfaced from the notch: screen colour picker, OCR of a screen region,
/// and the global web-search / calculator used by the command palette.
@MainActor
final class ToolsManager: ObservableObject {
    static let shared = ToolsManager()
    @Published private(set) var recentColors: [NSColor] = []
    private init() {}

    // MARK: Colour picker

    func pickColor() {
        NotchViewModel.shared.close()
        NSColorSampler().show { [weak self] color in
            guard let self, let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
            self.recentColors.insert(c, at: 0); self.recentColors = Array(self.recentColors.prefix(8))
            NotchViewModel.shared.show(message: IslandMessage(title: hex, subtitle: "Copied · " + String(format: "rgb(%d, %d, %d)", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255))), symbol: "eyedropper.halffull", tint: Color(nsColor: c).ensureMinimumBrightness(0.45)), duration: 3)
        }
    }

    // MARK: OCR

    func captureText() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("isla-ocr-\(Int(Date().timeIntervalSince1970)).png")
        NotchViewModel.shared.close()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-s", "-x", tmp.path]
        p.terminationHandler = { _ in
            guard let img = NSImage(contentsOf: tmp), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let req = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                try? FileManager.default.removeItem(at: tmp)
                Task { @MainActor in
                    if text.isEmpty {
                        NotchViewModel.shared.show(message: IslandMessage(title: "No text found", symbol: "text.viewfinder", tint: .orange), duration: 2)
                    } else {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                        let preview = lines.first.map { $0.count > 40 ? String($0.prefix(40)) + "…" : $0 } ?? ""
                        NotchViewModel.shared.show(message: IslandMessage(title: "Copied \(lines.count) line\(lines.count == 1 ? "" : "s")", subtitle: preview, symbol: "text.viewfinder", tint: .green), duration: 3)
                    }
                }
            }
            req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg).perform([req])
        }
        do { try p.run() } catch { Log.app.error("ocr failed: \(error.localizedDescription)") }
    }

    // MARK: Palette helpers

    static func searchURL(_ q: String) -> URL? {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        switch Preferences.shared.searchEngine {
        case "duckduckgo": return URL(string: "https://duckduckgo.com/?q=\(enc)")
        case "bing": return URL(string: "https://www.bing.com/search?q=\(enc)")
        case "perplexity": return URL(string: "https://www.perplexity.ai/search?q=\(enc)")
        default: return URL(string: "https://www.google.com/search?q=\(enc)")
        }
    }

    /// Evaluates simple arithmetic ("12*4+3", "2^10", "15% of 80") with NSExpression.
    static func evaluateMath(_ s: String) -> String? {
        var e = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "^", with: "**")
        if let r = e.range(of: #"^\s*([\d.]+)\s*%\s*of\s*([\d.]+)\s*$"#, options: .regularExpression) {
            let parts = e[r].components(separatedBy: CharacterSet(charactersIn: "% of")).filter { !$0.isEmpty }
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) { return format(a / 100 * b) }
        }
        guard e.range(of: #"^[\d\s.+\-*/()%]+$"#, options: .regularExpression) != nil, e.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/")) != nil else { return nil }
        // Promote integer literals to doubles so 7/2 == 3.5.
        e = e.replacingOccurrences(of: #"(?<![\d.])(\d+)(?![\d.])"#, with: "$1.0", options: .regularExpression)
        let expr = NSExpression(format: e)
        guard let v = expr.expressionValue(with: nil, context: nil) as? NSNumber else { return nil }
        return format(v.doubleValue)
    }

    private static func format(_ d: Double) -> String {
        guard d.isFinite else { return "∞" }
        let f = NumberFormatter(); f.maximumFractionDigits = 6; f.minimumFractionDigits = 0; f.numberStyle = .decimal
        return f.string(from: NSNumber(value: d)) ?? "\(d)"
    }
}
