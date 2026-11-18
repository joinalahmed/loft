import SwiftUI

/// The full-screen call to prayer: a calm, centred page tinted for the time of day, with the
/// day's timetable, an ayah to read, and its recitation one key away.
struct SalahAlertView: View {
    let prayer: PrayerTime
    let today: [PrayerTime]
    let following: PrayerTime?
    let place: String
    let ayah: PrayerTimesService.Ayah?
    @ObservedObject var salah = PrayerTimesService.shared
    @State private var appeared = false
    @State private var breathe = false

    struct Theme { let accent: Color; let top: Color; let bottom: Color }
    static func theme(for key: String) -> Theme {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch key {
        case "fajr": return Theme(accent: c(0.66, 0.76, 1.0), top: c(0.07, 0.10, 0.30), bottom: c(0.36, 0.28, 0.50))
        case "dhuhr": return Theme(accent: c(1.0, 0.84, 0.42), top: c(0.04, 0.20, 0.36), bottom: c(0.10, 0.36, 0.44))
        case "asr": return Theme(accent: c(1.0, 0.72, 0.38), top: c(0.06, 0.17, 0.28), bottom: c(0.34, 0.20, 0.08))
        case "maghrib": return Theme(accent: c(1.0, 0.58, 0.46), top: c(0.13, 0.07, 0.27), bottom: c(0.40, 0.13, 0.16))
        default: return Theme(accent: c(0.58, 0.86, 0.90), top: c(0.02, 0.05, 0.14), bottom: c(0.05, 0.17, 0.26))
        }
    }

    var body: some View {
        let theme = Self.theme(for: prayer.key)
        GeometryReader { geo in
            let s = max(0.8, min(1.45, min(geo.size.width / 1440, geo.size.height / 900)))
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                LinearGradient(colors: [theme.top, theme.bottom], startPoint: .top, endPoint: .bottom).opacity(0.9).ignoresSafeArea()
                RadialGradient(colors: [theme.accent.opacity(0.30), .clear], center: .init(x: 0.5, y: 0.26), startRadius: 0, endRadius: geo.size.height * 0.55)
                    .ignoresSafeArea().blendMode(.screen)
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom).ignoresSafeArea()

                VStack(spacing: 0) {
                    emblem(theme, s)
                    Text(("Salah" + (place.isEmpty ? "" : " · \(place)")).uppercased())
                        .font(.system(size: 13 * s, weight: .semibold)).tracking(3 * s).foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 22 * s)
                    Text(prayer.name)
                        .font(.system(size: 104 * s, weight: .bold, design: .serif)).tracking(-1)
                        .foregroundStyle(LinearGradient(colors: [.white, theme.accent], startPoint: .top, endPoint: .bottom))
                        .shadow(color: theme.accent.opacity(0.35), radius: 30 * s)
                        .padding(.top, 2 * s)
                    Text("It is time to pray · \(prayer.date.shortTime)")
                        .font(.system(size: 21 * s, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    timeline(theme, s).padding(.top, 30 * s)
                    if let ayah { verse(ayah, theme, s).padding(.top, 30 * s) }
                    controls(theme, s).padding(.top, 30 * s)
                }
                .frame(maxWidth: min(geo.size.width * 0.7, 860 * s))
                .scaleEffect(appeared ? 1 : 0.96).opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
                .onTapGesture { }   // taps on the content do not dismiss
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { FullScreenAlertController.shared.dismiss() }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func emblem(_ theme: Theme, _ s: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(theme.accent.opacity(0.18), lineWidth: 1).frame(width: 132 * s, height: 132 * s)
                .scaleEffect(breathe ? 1.08 : 0.96).opacity(breathe ? 0.4 : 1)
            Circle().fill(theme.accent.opacity(0.16)).frame(width: 96 * s, height: 96 * s)
            Circle().strokeBorder(theme.accent.opacity(0.55), lineWidth: 1).frame(width: 96 * s, height: 96 * s)
            Image(systemName: prayer.symbol).font(.system(size: 40 * s, weight: .medium)).foregroundStyle(theme.accent)
        }
        .frame(height: 132 * s)
    }

    /// The five prayers of the day on one line, this one lit.
    private func timeline(_ theme: Theme, _ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            ForEach(today.filter(\.isPrayer)) { p in
                let current = p.key == prayer.key
                VStack(spacing: 3 * s) {
                    Text(p.name).font(.system(size: 13 * s, weight: .semibold))
                    Text(p.date.shortTime).font(.system(size: 12.5 * s, weight: .medium, design: .rounded)).monospacedDigit().opacity(current ? 0.8 : 0.7)
                }
                .foregroundStyle(current ? Color.black.opacity(0.88) : .white.opacity(p.date < prayer.date ? 0.4 : 0.85))
                .frame(maxWidth: .infinity).frame(height: 54 * s)
                .background {
                    if current { RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(theme.accent) }
                    else { RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(.white.opacity(0.07)) }
                }
                .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).strokeBorder(.white.opacity(current ? 0.3 : 0.1), lineWidth: 0.75))
            }
        }
    }

    private func verse(_ a: PrayerTimesService.Ayah, _ theme: Theme, _ s: CGFloat) -> some View {
        VStack(spacing: 12 * s) {
            Text(a.arabic).font(.system(size: 30 * s, weight: .medium)).lineSpacing(10 * s)
                .multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.45)
            if !a.translation.isEmpty {
                Text("“\(a.translation)”").font(.system(size: 17 * s, design: .serif)).italic().foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10 * s) {
                Rectangle().fill(theme.accent.opacity(0.4)).frame(width: 28 * s, height: 1)
                Text("\(a.surahName) \(a.surah):\(a.ayah)").font(.system(size: 12.5 * s, weight: .semibold)).tracking(1).foregroundStyle(theme.accent)
                Rectangle().fill(theme.accent.opacity(0.4)).frame(width: 28 * s, height: 1)
            }
        }
        .padding(.horizontal, 30 * s).padding(.vertical, 24 * s)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 26 * s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
    }

    private func controls(_ theme: Theme, _ s: CGFloat) -> some View {
        VStack(spacing: 16 * s) {
            HStack(spacing: 12 * s) {
                if let ayah {
                    pill(salah.audioLoading ? "Loading…" : salah.playing ? "Pause" : "Listen", symbol: salah.playing ? "pause.fill" : "play.fill", hint: "P", filled: false, theme, s) {
                        salah.togglePlayback(ayah)
                    }
                    .keyboardShortcut("p", modifiers: [])
                }
                pill("Dismiss", symbol: nil, hint: "↩", filled: true, theme, s) { FullScreenAlertController.shared.dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            if let following {
                Text("Next is \(following.name) at \(following.date.shortTime)").font(.system(size: 13 * s, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            // esc works as well as return
            Button("") { FullScreenAlertController.shared.dismiss() }.keyboardShortcut(.escape, modifiers: []).opacity(0).frame(width: 0, height: 0)
        }
    }

    private func pill(_ title: String, symbol: String?, hint: String, filled: Bool, _ theme: Theme, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9 * s) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15 * s, weight: .semibold)) }
                Text(title).font(.system(size: 17 * s, weight: filled ? .semibold : .medium))
                Text(hint).font(.system(size: 11 * s, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6 * s).frame(height: 20 * s)
                    .background((filled ? Color.black : Color.white).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .foregroundStyle(filled ? Color.black.opacity(0.88) : .white.opacity(0.94))
            .padding(.horizontal, 24 * s).frame(height: 50 * s)
            .background {
                if filled { Capsule().fill(theme.accent) } else { Capsule().fill(.white.opacity(0.10)) }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
