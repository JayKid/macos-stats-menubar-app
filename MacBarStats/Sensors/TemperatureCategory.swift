import Foundation

/// Curated buckets that we surface in the UI and let the user pick from in
/// the menu bar. Raw `IOHIDEventSystemClient` reports dozens of sensors with
/// repeated names (46 on the dev Mac), so we group them with fuzzy name
/// matching against the patterns observed in the spike output.
///
/// All ad-hoc string matching lives in `categorize(name:)`. If Apple renames
/// sensors on a future SoC, this is the one file to update.
enum TempCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpuPerf  = "CPU Performance"
    case cpuEff   = "CPU Efficiency"
    case gpu      = "GPU"
    case soc      = "SoC die"
    case battery  = "Battery"
    case nand     = "NAND"
    case ambient  = "Ambient"

    var id: String { rawValue }

    /// SF Symbol used in rows / menu bar.
    var symbol: String {
        switch self {
        case .cpuPerf, .cpuEff: return "cpu"
        case .gpu:              return "display"
        case .soc:              return "memorychip"
        case .battery:          return "battery.100"
        case .nand:             return "internaldrive"
        case .ambient:          return "thermometer"
        }
    }
}

enum TemperatureCategorizer {
    /// Map a raw sensor name to a curated category, or `nil` if no rule
    /// matches. Sensors with `nil` still appear in the popup under "Other"
    /// but aren't selectable in the menu bar.
    static func categorize(name: String) -> TempCategory? {
        let lower = name.lowercased()

        // CPU clusters. Apple's naming has historically used `pACC` for the
        // performance cluster and `eACC` for the efficiency cluster. Some
        // SoCs also expose names containing `perf`/`eff`.
        if lower.contains("pacc") || lower.contains("perf core") || lower.contains("pcore") {
            return .cpuPerf
        }
        if lower.contains("eacc") || lower.contains("ecore") || lower.contains("eff core") {
            return .cpuEff
        }

        if lower.contains("gpu") {
            return .gpu
        }

        if lower.contains("battery") || lower.contains("gas gauge") {
            return .battery
        }

        if lower.contains("nand") {
            return .nand
        }

        if lower.contains("ambient") || lower.contains("airflow") {
            return .ambient
        }

        // PMU sensors named `tdie*` / `tdev*` / `tcal` are SoC die thermistors.
        // Bucket them all as "SoC die" — we'll aggregate by max within the
        // category so it stays meaningful even with many sensors.
        if lower.contains("tdie") || lower.contains("tdev") || lower.contains("tcal") || lower.contains("pmu t") {
            return .soc
        }

        return nil
    }
}
