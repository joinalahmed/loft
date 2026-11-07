import Foundation
import SwiftUI
import Combine

struct WeatherSnapshot: Equatable {
    var place: String
    var temperature: Double
    var feelsLike: Double
    var humidity: Int
    var windKph: Double
    var code: Int
    var daily: [Day]
    var fetchedAt: Date
    struct Day: Equatable, Identifiable { var id: String { date }; var date: String; var hi: Double; var lo: Double; var code: Int }
}

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private var lastCity = ""
    private init() {}

    func refreshIfNeeded(force: Bool = false) {
        let prefs = Preferences.shared
        let city = prefs.weatherCity.trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { snapshot = nil; return }
        if !force, city == lastCity, let s = snapshot, Date().timeIntervalSince(s.fetchedAt) < 900 { return }
        lastCity = city
        loading = true; error = nil
        Task {
            do { snapshot = try await fetch(city: city, fahrenheit: prefs.weatherUseFahrenheit) }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    private func fetch(city: String, fahrenheit: Bool) async throws -> WeatherSnapshot {
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        let (gdata, _) = try await URLSession.shared.data(from: geo.url!)
        guard let gobj = try JSONSerialization.jsonObject(with: gdata) as? [String: Any],
              let result = (gobj["results"] as? [[String: Any]])?.first,
              let lat = result["latitude"] as? Double, let lon = result["longitude"] as? Double else {
            throw NSError(domain: "Loft", code: 1, userInfo: [NSLocalizedDescriptionKey: "City not found"])
        }
        let name = [result["name"] as? String, result["country_code"] as? String].compactMap { $0 }.joined(separator: ", ")
        var fc = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        fc.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "5"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        let (fdata, _) = try await URLSession.shared.data(from: fc.url!)
        guard let f = try JSONSerialization.jsonObject(with: fdata) as? [String: Any],
              let cur = f["current"] as? [String: Any], let daily = f["daily"] as? [String: Any],
              let dates = daily["time"] as? [String], let his = daily["temperature_2m_max"] as? [Double],
              let los = daily["temperature_2m_min"] as? [Double], let codes = daily["weather_code"] as? [Int] else {
            throw NSError(domain: "Loft", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad forecast response"])
        }
        let days = zip(zip(dates, his), zip(los, codes)).map { WeatherSnapshot.Day(date: $0.0.0, hi: $0.0.1, lo: $0.1.0, code: $0.1.1) }
        return WeatherSnapshot(place: name,
                               temperature: cur["temperature_2m"] as? Double ?? 0,
                               feelsLike: cur["apparent_temperature"] as? Double ?? 0,
                               humidity: cur["relative_humidity_2m"] as? Int ?? 0,
                               windKph: cur["wind_speed_10m"] as? Double ?? 0,
                               code: cur["weather_code"] as? Int ?? 0, daily: days, fetchedAt: Date())
    }

    static func symbol(for code: Int, night: Bool = false) -> String {
        switch code {
        case 0: night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63, 65: "Rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75: "Snow"
        case 77: "Snow grains"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "—"
        }
    }
}
