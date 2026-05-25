import SwiftUI

/// 6-pt colored circle indicating warn/critical state. Hidden when state is
/// `.ok` so unflagged rows stay quiet.
struct ThresholdDot: View {
    let state: ThresholdState

    var body: some View {
        if state == .ok {
            EmptyView()
        } else {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }
}
