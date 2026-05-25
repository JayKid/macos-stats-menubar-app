import Foundation

/// GPU "busy %" derived from IOReport state channels in the `"GPU Stats"`
/// group.
///
/// We try two channels in order of community preference:
///
/// 1. `GPUPH` in subgroup `"GPU Performance States"` — the channel macmon /
///    btop / mactop all use. P-state residency by frequency bucket. Present
///    on most M1/M2/M3/M4 Macs.
/// 2. `PWRCTRL` in subgroup `"GPU Power Controller States"` — older path,
///    still surfaced on Apple Silicon. Used when GPUPH isn't subscribable
///    (the dev MacBook Pro this app was written on falls into this case).
///
/// The set of "idle" state names varies by SoC generation: macOS uses
/// `IDLE_OFF` on some Macs, `OFF` on M4-class chips, `IDLE`/`DOWN` on
/// M2/M3 Max. We match any of `{OFF, IDLE, IDLE_OFF, DOWN, SW_OFF}`
/// case-insensitively so a future SoC rename doesn't silently zero out the
/// reading.
///
/// **Important caveat about the number itself.** macmon and similar tools
/// derive a frequency-weighted busy ratio (residency × per-state frequency,
/// normalized to the max frequency) because macOS parks the GPU at P1 for
/// display compositing 40–60 % of the time — so plain
/// `1 - idle/total` overestimates by ~3–5× on most Macs. We use the plain
/// form for v1 simplicity; expect baseline values of 50–70 % when the
/// system is "idle." Switching to frequency-weighting (or using
/// `IORegistry → AGXAccelerator → PerformanceStatistics["Device Utilization %"]`,
/// which is what exelban/stats reads) is the obvious next step if numbers
/// feel off.
///
/// Initialization fails (returns `nil`) if `libIOReport.dylib` can't be
/// loaded or no channels in the group can be subscribed. The Sampler
/// treats a `nil` source as "GPU section disabled," which is exactly what
/// we want on a Mac where IOReport drifts.
final class GPUUsageSource {

    private let ior: IORBindings
    private let subscription: OpaquePointer
    private let subscribedChannels: CFMutableDictionary
    private var previousSample: CFDictionary?

    init?() {
        guard let ior = IORBindings.load() else { return nil }
        self.ior = ior

        guard let channelsRef = ior.copyChannels("GPU Stats" as CFString, nil, 0, 0, 0) else {
            return nil
        }
        let channels = channelsRef.takeRetainedValue()

        var subbed: Unmanaged<CFMutableDictionary>? = nil
        guard let sub = ior.createSub(nil, channels, &subbed, 0, nil),
              let subbedChannels = subbed?.takeRetainedValue() else {
            return nil
        }
        self.subscription = sub
        self.subscribedChannels = subbedChannels
    }

    func read() -> GPUReading? {
        guard let curRef = ior.createSamples(subscription, subscribedChannels, nil) else {
            return nil
        }
        let cur = curRef.takeRetainedValue()
        defer { previousSample = cur }

        // First call has nothing to delta against.
        guard let previousSample else { return GPUReading(busy: 0) }

        guard let deltaRef = ior.createDelta(previousSample, cur, nil) else {
            return nil
        }
        let delta = deltaRef.takeRetainedValue()

        // Collect residency from BOTH known channels in one iteration pass,
        // then prefer GPUPH (community-standard) if it produced data, else
        // fall back to PWRCTRL.
        var gpuphTotal: Int64 = 0,   gpuphIdle: Int64 = 0
        var pwrctrlTotal: Int64 = 0, pwrctrlIdle: Int64 = 0

        ior.iterate(delta, { ch in
            guard ior.getFormat(ch) == 2 else { return 0 } // state channels only
            let name = cfStr(ior.getChannelName(ch))
            guard name == "GPUPH" || name == "PWRCTRL" else { return 0 }

            let count = ior.stateCount(ch)
            guard count > 0 else { return 0 }
            for i in 0..<count {
                let state = cfStr(ior.stateName(ch, i)).uppercased()
                let r = ior.stateRes(ch, i)
                let isIdle = Self.idleStateNames.contains(state)
                if name == "GPUPH" {
                    gpuphTotal &+= r
                    if isIdle { gpuphIdle &+= r }
                } else {
                    pwrctrlTotal &+= r
                    if isIdle { pwrctrlIdle &+= r }
                }
            }
            return 0
        })

        let (total, idle) = gpuphTotal > 0
            ? (gpuphTotal, gpuphIdle)
            : (pwrctrlTotal, pwrctrlIdle)
        guard total > 0 else { return GPUReading(busy: 0) }
        let busy = 1 - Double(idle) / Double(total)
        return GPUReading(busy: max(0, min(1, busy)))
    }

