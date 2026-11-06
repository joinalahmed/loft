import Foundation
import Darwin
import Combine

@MainActor
final class SystemStats: ObservableObject {
    static let shared = SystemStats()
    @Published private(set) var cpu: Double = 0           // 0…1
    @Published private(set) var memoryUsed: Double = 0    // bytes
    @Published private(set) var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var diskFree: Double = 0
    @Published private(set) var diskTotal: Double = 0
    @Published private(set) var netDown: Double = 0       // bytes/s
    @Published private(set) var netUp: Double = 0
    @Published private(set) var uptime: TimeInterval = 0
    private var timer: Timer?
    private var prevTicks: (idle: UInt64, total: UInt64) = (0, 0)
    private var prevNet: (rx: UInt64, tx: UInt64, at: Date) = (0, 0, Date())
    private var subscribers = 0

    private init() {}

    func subscribe() { subscribers += 1; if timer == nil { sample(); timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.sample() } } } }
    func unsubscribe() { subscribers = max(0, subscribers - 1); if subscribers == 0 { timer?.invalidate(); timer = nil } }

    private func sample() {
        sampleCPU(); sampleMemory(); sampleDisk(); sampleNetwork()
        uptime = ProcessInfo.processInfo.systemUptime
    }

    private func sampleCPU() {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var idle: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[base + Int(CPU_STATE_USER)]), sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)]), idl = UInt64(info[base + Int(CPU_STATE_IDLE)])
            idle += idl; total += user + sys + nice + idl
        }
        let dIdle = Double(idle &- prevTicks.idle), dTotal = Double(total &- prevTicks.total)
        if prevTicks.total > 0, dTotal > 0 { cpu = max(0, min(1, 1 - dIdle / dTotal)) }
        prevTicks = (idle, total)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        memoryUsed = used
    }

    private func sampleDisk() {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") else { return }
        diskTotal = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            diskFree = Double(free)
        } else {
            diskFree = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        }
    }

    private func sampleNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("pdp") else { continue }
            rx += UInt64(data.pointee.ifi_ibytes); tx += UInt64(data.pointee.ifi_obytes)
        }
        let now = Date(); let dt = now.timeIntervalSince(prevNet.at)
        if prevNet.rx > 0, dt > 0 {
            netDown = Double(rx &- prevNet.rx) / dt; netUp = Double(tx &- prevNet.tx) / dt
        }
        prevNet = (rx, tx, now)
    }

    static func bytes(_ v: Double, perSecond: Bool = false) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = max(0, v); var i = 0
        while value >= 1000, i < units.count - 1 { value /= 1000; i += 1 }
        let s = i == 0 ? String(format: "%.0f %@", value, units[i]) : String(format: value < 10 ? "%.2f %@" : value < 100 ? "%.1f %@" : "%.0f %@", value, units[i])
        return s + (perSecond ? "/s" : "")
    }
}
