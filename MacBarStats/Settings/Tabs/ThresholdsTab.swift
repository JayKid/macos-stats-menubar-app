import SwiftUI

struct ThresholdsTab: View {
    @EnvironmentObject var state: AppState

    private let rows: [StatID] = [
        .socTemp, .batteryTemp, .nandTemp,
        .cpuUsage, .gpuUsage, .batteryCharge,
        .fan0, .fan1,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Set warn/critical values per stat. Leave blank to disable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore defaults") {
                    state.settings.thresholds = .default
                }
            }

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        Text("Stat")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Warn")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Critical")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Unit")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Divider().gridCellColumns(4)

                    ForEach(rows) { stat in
                        GridRow {
                            HStack {
                                Image(systemName: stat.symbol)
                                    .frame(width: 14)
                                    .foregroundStyle(.secondary)
                                Text(stat.label)
                            }
                            thresholdField(stat: stat, kind: .warn)
                            thresholdField(stat: stat, kind: .critical)
                            Text(unitLabel(stat))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 460, height: 480)
    }

    private enum FieldKind { case warn, critical }

    @ViewBuilder
    private func thresholdField(stat: StatID, kind: FieldKind) -> some View {
        TextField("", value: Binding<Double?>(
            get: {
                let pair = state.settings.thresholds.byStat[stat] ?? .init()
                switch kind {
                case .warn:     return pair.warn
                case .critical: return pair.critical
                }
            },
            set: { newValue in
                var p = state.settings.thresholds.byStat[stat] ?? .init()
                switch kind {
                case .warn:     p.warn = newValue
                case .critical: p.critical = newValue
                }
                if p.warn == nil && p.critical == nil {
                    state.settings.thresholds.byStat.removeValue(forKey: stat)
                } else {
                    state.settings.thresholds.byStat[stat] = p
                }
            }
        ), format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(width: 80)
    }

    private func unitLabel(_ stat: StatID) -> String {
        switch stat.unit {
        case .celsius: return "°C"
        case .rpm:     return "RPM"
        case .percent: return "%"
        }
    }
}