    /// Idle state names observed across Apple Silicon generations:
    /// - `IDLE_OFF` — PWRCTRL on the dev MacBook Pro (M-series)
    /// - `OFF`     — M4-class chips (per shm11C3 tests)
    /// - `IDLE` / `DOWN` — M2 / M3 Max (per macmon's calc_freq comment)
    /// - `SW_OFF`  — appears in some Apple registry filters alongside IDLE_OFF
    /// Match case-insensitively — uppercased here for the `.contains` check.
    private static let idleStateNames: Set<String> = [
        "OFF", "IDLE", "IDLE_OFF", "DOWN", "SW_OFF"
    ]
}

// MARK: - dlsym bindings (private framework / public symbols)

private typealias IOReportCopyChannelsInGroupFn = @convention(c) (
    CFString?, CFString?, UInt64, UInt64, UInt64
) -> Unmanaged<CFMutableDictionary>?

private typealias IOReportCreateSubscriptionFn = @convention(c) (
    UnsafeMutableRawPointer?, CFMutableDictionary,
    UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
    UInt64, CFTypeRef?
) -> OpaquePointer?

private typealias IOReportCreateSamplesFn = @convention(c) (
    OpaquePointer, CFMutableDictionary, CFTypeRef?
) -> Unmanaged<CFDictionary>?

private typealias IOReportCreateSamplesDeltaFn = @convention(c) (
    CFDictionary, CFDictionary, CFTypeRef?
) -> Unmanaged<CFDictionary>?

private typealias IOReportIterateCallback = @convention(block) (CFDictionary) -> Int32
private typealias IOReportIterateFn = @convention(c) (CFDictionary, IOReportIterateCallback) -> Void

private typealias CFDictToCFStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
private typealias IOReportChannelGetFormatFn = @convention(c) (CFDictionary) -> Int32
private typealias IOReportStateGetCountFn = @convention(c) (CFDictionary) -> Int32
private typealias IOReportStateGetNameForIndexFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
private typealias IOReportStateGetResidencyFn = @convention(c) (CFDictionary, Int32) -> Int64

private struct IORBindings {
    let copyChannels: IOReportCopyChannelsInGroupFn
    let createSub: IOReportCreateSubscriptionFn
    let createSamples: IOReportCreateSamplesFn
    let createDelta: IOReportCreateSamplesDeltaFn
    let iterate: IOReportIterateFn
    let getChannelName: CFDictToCFStringFn
    let getFormat: IOReportChannelGetFormatFn
    let stateCount: IOReportStateGetCountFn
    let stateName: IOReportStateGetNameForIndexFn
    let stateRes: IOReportStateGetResidencyFn

    static func load() -> IORBindings? {
        let candidates = [
            "/usr/lib/libIOReport.dylib",
            "/System/Library/PrivateFrameworks/IOReport.framework/IOReport",
            "/System/Library/Frameworks/IOReport.framework/IOReport",
        ]
        var handle: UnsafeMutableRawPointer?
        for p in candidates {
            if let h = dlopen(p, RTLD_LAZY) { handle = h; break }
        }
        guard let handle else { return nil }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard
            let cc = sym("IOReportCopyChannelsInGroup", IOReportCopyChannelsInGroupFn.self),
            let cs = sym("IOReportCreateSubscription", IOReportCreateSubscriptionFn.self),
            let cr = sym("IOReportCreateSamples", IOReportCreateSamplesFn.self),
            let cd = sym("IOReportCreateSamplesDelta", IOReportCreateSamplesDeltaFn.self),
            let it = sym("IOReportIterate", IOReportIterateFn.self),
            let gn = sym("IOReportChannelGetChannelName", CFDictToCFStringFn.self),
            let gf = sym("IOReportChannelGetFormat", IOReportChannelGetFormatFn.self),
            let sc = sym("IOReportStateGetCount", IOReportStateGetCountFn.self),
            let sn = sym("IOReportStateGetNameForIndex", IOReportStateGetNameForIndexFn.self),
            let sr = sym("IOReportStateGetResidency", IOReportStateGetResidencyFn.self)
        else { return nil }
        return IORBindings(
            copyChannels: cc, createSub: cs, createSamples: cr, createDelta: cd,
            iterate: it, getChannelName: gn, getFormat: gf,
            stateCount: sc, stateName: sn, stateRes: sr
        )
    }
}

private func cfStr(_ u: Unmanaged<CFString>?) -> String {
    guard let u else { return "" }
    return u.takeUnretainedValue() as String
}
