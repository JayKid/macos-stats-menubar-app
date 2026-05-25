import SwiftUI

/// Battery info row. Hidden when `battery == nil` (no battery present).
struct BatterySection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let snap = state.sampler.current, let b = snap.battery {
            VStack(alignment: .leading, spacing: 4) {
                Text("Battery")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                let chargePct = b.charge * 100
                StatRow(
                    symbol: symbol(for: b.state),
                    label: stateLabel(b),
                    value: String(format: "%.0f%%", chargePct),
                    state: state.settings.thresholds.evaluate(.batteryCharge, value: chargePct),
                    sparklineValues: state.sampler.history.toArray().series(for: .batteryCharge)
                )

                HStack(spacing: 12) {
                    if let cycles = b.cycleCount {
                        meta(label: "Cycles", value: "\(cycles)")
                    }
                    if let health = b.health {
                        meta(label: "Health", value: String(format: "%.0f%%", health * 100))
                    }
                    if let wattage = b.wattage {
                        meta(label: "Power", value: String(format: "%.1f W", wattage))
                    }
                    if let mins = b.timeRemainingMinutes {
                        meta(label: "Time", value: formatMinutes(mins))
                    }
                }
                .padding(.leading, 22)
            }
        }
    }

    private func meta(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11))
                .monospacedDigit()
        }
    }

    private func symbol(for state: BatteryReading.State) -> String {
        switch state {
        case .charging:    return "bolt.fill"
        case .discharging: return "battery.50"
        case .full:        return "battery.100"
        case .unknown:     return "battery.0"
        }
    }

    private func stateLabel(_ b: BatteryReading) -> String {
        switch b.state {
        case .charging:    return "Charging"
        case .discharging: return "On battery"
        case .full:        return "Plugged in"
        case .unknown:     return "Battery"
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        let h = m / 60
        let r = m % 60
        return h > 0 ? "\(h)h \(r)m" : "\(r)m"
    }
}
