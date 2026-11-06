import SwiftUI

struct MusicTabView: View {
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var audio = AudioDeviceManager.shared
    @State private var showLyrics = false
    @Environment(\.islandTint) private var tint

    var body: some View {
        if music.title.isEmpty && !music.isPlaying {
            EmptyHint(symbol: "music.note", title: "Nothing playing",
                      subtitle: music.usingAdapter ? "Play something in any app that reports to Now Playing." : "Open Spotify or Music to see controls here.")
        } else {
            HStack(spacing: 14) {
                AlbumArtView(image: music.artwork, cornerRadius: 12)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(music.title, font: .system(size: 15, weight: .bold))
                            MarqueeText(music.artist, font: .system(size: 12, weight: .medium), color: .secondary)
                            if !music.album.isEmpty && !showLyrics {
                                Text(music.album).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            if prefs.lyricsEnabled {
                                SmallIconButton(symbol: showLyrics ? "quote.bubble.fill" : "quote.bubble", size: 11, help: "Lyrics", tint: showLyrics ? tint : .white) { showLyrics.toggle() }
                            }
                            Menu {
                                ForEach(audio.outputDevices) { d in
                                    Button { audio.setDefaultOutput(d) } label: {
                                        Label(d.name, systemImage: d.symbol)
                                        if d.id == audio.defaultOutputID { Image(systemName: "checkmark") }
                                    }
                                }
                            } label: {
                                Image(systemName: audio.outputDevices.first { $0.id == audio.defaultOutputID }?.symbol ?? "speaker.wave.2")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).frame(width: 24, height: 24)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).help("Audio output")
                            .onAppear { audio.refresh() }
                            if let icon = music.sourceIcon {
                                Image(nsImage: icon).resizable().frame(width: 22, height: 22).help(music.sourceName)
                            }
                        }
                    }
                    if showLyrics { LyricsView() } else { Spacer(minLength: 0) }
                    PlaybackScrubber(tint: tint)
                    HStack(spacing: 18) {
                        Spacer()
                        SmallIconButton(symbol: "gobackward.15", size: 14, help: "Back 15s") { music.skip(seconds: -15) }
                        SmallIconButton(symbol: "backward.fill", size: 16, help: "Previous") { music.previous() }
                        Button { music.togglePlayPause() } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 40, height: 40).background(tint, in: Circle())
                                .contentTransition(.symbolEffect(.replace))
                        }.buttonStyle(.plain)
                        SmallIconButton(symbol: "forward.fill", size: 16, help: "Next") { music.next() }
                        SmallIconButton(symbol: "goforward.15", size: 14, help: "Forward 15s") { music.skip(seconds: 15) }
                        Spacer()
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

struct PlaybackScrubber: View {
    @ObservedObject var music = MusicManager.shared
    let tint: Color
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let total = max(1, music.duration)
            let current = dragging ? dragValue : min(total, music.elapsed)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18)).frame(height: 5)
                        Capsule().fill(tint).frame(width: max(5, geo.size.width * CGFloat(current / total)), height: 5)
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragging = true
                            dragValue = Double(min(1, max(0, g.location.x / geo.size.width))) * total
                        }
                        .onEnded { _ in
                            music.seek(to: dragValue)
                            dragging = false
                        })
                }
                .frame(height: 14)
                HStack {
                    Text(current.clockString)
                    Spacer()
                    Text("-" + max(0, total - current).clockString)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// Scrolls horizontally when the text does not fit. Driven by wall-clock time so it
/// never gets stuck mid-animation when the view is rebuilt.
struct MarqueeText: View {
    let text: String
    let font: Font
    var color: Color = .white
    init(_ text: String, font: Font, color: Color = .white) { self.text = text; self.font = font; self.color = color }

    @State private var textWidth: CGFloat = 0
    private let gap: CGFloat = 40
    private let speed: Double = 30      // points per second
    private let pause: Double = 1.5     // seconds at the start of each cycle

    var body: some View {
        GeometryReader { geo in
            let overflow = textWidth > geo.size.width + 1
            let distance = textWidth + gap
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !overflow)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let cycle = pause + Double(distance) / speed
                let phase = t.truncatingRemainder(dividingBy: cycle)
                let offset: CGFloat = overflow ? CGFloat(max(0, phase - pause) * speed) : 0
                HStack(spacing: gap) {
                    label
                    if overflow { label }
                }
                .offset(x: -offset)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: overflow ? 0.92 : 1), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        }
        .frame(height: 18)
        .background(
            // Measure the unconstrained text width off-screen.
            Text(text).font(font).fixedSize().lineLimit(1).hidden()
                .background(GeometryReader { g in Color.clear.onAppear { textWidth = g.size.width }.onChange(of: g.size.width) { _, w in textWidth = w } })
                .frame(width: 0, alignment: .leading).clipped()
        )
    }

    private var label: some View { Text(text).font(font).foregroundStyle(color).fixedSize().lineLimit(1) }
}
