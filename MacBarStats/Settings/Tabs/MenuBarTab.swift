import SwiftUI

struct MenuBarTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            previewRow

            Divider()

            Text("Stats")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            List {
                ForEach(state.settings.menuBarStats) { config in
                    HStack {
                        Image(systemName: config.stat.symbol)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(config.stat.label)
                        Spacer()
                        Toggle("", isOn: binding(for: config))
                            .labelsHidden()
                    }
                }
                .onMove(perform: move)
            }
            .listStyle(.inset)
        }
        .padding(12)
        .frame(width: 420, height: 480)
    }

    private var previewRow: some View {
        MenuBarItemView()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(6)
    }

    private func binding(for config: MenuBarStatConfig) -> Binding<Bool> {
        Binding(
            get: {
                state.settings.menuBarStats.first(where: { $0.id == config.id })?.enabled ?? false
            },
            set: { new in
                guard let idx = state.settings.menuBarStats.firstIndex(where: { $0.id == config.id }) else { return }
                state.settings.menuBarStats[idx].enabled = new
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        state.settings.menuBarStats.move(fromOffsets: source, toOffset: destination)
    }
}
