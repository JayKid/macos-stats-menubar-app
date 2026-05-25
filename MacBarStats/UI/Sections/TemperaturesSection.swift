import SwiftUI

/// Rows grouped by `TempCategory`. Each row shows the max-within-category
/// value with a sparkline. Sensors that don't fit any category appear under
/// "Other" at the bottom.
struct TemperaturesSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let snap = state.sampler.current {
            VStack(alignment: .leading, spacing: 4) {
                Text("Temperatures")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(rows(for: snap), id: \.stat) { row in
                    StatRow(
                        symbol: row.symbol,
                        label: row.label,
                        value: row.value,
                        state: row.state,
                        sparklineValues: row.sparkline
                    )
                }
                let extras = uncategorized(in: snap)
                if !extras.isEmpty {
                    DisclosureGroup("Other (\(extras.count))") {
                        ForEach(extras) { r in
                            StatRow(
                                symbol: "thermometer",
                                label: r.rawName,
                                value: String(format: "%.1f°", r.celsius)
                            )
                        }
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }

    private struct Row {
        let stat: StatID
        let symbol: String
        let label: String
        let value: String
        let state: ThresholdState
        let sparkline: [Double]
    }

    private func rows(for snap: Snapshot) -> [Row] {
        let series = state.sampler.history.toArray()
        let categories: [(TempCategory, StatID)] = [
            (.soc,     .socTemp),
            (.battery, .batteryTemp),
            (.nand,    .nandTemp),
        ]
        return categories.compactMap { (cat, stat) in
            guard let v = snap.value(for: stat) else { return nil }
            return Row(
                stat: stat,
                symbol: cat.symbol,
                label: cat.rawValue,
                value: stat.format(v),
                state: state.settings.thresholds.evaluate(stat, value: v),
                sparkline: series.series(for: stat)
            )
        }
    }

    private func uncategorized(in snap: Snapshot) -> [TemperatureReading] {
        snap.temperatures.filter { $0.category == nil }
            .sorted { $0.rawName < $1.rawName }
    }
}
