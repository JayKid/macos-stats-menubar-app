import Foundation
import Combine

/// User preferences, persisted to `UserDefaults`.
///
/// Simple scalars are stored under stable keys with `didSet` observers that
/// write through immediately. Complex structures (`menuBarStats` and
/// `thresholds`) round-trip as JSON to keep the keys human-readable in
/// `defaults read dev.joselopez.MacBarStats`.
@MainActor
final class Settings: ObservableObject {

    // MARK: - Tunables

    @Published var samplingIntervalSeconds: Double {
        didSet { defaults.set(samplingIntervalSeconds, forKey: K.interval) }
    }

    @Published var historyWindowMinutes: Double {
        didSet { defaults.set(historyWindowMinutes, forKey: K.window) }
    }

    @Published var didOnboardLoginItem: Bool {
        didSet { defaults.set(didOnboardLoginItem, forKey: K.didOnboard) }
    }

    @Published var menuBarStats: [MenuBarStatConfig] {
        didSet { saveCodable(menuBarStats, key: K.menuBar) }
    }

    @Published var thresholds: Thresholds {
        didSet { saveCodable(thresholds, key: K.thresholds) }
    }

    // MARK: - Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.object(forKey: K.interval) as? Double
        self.samplingIntervalSeconds = Self.clampInterval(storedInterval ?? 5)

        let storedWindow = defaults.object(forKey: K.window) as? Double
        self.historyWindowMinutes = Self.clampWindow(storedWindow ?? 15)

        self.didOnboardLoginItem = defaults.bool(forKey: K.didOnboard)

        // For menuBarStats and thresholds we use lossy decoding: if the
        // persisted JSON contains entries for an obsolete StatID (e.g., a
        // category we removed in a later version), strict Codable would
        // fail the whole decode and reset the user's config to defaults.
        // Lossy decoding parses the JSON manually and skips unknown
        // entries, so the user keeps the rest of their preferences.

        if let data = defaults.data(forKey: K.menuBar),
           let decoded = Self.decodeMenuBarStatsLossily(data: data),
           !decoded.isEmpty {
            // Merge in any new StatIDs that didn't exist when the user last saved.
            var merged = decoded
            let existing = Set(decoded.map(\.stat))
            for new in [MenuBarStatConfig].defaults where !existing.contains(new.stat) {
                merged.append(new)
            }
            self.menuBarStats = merged
        } else {
            self.menuBarStats = .defaults
        }

        if let data = defaults.data(forKey: K.thresholds),
           let decoded = Self.decodeThresholdsLossily(data: data) {
            self.thresholds = decoded
        } else {
            self.thresholds = .default
        }
    }

    // MARK: - Lossy decoders

    private static func decodeMenuBarStatsLossily(data: Data) -> [MenuBarStatConfig]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        var result: [MenuBarStatConfig] = []
        for entry in json {
            guard let rawStat = entry["stat"] as? String,
                  let stat = StatID(rawValue: rawStat),
                  let enabled = entry["enabled"] as? Bool else {
                continue // drop entries whose `stat` we no longer recognize
            }
            result.append(MenuBarStatConfig(stat: stat, enabled: enabled))
        }
        return result
    }

    private static func decodeThresholdsLossily(data: Data) -> Thresholds? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byStatJSON = json["byStat"] as? [String: [String: Any]] else {
            return nil
        }
        var byStat: [StatID: ThresholdPair] = [:]
        for (rawStat, pair) in byStatJSON {
            guard let stat = StatID(rawValue: rawStat) else { continue }
            byStat[stat] = ThresholdPair(
                warn: pair["warn"] as? Double,
                critical: pair["critical"] as? Double
            )
        }
        return Thresholds(byStat: byStat)
    }

    // MARK: - Clamping

    static func clampInterval(_ v: Double) -> Double { max(1, min(30, v)) }
    static func clampWindow(_ v: Double) -> Double   { max(1, min(60, v)) }

    // MARK: - Persistence

    private func saveCodable<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private enum K {
        static let interval   = "sampling.intervalSeconds"
        static let window     = "history.windowMinutes"
        static let didOnboard = "loginItem.didOnboard"
        static let menuBar    = "menuBar.stats.v1"
        static let thresholds = "thresholds.v1"
    }
}
