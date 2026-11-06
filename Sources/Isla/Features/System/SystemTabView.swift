import SwiftUI

struct SystemTabView: View {
    @ObservedObject var stats = SystemStats.shared
    @ObservedObject var battery = BatteryMonitor.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Gauge(title: "CPU", value: stats.cpu, detail: "\(Int(stats.cpu * 100))%", color: .orange)
                Gauge(title: "Memory", value: stats.memoryUsed / max(1, stats.memoryTotal),
                      detail: SystemStats.bytes(stats.memoryUsed), color: .purple)
                Gauge(title: "Disk", value: stats.diskTotal > 0 ? 1 - stats.diskFree / stats.diskTotal : 0,
                      detail: SystemStats.bytes(stats.diskFree) + " free", color: .blue)
                if battery.hasBattery {
                    Gauge(title: "Battery", value: Double(battery.level) / 100,
                          detail: "\(battery.level)%" + (battery.isCharging ? " ⚡︎" : ""), color: battery.level <= 20 ? .red : .green)
                }
            }
            HStack(spacing: 10) {
                Card(padding: 8) {
                    HStack(spacing: 14) {
                        Label(SystemStats.bytes(stats.netDown, perSecond: true), systemImage: "arrow.down").foregroundStyle(.cyan)
                        Label(SystemStats.bytes(stats.netUp, perSecond: true), systemImage: "arrow.up").foregroundStyle(.pink)
                        if let rssi = stats.wifiRSSI {
                            Label("\(rssi) dBm" + (stats.wifiBand.map { " · \($0)" } ?? "") + (stats.wifiRate.map { String(format: " · %.0f Mbps", $0) } ?? ""), systemImage: "wifi")
                                .foregroundStyle(rssi > -60 ? .green : rssi > -75 ? .yellow : .red)
                        }
                    }.font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                }
                if !stats.volumes.isEmpty {
                    Card(padding: 8) {
                        HStack(spacing: 8) {
                            ForEach(stats.volumes) { v in
                                HStack(spacing: 4) {
                                    Image(systemName: "externaldrive.fill").foregroundStyle(.secondary)
                                    Text(v.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    Button { stats.eject(v) } label: { Image(systemName: "eject.fill").font(.system(size: 10)) }.buttonStyle(.plain).help("Eject \(v.name)")
                                }
                            }
                        }
                    }
                }
                Card(padding: 8) {
                    HStack(spacing: 14) {
                        if let h = battery.healthPercent { Label("\(h)% health", systemImage: "heart.fill") }
                        if let c = battery.cycleCount { Label("\(c) cycles", systemImage: "arrow.triangle.2.circlepath") }
                        if let t = battery.temperatureC { Label(String(format: "%.0f °C", t), systemImage: "thermometer.medium") }
                        if let m = battery.timeRemainingMinutes { Label("\(m / 60)h \(m % 60)m \(battery.isCharging ? "to full" : "left")", systemImage: "clock") }
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("up \(Int(stats.uptime / 3600))h \(Int(stats.uptime.truncatingRemainder(dividingBy: 3600) / 60))m")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .onAppear { stats.subscribe() }
        .onDisappear { stats.unsubscribe() }
    }
}

private struct Gauge: View {
    let title: String
    let value: Double
    let detail: String
    let color: Color
    var body: some View {
        Card(padding: 8) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                    Circle().trim(from: 0, to: CGFloat(min(1, max(0, value))))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.6), value: value)
                    Text("\(Int(value * 100))").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                }.frame(width: 50, height: 50)
                Text(title).font(.system(size: 10, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity)
        }
    }
}
