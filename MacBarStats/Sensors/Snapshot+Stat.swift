import Foundation

extension Snapshot {
    /// Extract a single scalar value for a given menu-bar-style stat. Returns
    /// `nil` when the underlying sensor isn't available (e.g., GPU on a
    /// machine where IOReport doesn't expose `PWRCTRL`, or fan 2 on a 14"
    /// MacBook Pro with only one fan).
    func value(for stat: StatID) -> Double? {
        switch stat {
        case .socTemp:        return tempMax(in: .soc)
        case .batteryTemp:    return tempMax(in: .battery)
        case .nandTemp:       return tempMax(in: .nand)
        case .fan0:           return fans.first(where: { $0.id == 0 })?.actualRPM
        case .fan1:           return fans.first(where: { $0.id == 1 })?.actualRPM
        case .cpuUsage:       return cpu.aggregate * 100
        case .gpuUsage:       return gpu.map { $0.busy * 100 }
        case .batteryCharge:  return battery.map { $0.charge * 100 }
        }
    }

    private func tempMax(in cat: TempCategory) -> Double? {
        let inCat = temperatures.filter { $0.category == cat }
        guard !inCat.isEmpty else { return nil }
        return inCat.map(\.celsius).max()
    }
}

extension Array where Element == Snapshot {
    /// Pull a series of values from a buffer of snapshots — used to feed
    /// sparklines without re-computing per-call.
    func series(for stat: StatID) -> [Double] {
        compactMap { $0.value(for: stat) }
    }
}

extension StatID {
    /// Compact, fixed-width-friendly formatting for the menu bar.
    func format(_ v: Double) -> String {
        switch unit {
        case .celsius:  return String(format: "%.0f°", v)
        case .rpm:      return String(format: "%.0f", v)
        case .percent:  return String(format: "%.0f%%", v)
        }
    }
}
