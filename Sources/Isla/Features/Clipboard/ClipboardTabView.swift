import SwiftUI

struct ClipboardTabView: View {
    @ObservedObject var clip = ClipboardManager.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                    TextField("Search clipboard…", text: $clip.query).textFieldStyle(.plain).font(.system(size: 12))
                        .focused($searchFocused)
                }
                .padding(.horizontal, 10).frame(height: 26)
                .background(.white.opacity(0.08), in: Capsule())
                Text("\(clip.items.count)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                SmallIconButton(symbol: "trash", size: 11, help: "Clear unpinned") { clip.clear() }
            }
            if clip.filtered.isEmpty {
                EmptyHint(symbol: "doc.on.clipboard", title: clip.items.isEmpty ? "Nothing copied yet" : "No matches",
                          subtitle: clip.items.isEmpty ? "Everything you copy shows up here. Click to copy again, double-click to paste." : nil)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(clip.filtered) { item in ClipRow(item: item) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear { if NotchViewModel.shared.wantsKeyboard { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true } } }
        .onReceive(NotificationCenter.default.publisher(for: .islaWantsKeyboard)) { _ in searchFocused = true }
    }
}

private struct ClipRow: View {
    @ObservedObject var clip = ClipboardManager.shared
    let item: ClipItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if item.kind == .color, let c = Color(hex: item.text) {
                    RoundedRectangle(cornerRadius: 5).fill(c).frame(width: 22, height: 22)
                } else if item.kind == .image, let img = clip.image(for: item) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Text(item.preview).font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if hover {
                HStack(spacing: 2) {
                    SmallIconButton(symbol: "arrow.down.doc", size: 10, help: "Paste") { clip.paste(item) }
                    SmallIconButton(symbol: item.pinned ? "pin.fill" : "pin", size: 10, help: "Pin", tint: item.pinned ? .yellow : .white) { clip.togglePin(item) }
                    SmallIconButton(symbol: "xmark", size: 10, help: "Delete") { clip.delete(item) }
                }
            } else {
                if item.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
                Text(item.date, style: .relative).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).frame(height: 36)
        .background(hover ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { clip.paste(item) }
        .onTapGesture { clip.copy(item) }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
