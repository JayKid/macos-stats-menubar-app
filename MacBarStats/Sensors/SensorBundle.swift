import Foundation

/// Owns the live sensor objects for the app. Each source is optional so
/// that "this Mac doesn't expose X" degrades gracefully (e.g., MacBook Air
/// has no fan source, a Mac without a battery skips the battery source).
final class SensorBundle {

    let temperatures: IOHIDTemperatureSource?
    let fans: SMCFanSource?
    let cpu: CPUUsageSource
    let gpu: GPUUsageSource?
    let battery: BatterySource

    init() {
        self.temperatures = IOHIDTemperatureSource()
        self.fans = SMCFanSource()
        self.cpu = CPUUsageSource()
        self.gpu = GPUUsageSource()
        self.battery = BatterySource()
    }

    func sample() -> Snapshot {
        Snapshot(
            timestamp: Date(),
            temperatures: temperatures?.read() ?? [],
            fans: fans?.read() ?? [],
            cpu: cpu.read(),
            gpu: gpu?.read(),
            battery: battery.read()
        )
    }
}
