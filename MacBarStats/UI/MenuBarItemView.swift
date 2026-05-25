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
            if enabledStats.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                statsText
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
    }

    private var enabledStats: [MenuBarStatConfig] {
        state.settings.menuBarStats.filter(\.enabled)
    }

    private var leadingSymbol: String {
        enabledStats.first?.stat.symbol ?? "thermometer"
    }

    private var statsText: Text {
        guard let snap = state.sampler.current else {
            return Text("—").foregroundStyle(.secondary)
        }
        var result: Text?
        for config in enabledStats {
            guard let value = snap.value(for: config.stat) else { continue }
            let evaluated = state.settings.thresholds.evaluate(config.stat, value: value)
            let segment = Text(config.stat.format(value))
                .foregroundStyle(color(for: evaluated))
            result = result.map { $0 + Text("  ") + segment } ?? segment
        }
        return result ?? Text("—").foregroundStyle(.secondary)
    }

    private func color(for state: ThresholdState) -> Color {
        switch state {
        case .ok:       return .primary
        case .warn:     return .yellow
        case .critical: return .red
        }
    }
}
