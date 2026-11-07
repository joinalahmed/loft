import Foundation
import Combine

struct StockQuote: Identifiable, Equatable {
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let currency: String
    let sparkline: [Double]
    var id: String { symbol }
}

/// Quotes via Yahoo Finance chart endpoint (no key). Refreshes every 2 minutes while shown.
@MainActor
final class StocksService: ObservableObject {
    static let shared = StocksService()
    @Published private(set) var quotes: [StockQuote] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var error: String?
    private var inflight = false
    private init() {}

    func refresh(force: Bool = false) {
        if !force, let l = lastUpdate, Date().timeIntervalSince(l) < 120 { return }
        guard !inflight else { return }
        inflight = true
        let symbols = Preferences.shared.stockSymbols
        Task {
            var out: [StockQuote] = []
            for s in symbols {
                if let q = await Self.fetch(s) { out.append(q) }
            }
            quotes = out; lastUpdate = Date(); inflight = false
            error = out.isEmpty && !symbols.isEmpty ? "Could not load quotes" : nil
        }
    }

    private static func fetch(_ symbol: String) async -> StockQuote? {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?range=1d&interval=5m&includePrePost=false") else { return nil }
        var req = URLRequest(url: url); req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = ((root["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double else { return nil }
        let prev = meta["chartPreviousClose"] as? Double ?? meta["previousClose"] as? Double ?? price
        let closes = (((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first?["close"] as? [Any])?.compactMap { $0 as? Double } ?? []
        return StockQuote(symbol: symbol, name: meta["shortName"] as? String ?? meta["longName"] as? String ?? symbol, price: price,
                          change: price - prev, changePercent: prev > 0 ? (price - prev) / prev * 100 : 0,
                          currency: meta["currency"] as? String ?? "USD", sparkline: closes)
    }
}
