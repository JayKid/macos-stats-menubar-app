import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "thermometer")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)

            Text("MacBarStats")
                .font(.system(size: 16, weight: .semibold))

            Text("Version \(version)")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Link("github.com/JayKid/macos-stats-menubar-app",
                 destination: URL(string: "https://github.com/JayKid/macos-stats-menubar-app")!)
                .font(.callout)

            Spacer()
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .frame(width: 420, height: 320)
    }

    private var version: String {
        let dict = Bundle.main.infoDictionary
        let short = dict?["CFBundleShortVersionString"] as? String ?? "?"
        let build = dict?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
