import SwiftUI

/// Three-line synced lyrics with the current line highlighted.
struct LyricsView: View {
    @ObservedObject var lyrics = LyricsService.shared
    @ObservedObject var music = MusicManager.shared
    @Environment(\.islandTint) private var tint

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let t = music.elapsed
            if lyrics.loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !lyrics.lines.isEmpty, let i = lyrics.currentIndex(at: t) ?? (lyrics.lines.first.map { _ in -1 }) {
                VStack(alignment: .leading, spacing: 4) {
                    line(at: i - 1, opacity: 0.35)
                    line(at: i, opacity: 1, current: true)
                    line(at: i + 1, opacity: 0.5)
                    line(at: i + 2, opacity: 0.3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.3), value: i)
                .onTapGesture { if lyrics.lines.indices.contains(i + 1) { music.seek(to: lyrics.lines[i + 1].time) } }
            } else if let plain = lyrics.plain {
                ScrollView { Text(plain).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.never)
            } else {
                Text(lyrics.unavailable ? "No lyrics found for this track." : " ").font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .onAppear { lyrics.track(title: music.title, artist: music.artist, album: music.album, duration: music.duration) }
        .onChange(of: music.title) { _, _ in lyrics.track(title: music.title, artist: music.artist, album: music.album, duration: music.duration) }
    }

    @ViewBuilder private func line(at i: Int, opacity: Double, current: Bool = false) -> some View {
        if lyrics.lines.indices.contains(i) {
            Text(lyrics.lines[i].text)
                .font(.system(size: current ? 15 : 12, weight: current ? .bold : .medium))
                .foregroundStyle(current ? tint : .white)
                .opacity(opacity).lineLimit(current ? 2 : 1)
        } else {
            Text(" ").font(.system(size: 12))
        }
    }
}
