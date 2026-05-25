import Foundation
import SwiftUI

enum ThresholdState: Equatable {
    case ok, warn, critical

    var color: Color {
        switch self {
        case .ok:       return .secondary
        case .warn:     return .yellow
        case .critical: return .red
        }
    }
}

struct ThresholdPair: Codable, Hashable {
    var warn: Double?
    var critical: Double?
}

struct Thresholds: Codable, Hashable {
    var byStat: [StatID: ThresholdPair]

    static let `default`: Thresholds = .init(byStat: [
        // Temperature defaults from SPEC §8.
        .cpuPerfTemp: .init(warn: 85, critical: 95),
        .cpuEffTemp:  .init(warn: 85, critical: 95),
        .gpuTemp:     .init(warn: 85, critical: 95),
        .socTemp:     .init(warn: 85, critical: 95),
        // Battery low (lower-is-worse — handled inversely below).
        .batteryCharge: .init(warn: 20, critical: 10),
        // No defaults for the rest (off).
    ])

    func evaluate(_ stat: StatID, value: Double) -> ThresholdState {
        guard let pair = byStat[stat] else { return .ok }
        if stat.higherIsWorse {
            if let c = pair.critical, value >= c { return .critical }
            if let w = pair.warn,     value >= w { return .warn }
            return .ok
        } else {
            // Battery charge: lower is worse.
            if let c = pair.critical, value <= c { return .critical }
            if let w = pair.warn,     value <= w { return .warn }
            return .ok
        }
    }
}
