import SwiftUI

struct StocksTabView: View {
    @ObservedObject var stocks = StocksService.shared
    @ObservedObject var prefs = Preferences.shared
    var body: some View {
        Group {
            if stocks.quotes.isEmpty {
                EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: stocks.error ?? "Loading quotes…", subtitle: "Edit symbols in Settings → Features.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(stocks.quotes) { q in
                            Card(padding: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(q.symbol).font(.system(size: 12, weight: .bold))
                                        Spacer()
                                        Text(q.changePercent, format: .number.precision(.fractionLength(2)).sign(strategy: .always())).font(.system(size: 10, weight: .semibold)).foregroundStyle(q.change >= 0 ? .green : .red) + Text("%").font(.system(size: 10, weight: .semibold)).foregroundStyle(q.change >= 0 ? .green : .red)
                                    }
                                    Text(q.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                    HStack(alignment: .bottom) {
                                        Text(q.price, format: .currency(code: q.currency).precision(.fractionLength(2))).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                                        Spacer()
                                        Sparkline(values: q.sparkline, color: q.change >= 0 ? .green : .red).frame(width: 60, height: 20)
                                    }
                                }
                            }
                        }
                    }
                }.scrollIndicators(.never)
            }
        }
        .onAppear { stocks.refresh() }
        .contextMenu { Button("Refresh") { stocks.refresh(force: true) } }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 0.0001)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                    }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
