import SwiftUI

@main
struct MacBarStatsApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            DetailsPopupView()
                .environmentObject(state)
        } label: {
            MenuBarItemView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
