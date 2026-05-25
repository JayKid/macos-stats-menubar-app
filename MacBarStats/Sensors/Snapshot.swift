import Foundation

/// A single tick of sensor data. All values are plain `Sendable` structs so
/// they can cross the sampler/UI boundary freely.
struct Snapshot: Sendable {
    let timestamp: Date
    let temperatures: [TemperatureReading]
    let fans: [FanReading]
    let cpu: CPUReading
    let gpu: GPUReading?
    let battery: BatteryReading?
}

struct TemperatureReading: Sendable, Identifiable, Hashable {
    /// Stable identifier: `rawName + "#" + occurrence`. Two sensors with the
    /// same `Product` property are disambiguated by their order of discovery.
    let id: String
    let rawName: String
    let category: TempCategory?
    let celsius: Double
}

struct FanReading: Sendable, Identifiable, Hashable {
    let id: Int            // fan index, 0-based
    let actualRPM: Double
    let targetRPM: Double
    let minRPM: Double
    let maxRPM: Double
}

struct CPUReading: Sendable {
    /// 0...1 per logical core, in core-id order.
    let perCore: [Double]
    /// 0...1 averaged across all cores.
    let aggregate: Double
}

struct GPUReading: Sendable {
    /// 0...1. Note: this is **GPU active power-state residency**, not compute
    /// load. Baseline can sit 50–70 % on an idle desktop because the GPU
    /// remains in the `PERF` state to drive the display. See
    /// `GPUUsageSource.swift` for details.
    let busy: Double
}

struct BatteryReading: Sendable {
    enum State: String, Sendable {
        case charging, discharging, full, unknown
    }

    /// 0...1
    let charge: Double
    let state: State
    /// Minutes remaining; nil while macOS is still calibrating.
    let timeRemainingMinutes: Int?
    let cycleCount: Int?
    /// 0...1 (currentMaxCapacity / designCapacity)
    let health: Double?
    /// Negative when discharging, positive when charging. Watts.
    let wattage: Double?
}
