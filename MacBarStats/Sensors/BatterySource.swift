import Foundation
import IOKit
import IOKit.ps

/// Battery charge / state / health via two complementary APIs:
///   1. `IOPSCopyPowerSourcesInfo` for the user-facing fields (charge %,
///      charging/discharging, time remaining).
///   2. IORegistry walk to `AppleSmartBattery` for cycle count, design vs
///      current max capacity, and instantaneous wattage.
///
/// Returns `nil` on Macs without a battery (Mac mini, Studio, Pro), in
/// which case the popup hides the battery section entirely.
final class BatterySource {

    func read() -> BatteryReading? {
        guard hasBattery() else { return nil }

        // 1. IOPowerSources for charge / state / time.
        let snapshotRef = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sourcesRef  = snapshotRef.flatMap { IOPSCopyPowerSourcesList($0)?.takeRetainedValue() }
        guard let snapshot = snapshotRef, let sources = sourcesRef as? [CFTypeRef] else {
            return nil
        }

        var charge: Double = 0
        var state: BatteryReading.State = .unknown
        var minutesRemaining: Int? = nil

        for src in sources {
            guard let dict = IOPSGetPowerSourceDescription(snapshot, src)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let cur = dict[kIOPSCurrentCapacityKey] as? Int,
               let max = dict[kIOPSMaxCapacityKey] as? Int, max > 0 {
                charge = Double(cur) / Double(max)
            }
            let isCharging  = (dict[kIOPSIsChargingKey]  as? Bool) ?? false
            let isCharged   = (dict[kIOPSIsChargedKey]   as? Bool) ?? false
            if isCharged       { state = .full }
            else if isCharging { state = .charging }
            else               { state = .discharging }

            if let m = dict[kIOPSTimeToFullChargeKey] as? Int, state == .charging, m > 0 {
                minutesRemaining = m
            } else if let m = dict[kIOPSTimeToEmptyKey] as? Int, state == .discharging, m > 0 {
                minutesRemaining = m
            }
        }

        // 2. AppleSmartBattery for cycles, health, wattage.
        let (cycles, health, wattage) = readSmartBattery()

        return BatteryReading(
            charge: charge,
            state: state,
            timeRemainingMinutes: minutesRemaining,
            cycleCount: cycles,
            health: health,
            wattage: wattage
        )
    }

    private func hasBattery() -> Bool {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        return !list.isEmpty
    }

    private func readSmartBattery() -> (cycles: Int?, health: Double?, wattage: Double?) {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault,
                                                IOServiceMatching("AppleSmartBattery"))
        guard entry != 0 else { return (nil, nil, nil) }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil, nil)
        }

        let cycles = dict["CycleCount"] as? Int

        var health: Double? = nil
        if let design = dict["DesignCapacity"] as? Int,
           let raw = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["MaxCapacity"] as? Int),
           design > 0 {
            health = Double(raw) / Double(design)
        }

        // Amperage in mA, Voltage in mV. Watts = (mA * mV) / 1e6.
        var wattage: Double? = nil
        if let amperage = dict["InstantAmperage"] as? Int,
           let voltage = dict["Voltage"] as? Int {
            wattage = Double(amperage) * Double(voltage) / 1_000_000.0
        } else if let amperage = dict["Amperage"] as? Int,
                  let voltage = dict["Voltage"] as? Int {
            wattage = Double(amperage) * Double(voltage) / 1_000_000.0
        }

        return (cycles, health, wattage)
    }
}
