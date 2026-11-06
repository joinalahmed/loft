import SwiftUI
import UniformTypeIdentifiers

struct ShelfTabView: View {
    @ObservedObject var shelf = ShelfManager.shared
    @ObservedObject var vm = NotchViewModel.shared
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            if shelf.items.isEmpty {
                EmptyHint(symbol: "tray.and.arrow.down", title: "Drop files here",
                          subtitle: "Drag anything onto the notch to stash it. Drag it back out when you need it.")
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .foregroundStyle(targeted ? .cyan : .white.opacity(0.2)))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in ShelfItemView(item: item) }
                    }
                    .padding(.horizontal, 4).padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                HStack {
                    Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { shelf.airDrop(shelf.items) } label: { Label("AirDrop all", systemImage: "airplayaudio") }
                    Button { shelf.copyToClipboard(shelf.items) } label: { Label("Copy all", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { shelf.clear() } label: { Label("Clear", systemImage: "trash") }
                }
                .buttonStyle(.bordered).controlSize(.small).font(.system(size: 11))
            }
        }
        .onDrop(of: [.fileURL, .image, .utf8PlainText], isTargeted: $targeted) { providers in
            shelf.ingest(providers); return true
        }
    }
}

private struct ShelfItemView: View {
    @ObservedObject var shelf = ShelfManager.shared
    let item: ShelfItem
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon).resizable().aspectRatio(contentMode: .fit).frame(width: 48, height: 48)
            Text(item.name).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(width: 84)
        }
        .padding(6)
        .background(hover ? .white.opacity(0.1) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .gray)
                }.buttonStyle(.plain).offset(x: 4, y: -4)
            }
        }
        .onHover { hover = $0 }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Reveal in Finder") { shelf.reveal(item) }
            Button("AirDrop…") { shelf.airDrop([item]) }
            Button("Copy") { shelf.copyToClipboard([item]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
