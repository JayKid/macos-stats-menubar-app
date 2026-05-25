import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            MenuBarTab()
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
            ThresholdsTab()
                .tabItem { Label("Thresholds", systemImage: "exclamationmark.triangle") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}
