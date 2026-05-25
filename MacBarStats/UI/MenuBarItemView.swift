import SwiftUI
import AppKit

/// Menu bar label.
///
/// **Why this isn't just an HStack of `Image` + `Text` views.**
/// `MenuBarExtra`'s label closure is rendered into an `NSStatusItem`, which
/// expects either a single `NSImage` or a plain string. Real SwiftUI views
/// inside the closure get partially flattened:
///
/// - A standalone `Image` at the root renders as the status item's image.
/// - `Text(Image(systemName:))` collapses to text only — the inline symbol
///   is dropped (this is what gave us "no icons at all" in an earlier try).
/// - `HStack { Image; Text; Image; Text }` typically renders only the first
///   image and concatenated text — every image after the first disappears
///   (this is what gave us "only the first icon" symptom).
///
/// To get reliable multi-icon layout, we render the rich HStack into an
/// `NSImage` ourselves via `ImageRenderer` and hand that single image to
/// `MenuBarExtra` — the same workaround documented in Apple's Developer
/// Forums and used by most production menu bar apps.
///
/// Colors are preserved because we mark the resulting image as
/// non-template, so the system doesn't re-tint it. The trade-off: we have
/// to react explicitly to light/dark mode changes — which we do by
/// reading `@Environment(\.colorScheme)` so SwiftUI re-evaluates `body`
/// (and therefore re-renders the image) when the system theme flips.
struct MenuBarItemView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let img = renderLabelImage() {
            Image(nsImage: img)
        } else {
            // Pre-first-sample fallback: a static symbol so the menu bar
            // always has something to click.
            Image(systemName: "thermometer")
        }
    }

    // MARK: - Rendering

    @MainActor
    private func renderLabelImage() -> NSImage? {
        let renderer = ImageRenderer(content: labelContent)
        // Render at the screen's backing scale so the symbols stay crisp on
        // Retina; fall back to 2× for safety.
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // Non-template so our threshold yellow/red survives — the system
        // would tint a template image and erase the warn/critical colors.
        // Light/dark adaptation is handled in `color(for:)`, which reads
        // `colorScheme`; `body` re-evaluates when it flips.
        image.isTemplate = false
        return image
    }

    /// The view tree that becomes the menu bar pixels. SwiftUI is already
    /// subscribed to `colorScheme` via the `@Environment` declaration above,
    /// so `body` re-evaluates (and we re-render the image) whenever the
    /// system theme flips.
    private var labelContent: some View {
        HStack(spacing: 6) {
            if enabledStats.isEmpty || state.sampler.current == nil {
                Image(systemName: "thermometer")
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(enabledStats) { config in
                    statCell(for: config)
                }
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func statCell(for config: MenuBarStatConfig) -> some View {
        if let snap = state.sampler.current,
           let value = snap.value(for: config.stat) {
            let evaluated = state.settings.thresholds.evaluate(config.stat, value: value)
            HStack(spacing: 3) {
                Image(systemName: config.stat.symbol)
                Text(config.stat.format(value))
            }
            .foregroundStyle(color(for: evaluated))
        }
    }

    private var enabledStats: [MenuBarStatConfig] {
        state.settings.menuBarStats.filter(\.enabled)
    }

    private func color(for state: ThresholdState) -> Color {
        switch state {
        case .ok:       return colorScheme == .dark ? .white : .black
        case .warn:     return .yellow
        case .critical: return .red
        }
    }
}
