import SwiftUI

/// The label shown in the system menu bar. Renders each enabled stat as
/// "<icon> <value>", with per-stat foreground color flipped to yellow/red
/// when its threshold is tripped.
///
/// We render `Text` rather than mixing in `Image(systemName:)` because some
/// SF Symbols don't size well inside `MenuBarExtra` labels — a single
/// thermometer prefix gives reliable layout while still telegraphing "this
/// is the temperature app."
struct MenuBarItemView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: leadingSymbol)
            ForEach(enabledStats, id: \.id) { config in
                statView(for: config.stat)
            }
            if enabledStats.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
    }

    private var enabledStats: [MenuBarStatConfig] {
        state.settings.menuBarStats.filter(\.enabled)
    }

    /// The lead symbol gives the menu bar a recognizable shape regardless of
    /// which stats are enabled.
    private var leadingSymbol: String {
        enabledStats.first?.stat.symbol ?? "thermometer"
    }

    @ViewBuilder
    private func statView(for stat: StatID) -> some View {
        if let snap = state.sampler.current, let value = snap.value(for: stat) {
            let evaluated = state.settings.thresholds.evaluate(stat, value: value)
            Text(stat.format(value))
                .foregroundStyle(color(for: evaluated))
        } else {
            Text("—")
                .foregroundStyle(.secondary)
        }
    }

    private func color(for state: ThresholdState) -> Color {
        switch state {
        case .ok:       return .primary
        case .warn:     return .yellow
        case .critical: return .red
        }
    }
}
