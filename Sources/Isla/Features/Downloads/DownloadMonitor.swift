import Foundation
import AppKit
import Combine

struct ActiveDownload: Equatable {
    var name: String
    var bytes: Int64
    var total: Int64?
    var progress: Double? { total.map { $0 > 0 ? Double(bytes) / Double($0) : nil } ?? nil }
}

/// Watches ~/Downloads for browser temp files (.download / .crdownload / .part) and shows a live
/// progress island, then a "complete" island with a Reveal action. Opt-in: the first access
/// triggers the Downloads-folder permission prompt, so everything runs on a utility queue.
@MainActor
final class DownloadMonitor: ObservableObject {
    static let shared = DownloadMonitor()
    @Published private(set) var active: ActiveDownload?
    private static let queue = DispatchQueue(label: "isla.downloads", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var poll: Timer?
    private var tracked: [String: ActiveDownload] = [:]
    private let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private static let tempExt: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]
    private init() {}

    func applyPreferences() {
        if Preferences.shared.downloadsEnabled { start() } else { stop() }
    }

    private func start() {
        guard source == nil else { return }
        let dir = self.dir
        Self.queue.async { [weak self] in
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: Self.queue)
            src.setEventHandler { [weak self] in self?.scan() }
            src.setCancelHandler { close(fd) }
            Task { @MainActor in
                guard let self, self.source == nil else { src.cancel(); return }
                self.source = src; src.resume()
            }
        }
    }

    private func stop() {
        source?.cancel(); source = nil
        poll?.invalidate(); poll = nil
        tracked.removeAll(); active = nil
    }

    nonisolated private func scan() {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        var found: [String: ActiveDownload] = [:]
        for name in names {
            let url = dir.appendingPathComponent(name)
            guard Self.tempExt.contains(url.pathExtension.lowercased()) else { continue }
            var bytes: Int64 = 0; var total: Int64?
            if url.pathExtension.lowercased() == "download" {
                // Safari: a bundle with Info.plist carrying progress.
                if let plist = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) {
                    bytes = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
                }
                if bytes == 0, let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let f as URL in e { bytes += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                }
            } else {
                bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            let display = url.deletingPathExtension().lastPathComponent
            found[name] = ActiveDownload(name: display, bytes: bytes, total: total)
        }
        Task { @MainActor in self.update(found) }
    }

    private func update(_ found: [String: ActiveDownload]) {
        let finished = Set(tracked.keys).subtracting(found.keys)
        for key in finished {
            let d = tracked[key]!
            // The final file usually shares the base name.
            let final = dir.appendingPathComponent(d.name)
            let exists = FileManager.default.fileExists(atPath: final.path)
            NotchViewModel.shared.show(message: IslandMessage(
                title: "Download complete", subtitle: d.name, symbol: "arrow.down.circle.fill", tint: .green,
                action: exists ? { NSWorkspace.shared.activateFileViewerSelecting([final]) } : nil), duration: 5)
            if exists, Preferences.shared.shelfEnabled { ShelfManager.shared.add(final) }
        }
        tracked = found
        active = found.values.max { $0.bytes < $1.bytes }
        if !found.isEmpty, poll == nil {
            poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Self.queue.async { self?.scan() } }
        } else if found.isEmpty { poll?.invalidate(); poll = nil }
    }
}
