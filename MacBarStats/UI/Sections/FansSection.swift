import SwiftUI

/// One row per fan. Section is hidden entirely when `fans.isEmpty`
/// (MacBook Air, desktop without fans, etc.).
struct FansSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let snap = state.sampler.current, !snap.fans.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fans")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                let series = state.sampler.history.toArray()
                ForEach(snap.fans) { fan in
                    let stat: StatID = fan.id == 0 ? .fan0 : .fan1
                    StatRow(
                        symbol: "fan",
                        label: "Fan \(fan.id + 1)",
                        value: "\(Int(fan.actualRPM.rounded())) / \(Int(fan.targetRPM.rounded())) RPM",
                        state: state.settings.thresholds.evaluate(stat, value: fan.actualRPM),
                        sparklineValues: series.series(for: stat)
                    )
                }
            }
        }
    }
}
