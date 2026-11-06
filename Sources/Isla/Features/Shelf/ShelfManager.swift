import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var isImage: Bool { ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"].contains(url.pathExtension.lowercased()) }
    /// Real preview for images, Finder icon for everything else.
    var icon: NSImage {
        if isImage, let img = NSImage(contentsOf: url) { return img.resized(maxDimension: 160) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    static func == (a: ShelfItem, b: ShelfItem) -> Bool { a.url == b.url }
}

@MainActor
final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()
    @Published private(set) var items: [ShelfItem] = []
    private let tempDir = AppSupport.directory("Shelf")
    private let store = AppSupport.directory("").appendingPathComponent("shelf.json")

    private init() { load() }

    func ingest(_ providers: [NSItemProvider]) {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                    guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in self?.add(url) }
                }
            } else if p.canLoadObject(ofClass: NSImage.self) {
                _ = p.loadObject(ofClass: NSImage.self) { [weak self] obj, _ in
                    guard let img = obj as? NSImage, let tiff = img.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in self?.addTemp(data: png, ext: "png", base: "Image") }
                }
            } else if p.canLoadObject(ofClass: NSString.self) {
                _ = p.loadObject(ofClass: NSString.self) { [weak self] obj, _ in
                    guard let s = obj as? String, let data = s.data(using: .utf8) else { return }
                    Task { @MainActor in self?.addTemp(data: data, ext: "txt", base: "Text") }
                }
            }
        }
    }

    /// Drops entries whose files were deleted or moved since they were shelved.
    /// File checks run off the main thread: protected folders can block on a permission prompt.
    func prune() {
        let paths = items.map(\.url.path)
        Task.detached(priority: .utility) { [weak self] in
            let gone = Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
            guard !gone.isEmpty else { return }
            await MainActor.run {
                guard let self else { return }
                self.items.removeAll { gone.contains($0.url.path) }
                self.save()
            }
        }
    }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.insert(ShelfItem(url: url), at: 0)
        save()
    }

    private func addTemp(data: Data, ext: String, base: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let url = tempDir.appendingPathComponent("\(base) \(stamp).\(ext)")
        try? data.write(to: url)
        add(url)
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        if item.url.path.hasPrefix(tempDir.path) { try? FileManager.default.removeItem(at: item.url) }
        save()
    }

    func clear() { items.forEach { if $0.url.path.hasPrefix(tempDir.path) { try? FileManager.default.removeItem(at: $0.url) } }; items.removeAll(); save() }

    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func airDrop(_ selection: [ShelfItem]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        let vm = NotchViewModel.shared
        vm.pinnedOpen = true
        service.perform(withItems: selection.map(\.url))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { vm.pinnedOpen = false }
    }

    func copyToClipboard(_ selection: [ShelfItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(selection.map { $0.url as NSURL })
    }

    private func load() {
        guard let data = try? Data(contentsOf: store), let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        items = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
        prune()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items.map(\.url.path)) { try? data.write(to: store, options: .atomic) }
    }
}
