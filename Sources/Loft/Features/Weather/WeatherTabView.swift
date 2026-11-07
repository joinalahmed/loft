import SwiftUI

struct WeatherTabView: View {
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var prefs = Preferences.shared
    @State private var cityDraft = Preferences.shared.weatherCity

    var body: some View {
        Group {
            if prefs.weatherCity.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.sun").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("Which city?").font(.system(size: 12, weight: .semibold))
                    HStack {
                        TextField("e.g. Lisbon", text: $cityDraft).textFieldStyle(.roundedBorder).frame(width: 180)
                            .onSubmit { prefs.weatherCity = cityDraft; weather.refreshIfNeeded(force: true) }
                        Button("Save") { prefs.weatherCity = cityDraft; weather.refreshIfNeeded(force: true) }.buttonStyle(.borderedProminent)
                    }.controlSize(.small)
                    Text("No location permission needed. Data by Open-Meteo.").font(.system(size: 9)).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let s = weather.snapshot {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: WeatherService.symbol(for: s.code)).symbolRenderingMode(.multicolor).font(.system(size: 30))
                            Text("\(Int(s.temperature.rounded()))°").font(.system(size: 40, weight: .bold, design: .rounded))
                        }
                        Text(WeatherService.describe(s.code)).font(.system(size: 12, weight: .semibold))
                        Text(s.place).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 12) {
                            Label("\(Int(s.feelsLike.rounded()))°", systemImage: "thermometer.variable")
                            Label("\(s.humidity)%", systemImage: "humidity.fill")
                            Label(String(format: "%.0f km/h", s.windKph), systemImage: "wind")
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(width: 200, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach(s.daily) { d in
                            Card(padding: 6) {
                                VStack(spacing: 4) {
                                    Text(dayName(d.date)).font(.system(size: 10, weight: .semibold))
                                    Image(systemName: WeatherService.symbol(for: d.code)).symbolRenderingMode(.multicolor).font(.system(size: 16))
                                    Text("\(Int(d.hi.rounded()))°").font(.system(size: 11, weight: .semibold))
                                    Text("\(Int(d.lo.rounded()))°").font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    SmallIconButton(symbol: "arrow.clockwise", size: 10, help: "Refresh") { weather.refreshIfNeeded(force: true) }
                }
            } else if weather.loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    Text(weather.error ?? "Could not load weather").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack { Button("Retry") { weather.refreshIfNeeded(force: true) }; Button("Change city") { prefs.weatherCity = "" } }.controlSize(.small)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { weather.refreshIfNeeded() }
    }

    private func dayName(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        if Calendar.current.isDateInToday(d) { return "Today" }
        let o = DateFormatter(); o.dateFormat = "EEE"; return o.string(from: d)
    }
}
