import SwiftUI

/// Popup content shown when the user clicks the menu bar item. Sections
/// stack vertically; ScrollView in case the temperature list is long.
struct DetailsPopupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TemperaturesSection()
                    FansSection()
                    UsageSection()
                    BatterySection()
                }
                .padding(12)
            }
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 360, height: 520)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let ts = state.sampler.current?.timestamp {
                Text("Updated \(timestampString(ts))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(state.sampler.paused ? "Resume" : "Pause") {
                state.sampler.paused.toggle()
            }
            .buttonStyle(.borderless)
            Button {
                openSettings()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
    }

    private func timestampString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
