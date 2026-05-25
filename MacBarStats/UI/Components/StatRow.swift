import SwiftUI

/// Single-line stat row used across all popup sections. Optional sparkline
/// appears between the label and value when `sparklineValues` has at least
/// two points.
struct StatRow: View {
    let symbol: String
    let label: String
    let value: String
    var state: ThresholdState = .ok
    var sparklineValues: [Double] = []

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(label)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !sparklineValues.isEmpty {
                Sparkline(values: sparklineValues)
                    .frame(width: 60)
                    .foregroundStyle(.tint)
            }
            Text(value)
                .monospacedDigit()
                .foregroundStyle(state == .ok ? .primary : state.color)
            ThresholdDot(state: state)
        }
        .font(.system(size: 12))
    }
}
