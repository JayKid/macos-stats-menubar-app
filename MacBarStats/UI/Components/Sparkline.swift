import SwiftUI
import Charts

/// A compact line chart with hidden axes, suitable for inline use in stat
/// rows. Pass a non-empty `[Double]`; an empty array renders nothing.
struct Sparkline: View {
    let values: [Double]
    var height: CGFloat = 18

    var body: some View {
        if values.count < 2 {
            // Need at least two points for a line.
            Color.clear.frame(height: height)
        } else {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                    LineMark(
                        x: .value("i", idx),
                        y: .value("v", v)
                    )
                    .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: height)
        }
    }
}
