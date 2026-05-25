import Foundation
import Combine

/// Composition root. Owned by the `App` scene and injected via
/// `@EnvironmentObject` into all views.
///
/// `AppState` owns `Settings` and `Sampler` (both `ObservableObject`s) and
/// forwards their `objectWillChange` to its own publisher. Without that
/// forwarding, views observing `AppState` wouldn't redraw when something
/// inside `Settings` or `Sampler` published — they'd be observing the
/// wrong object.
@MainActor
final class AppState: ObservableObject {
    let settings: Settings
    let sampler: Sampler

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = Settings()
        let bundle = SensorBundle()
        let sampler = Sampler(settings: settings, bundle: bundle)
        self.settings = settings
        self.sampler = sampler

        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sampler.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // First-launch login-item opt-in (per SPEC §9): default on, but only
        // attempted once — if the user turns it off later, we don't re-prompt.
        if !settings.didOnboardLoginItem {
            settings.didOnboardLoginItem = true
            _ = LoginItem.setEnabled(true)
        }

        sampler.start()
    }
}
