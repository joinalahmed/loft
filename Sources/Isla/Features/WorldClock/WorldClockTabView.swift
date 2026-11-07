import SwiftUI

/// Cities in a row of cards: local time, offset from here, day/night tint, tomorrow/yesterday.
/// Type a city to add it; drag to reorder; right-click to rename or remove. A time scrubber
/// lets you ask "what time is it there when it is 9 am here?"
struct WorldClockTabView: View {
    @ObservedObject var store = WorldClockStore.shared
    @ObservedObject var vm = NotchViewModel.shared
    @State private var query = ""
    @State private var scrub: Double = 0       // hours offset from now, −12…+12
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Add a city or time zone…", text: $query).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                        .onSubmit { if let first = WorldClockPlaces.search(query).first { store.add(first.zone, label: first.label); query = "" } }
                }
                .padding(.horizontal, 10).frame(height: 26).background(.white.opacity(0.08), in: Capsule())
                .frame(width: 260)
                .overlay(alignment: .topLeading) {
                    let results = WorldClockPlaces.search(query)
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { hit in
                                Button { store.add(hit.zone, label: hit.label); query = "" } label: {
                                    HStack {
                                        Text(hit.city).font(.system(size: 12, weight: .medium))
                                        Text(hit.country).font(.system(size: 10)).foregroundStyle(.secondary)
                                        Text(hit.zone).font(.system(size: 10)).foregroundStyle(.tertiary)
                                        Spacer()
                                        Text(WorldClockZone(identifier: hit.zone).time(at: Date())).font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10).frame(height: 24).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1)))
                        .offset(y: 30).zIndex(10)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 11)).foregroundStyle(.secondary)
                    Slider(value: $scrub, in: -12...12, step: 0.5).frame(width: 150)
                    Text(scrub == 0 ? "Now" : (scrub > 0 ? "+" : "−") + String(format: "%g h", abs(scrub)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 44, alignment: .leading)
                    if scrub != 0 { SmallIconButton(symbol: "arrow.counterclockwise", size: 10, help: "Back to now") { scrub = 0 } }
                }
            }
            .zIndex(10)
            if store.zones.isEmpty {
                EmptyHint(symbol: "globe", title: "No cities yet", subtitle: "Search above to add places you care about.")
            } else {
                TimelineView(.everyMinute) { ctx in
                    let date = ctx.date.addingTimeInterval(scrub * 3600)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            localCard(at: date)
                            ForEach(store.zones) { zone in
                                ZoneCard(zone: zone, date: date)
                                    .contextMenu {
                                        Button("Rename…") { rename(zone) }
                                        Button("Move Left") { move(zone, by: -1) }.disabled(store.zones.first == zone)
                                        Button("Move Right") { move(zone, by: 1) }.disabled(store.zones.last == zone)
                                        Divider()
                                        Button("Remove", role: .destructive) { store.remove(zone) }
                                    }
                            }
                        }
                    }.scrollIndicators(.never)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { focused = vm.wantsKeyboard && store.zones.isEmpty }
    }

    private func localCard(at date: Date) -> some View {
        ZoneCard(zone: WorldClockZone(identifier: TimeZone.current.identifier, label: "Here"), date: date, isLocal: true)
    }

    private func move(_ zone: WorldClockZone, by delta: Int) {
        guard let i = store.zones.firstIndex(of: zone) else { return }
        let j = i + delta
        guard store.zones.indices.contains(j) else { return }
        store.zones.swapAt(i, j)
    }

    private func rename(_ zone: WorldClockZone) {
        let alert = NSAlert()
        alert.messageText = "Label for \(WorldClockZone.cityName(zone.identifier))"
        alert.informativeText = "Shown instead of the city name, e.g. a person or an office."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24)); field.stringValue = zone.label ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let i = store.zones.firstIndex(of: zone) {
            store.zones[i].label = field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : field.stringValue
        }
    }
}

struct ZoneCard: View {
    let zone: WorldClockZone
    let date: Date
    var isLocal = false
    var body: some View {
        let hour = zone.hour(at: date)
        let night = hour < 6 || hour >= 20
        let evening = hour >= 17 && hour < 20
        let dawn = hour >= 6 && hour < 8
        let tint: Color = night ? .indigo : evening ? .orange : dawn ? .pink : .yellow
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: night ? "moon.stars.fill" : evening ? "sunset.fill" : dawn ? "sunrise.fill" : "sun.max.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                Text(zone.city).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(zone.time(at: date)).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text(isLocal ? TimeZone.current.abbreviation(for: date) ?? "" : zone.offsetText(at: date))
                if let d = zone.dayText(at: date) { Text("· \(d)") }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            // 24-hour band with the local hour marked, so the shape of their day is visible at a glance.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [.indigo.opacity(0.5), .yellow.opacity(0.5), .orange.opacity(0.5), .indigo.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                        .mask(Capsule())
                    Circle().fill(.white).frame(width: 7, height: 7)
                        .offset(x: geo.size.width * CGFloat(hour) / 24 - 3.5)
                }
            }.frame(height: 5)
        }
        .padding(10)
        .frame(width: 138, height: 100, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(isLocal ? 0.22 : 0.14), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isLocal ? tint.opacity(0.45) : .white.opacity(0.07), lineWidth: 0.5)
        }
    }
}
