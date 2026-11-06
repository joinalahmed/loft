import AppKit
import SwiftUI
import Combine

/// Screen capture from the notch. Uses the system `screencapture` tool so region and window
/// selection look exactly like ⌘⇧4 / ⌘⇧5. Results go to the Desktop, the shelf and the
/// clipboard depending on preferences. Also watches the Desktop so screenshots taken with
/// the native shortcuts land on the shelf too.
@MainActor
final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()
    enum Mode: String { case region, window, full }

    @Published private(set) var isCapturing = false
    @Published private(set) var recent: [URL] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var knownDesktop: Set<String> = []
    private let prefs = Preferences.shared
    private let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    private var selfMade = Set<String>()

    private init() { applyPreferences() }

    func applyPreferences() {
        if prefs.watchDesktopScreenshots { startWatching() } else { stopWatching() }
    }

    // MARK: Capture

    func capture(_ mode: Mode) {
        guard !isCapturing else { return }
        isCapturing = true
        let vm = NotchViewModel.shared
        vm.close()
        let wasHidden = vm.isHidden
        vm.isHidden = true   // keep the island out of the shot

        let url = destination()
        selfMade.insert(url.lastPathComponent)
        var args = ["-x", "-o"]                 // no sound, no window shadow
        switch mode {
        case .region: args += ["-i", "-s"]
        case .window: args += ["-i", "-W"]
        case .full: break
        }
        args.append(url.path)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = args
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.isCapturing = false
                vm.isHidden = wasHidden
                guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else { return }
                self.finish(url, fromWatcher: false)
            }
        }
        do { try proc.run() } catch {
            isCapturing = false; vm.isHidden = wasHidden
            Log.app.error("screencapture failed: \(error.localizedDescription)")
        }
    }

    private func destination() -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screenshot \(f.string(from: Date())).png"
        let dir = prefs.screenshotSaveToDesktop ? desktop : AppSupport.directory("Screenshots")
        return dir.appendingPathComponent(name)
    }

    private func finish(_ url: URL, fromWatcher: Bool) {
        recent.insert(url, at: 0); if recent.count > 20 { recent.removeLast() }
        if prefs.screenshotToShelf { ShelfManager.shared.add(url) }
        if prefs.screenshotToClipboard, !fromWatcher, let img = NSImage(contentsOf: url) {
            let pb = NSPasteboard.general
            pb.clearContents(); pb.writeObjects([img])
        }
        let thumb = NSImage(contentsOf: url)?.resized(maxDimension: 120)
        NotchViewModel.shared.show(message: IslandMessage(
            title: fromWatcher ? "Screenshot added to shelf" : "Screenshot saved",
            subtitle: [prefs.screenshotToShelf ? "shelf" : nil, prefs.screenshotToClipboard && !fromWatcher ? "clipboard" : nil, prefs.screenshotSaveToDesktop || fromWatcher ? "Desktop" : nil].compactMap { $0 }.joined(separator: " · "),
            symbol: "camera.viewfinder", tint: .cyan, thumbnail: thumb,
            action: { NotchViewModel.shared.open(tab: .shelf) }), duration: 4)
    }

    // MARK: Desktop watcher (native ⌘⇧3/4/5 screenshots → shelf)

    private func startWatching() {
        guard watcher == nil, prefs.shelfEnabled else { return }
        knownDesktop = Set((try? FileManager.default.contentsOfDirectory(atPath: desktop.path)) ?? [])
        watchedFD = open(desktop.path, O_EVTONLY)
        guard watchedFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchedFD, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in self?.desktopChanged() }
        src.setCancelHandler { [fd = watchedFD] in close(fd) }
        src.resume()
        watcher = src
    }

    private func stopWatching() {
        watcher?.cancel(); watcher = nil; watchedFD = -1
    }

    private func desktopChanged() {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: desktop.path)) ?? [])
        let added = names.subtracting(knownDesktop)
        knownDesktop = names
        for name in added where !selfMade.contains(name) {
            let lower = name.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".mov"),
                  lower.hasPrefix("screenshot") || lower.hasPrefix("screen shot") || lower.hasPrefix("screen recording") || lower.hasPrefix("capture") else { continue }
            let url = desktop.appendingPathComponent(name)
            // macOS writes the file a moment after creating it; wait for a stable size.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                self?.finish(url, fromWatcher: true)
            }
        }
    }
}
