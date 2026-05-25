import Foundation

/// Curated buckets that we surface in the UI. Raw `IOHIDEventSystemClient`
/// reports dozens of sensors with repeated names (46 on the dev Mac), so we
/// group them with fuzzy name matching against the patterns observed in the
/// spike output.
///
/// On Apple Silicon, most sensors are die-level (PMU tdie*) — there are no
/// separate CPU performance / CPU efficiency / GPU temperature zones exposed
/// via the HID API, so those categories were removed.
///
/// All ad-hoc string matching lives in `categorize(name:)`. If Apple renames
/// sensors on a future SoC, this is the one file to update.
enum TempCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case soc      = "SoC die"
    case battery  = "Battery"
    case nand     = "NAND"

    var id: String { rawValue }

    /// SF Symbol used in rows.
    var symbol: String {
        switch self {
        case .soc:     return "memorychip"
        case .battery: return "battery.100"
        case .nand:    return "internaldrive"
        }
    }
}

enum TemperatureCategorizer {
    /// Map a raw sensor name to a curated category, or `nil` if no rule
    /// matches. Sensors with `nil` still appear in the popup under "Other".
    static func categorize(name: String) -> TempCategory? {
        let lower = name.lowercased()

        if lower.contains("battery") || lower.contains("gas gauge") {
            return .battery
        }

        if lower.contains("nand") {
            return .nand
        }

        // PMU sensors named `tdie*` / `tdev*` / `tcal` are SoC die thermistors.
        // This is the most common sensor type on Apple Silicon; there are no
        // separate CPU/GPU temperature zones.
        if lower.contains("tdie") || lower.contains("tdev") || lower.contains("tcal") || lower.contains("pmu t") {
            return .soc
        }

        return nil
    }
}
