import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @State private var loginItemEnabled: Bool = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Sampling interval") {
                    VStack(alignment: .trailing) {
                        Slider(
                            value: Binding(
                                get: { state.settings.samplingIntervalSeconds },
                                set: { state.settings.samplingIntervalSeconds = Settings.clampInterval($0) }
                            ),
                            in: 1...30,
                            step: 1
                        )
                        Text("\(Int(state.settings.samplingIntervalSeconds)) s")
                            .font(.callout)
                            .monospacedDigit()
                    }
                }
                LabeledContent("History window") {
                    VStack(alignment: .trailing) {
                        Slider(
                            value: Binding(
                                get: { state.settings.historyWindowMinutes },
                                set: { state.settings.historyWindowMinutes = Settings.clampWindow($0) }
                            ),
                            in: 1...60,
                            step: 1
                        )
                        Text("\(Int(state.settings.historyWindowMinutes)) min")
                            .font(.callout)
                            .monospacedDigit()
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItemEnabled },
                    set: { newValue in
                        switch LoginItem.setEnabled(newValue) {
                        case .success:
                            loginItemEnabled = newValue
                            loginItemError = nil
                        case .failure(let err):
                            loginItemError = err.localizedDescription
                        }
                    }
                ))
                if let err = loginItemError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
    }
}
