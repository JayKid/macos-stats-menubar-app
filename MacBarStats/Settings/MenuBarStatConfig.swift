import Foundation

/// Every thing the menu bar (or popup) can display as a single value. This
/// is also the key used for thresholds and the menu-bar reorder list.
enum StatID: String, Codable, Hashable, CaseIterable, Identifiable {
    case socTemp       = "soc_temp"
    case batteryTemp   = "battery_temp"
    case nandTemp      = "nand_temp"
    case fan0          = "fan_0"
    case fan1          = "fan_1"
    case cpuUsage      = "cpu_usage"
    case gpuUsage      = "gpu_usage"
    case batteryCharge = "battery_charge"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .socTemp:       return "SoC temp"
        case .batteryTemp:   return "Battery temp"
        case .nandTemp:      return "NAND temp"
        case .fan0:          return "Fan 1"
        case .fan1:          return "Fan 2"
        case .cpuUsage:      return "CPU %"
        case .gpuUsage:      return "GPU %"
        case .batteryCharge: return "Battery %"
        }
    }

    var symbol: String {
        switch self {
        case .cpuUsage:      return "cpu"
        case .gpuUsage:      return "display"
        case .socTemp:       return "memorychip"
        case .batteryTemp, .batteryCharge: return "battery.100"
        case .nandTemp:      return "internaldrive"
        case .fan0, .fan1:   return "fan"
        }
    }

    enum Unit { case celsius, rpm, percent }

    var unit: Unit {
        switch self {
        case .fan0, .fan1: return .rpm
        case .cpuUsage, .gpuUsage, .batteryCharge: return .percent
        default: return .celsius
        }
    }

    /// Higher is worse for these (warn/critical fire above the threshold).
    /// Battery charge is the opposite — handled separately in Thresholds.
    var higherIsWorse: Bool {
        self != .batteryCharge
    }
}

struct MenuBarStatConfig: Identifiable, Codable, Hashable {
    let stat: StatID
    var enabled: Bool

    var id: String { stat.rawValue }
}

extension Array where Element == MenuBarStatConfig {
    static var defaults: [MenuBarStatConfig] {
        // CPU usage always works (public API).
        StatID.allCases.map { id in
            MenuBarStatConfig(stat: id, enabled: id == .cpuUsage)
        }
    }
}
