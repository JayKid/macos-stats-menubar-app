import SwiftUI

/// Aggregate CPU and GPU usage with sparklines, plus per-core CPU bars.
/// GPU row is hidden when the source is unavailable.
struct UsageSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let snap = state.sampler.current {
            let series = state.sampler.history.toArray()
            VStack(alignment: .leading, spacing: 6) {
                Text("Usage")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                let cpuPct = snap.cpu.aggregate * 100
                StatRow(
                    symbol: "cpu",
                    label: "CPU",
                    value: String(format: "%.0f%%", cpuPct),
                    state: state.settings.thresholds.evaluate(.cpuUsage, value: cpuPct),
                    sparklineValues: series.series(for: .cpuUsage)
                )

                // Per-core bars
                if !snap.cpu.perCore.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(snap.cpu.perCore.enumerated()), id: \.offset) { _, v in
                            GeometryReader { proxy in
                                ZStack(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.15))
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(height: proxy.size.height * CGFloat(max(0, min(1, v))))
                                }
                            }
                            .frame(height: 18)
                            .cornerRadius(1.5)
                        }
                    }
                    .padding(.leading, 22) // align under the label column
                }

                if let gpu = snap.gpu {
                    let gpuPct = gpu.busy * 100
                    StatRow(
                        symbol: "display",
                        label: "GPU",
                        value: String(format: "%.0f%%", gpuPct),
                        state: state.settings.thresholds.evaluate(.gpuUsage, value: gpuPct),
                        sparklineValues: series.series(for: .gpuUsage)
                    )
                }
            }
        }
    }
}
