import Foundation
import Combine

/// Drives the periodic sensor read, publishes `current` + `history` for the
/// UI to observe. Settings changes (sampling interval, history window) take
/// effect on the next tick.
///
/// Sample reads are performed on the main actor; they're fast (a few
/// milliseconds typically), and keeping everything single-actor avoids the
/// Sendable-conformance churn of pushing IOKit/SMC objects across actors.
@MainActor
final class Sampler: ObservableObject {

    @Published private(set) var current: Snapshot?
    @Published private(set) var history: RingBuffer<Snapshot>
    @Published var paused: Bool = false {
        didSet { paused ? stop() : start() }
    }

    private let bundle: SensorBundle
    private let settings: Settings
    private var task: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: Settings, bundle: SensorBundle) {
        self.settings = settings
        self.bundle = bundle
        self.history = RingBuffer(capacity: Self.capacity(for: settings))

        // Re-size the buffer when interval/window change. The loop's next
        // wake-up picks up the new interval naturally. We hop back to the
        // main actor inside the sink callback because under Swift 6 strict
        // concurrency, Combine sinks aren't statically known to be main-
        // isolated even when `receive(on:)` schedules them there.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let desired = Self.capacity(for: self.settings)
                    if desired != self.history.capacity {
                        self.history.setCapacity(desired)
                    }
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let snap = self.bundle.sample()
                self.current = snap
                self.history.append(snap)

                let interval = self.settings.samplingIntervalSeconds
                let ns = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func capacity(for settings: Settings) -> Int {
        let windowSeconds = settings.historyWindowMinutes * 60
        let perSample = max(1, settings.samplingIntervalSeconds)
        return max(1, Int((windowSeconds / perSample).rounded(.up)))
    }
}
