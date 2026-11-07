import Foundation
import AppKit
import SwiftUI
import IOKit.ps
import IOKit
import Combine

@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var pluggedIn = false
    @Published private(set) var hasBattery = true
    @Published private(set) var timeRemainingMinutes: Int?
    @Published private(set) var cycleCount: Int?
    @Published private(set) var healthPercent: Int?
    @Published private(set) var temperatureC: Double?
    private var source: CFRunLoopSource?
    private var primed = false
    private var announcedFull = false
    private var warnedLevels = Set<Int>()

    private init() {}

    func start() {
        refresh()
        primed = true
        let callback: IOPowerSourceCallbackType = { _ in Task { @MainActor in BatteryMonitor.shared.refresh() } }
        source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any] else {
            hasBattery = false; return
        }
        let newLevel = desc[kIOPSCurrentCapacityKey] as? Int ?? level
        let newCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let newPlugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let ttf = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
        let tte = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
        timeRemainingMinutes = newCharging ? (ttf > 0 ? ttf : nil) : (tte > 0 ? tte : nil)
        readSmartBattery()

        let plugChanged = newPlugged != pluggedIn || newCharging != isCharging
        level = newLevel; isCharging = newCharging; pluggedIn = newPlugged
        guard primed, Preferences.shared.batteryAlerts else { return }
        if plugChanged {
            NotchViewModel.shared.show(.battery(level: level, charging: isCharging, pluggedIn: pluggedIn, low: false), duration: 2.5)
        }
        let prefs = Preferences.shared
        if !pluggedIn {
            for threshold in [prefs.batteryLowLevel, prefs.batteryCriticalLevel, 5] where level <= threshold && !warnedLevels.contains(threshold) {
                warnedLevels.insert(threshold)
                NotchViewModel.shared.show(.battery(level: level, charging: false, pluggedIn: false, low: true), duration: 4)
                if threshold <= prefs.batteryCriticalLevel { NSSound(named: "Basso")?.play() }
            }
            announcedFull = false
        } else {
            warnedLevels.removeAll()
            if level >= 100, !isCharging, !announcedFull, prefs.batteryFullAlert {
                announcedFull = true
                NotchViewModel.shared.show(message: IslandMessage(title: "Fully charged", subtitle: "You can unplug now", symbol: "battery.100percent.bolt", tint: .green), duration: 4)
            }
        }
    }

    private func readSmartBattery() {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard entry != 0 else { return }
        defer { IOObjectRelease(entry) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }
        cycleCount = dict["CycleCount"] as? Int
        if let design = dict["DesignCapacity"] as? Int, design > 0 {
            let maxCap = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["NominalChargeCapacity"] as? Int) ?? (dict["MaxCapacity"] as? Int)
            if let maxCap { healthPercent = min(100, Int((Double(maxCap) / Double(design) * 100).rounded())) }
        }
        if let t = dict["Temperature"] as? Int { temperatureC = Double(t) / 100 }
    }
}
