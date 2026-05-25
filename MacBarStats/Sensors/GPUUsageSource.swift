import Foundation

/// GPU "busy %" derived from the `IOReport` `PWRCTRL` state channel in the
/// `GPU Stats` group (subgroup `GPU Power Controller States`).
///
/// Caveat — this is **power-state residency**, not compute load. The GPU
/// stays in the `PERF` state to drive the display compositor even on an
/// otherwise idle system, so the baseline reads 50–70 % when nothing is
/// happening. The value DOES respond to real workloads (drops further
/// toward zero when display sleeps; pegs near 100 % under sustained Metal
/// load). A future revision can swap in `IORegistry → AGXAccelerator →
/// PerformanceStatistics` for an actual compute-load metric.
///
/// Initialization fails (returns `nil`) if `libIOReport.dylib` can't be
/// loaded or the symbols/channel can't be resolved. The Sampler treats a
/// `nil` source as "GPU section disabled," which is exactly what we want
/// on a Mac where IOReport drifts (e.g., a new SoC generation).
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

        var total: Int64 = 0
        var idle: Int64 = 0
        ior.iterate(delta, { ch in
            guard cfStr(ior.getChannelName(ch)) == "PWRCTRL" else { return 0 }
            guard ior.getFormat(ch) == 2 else { return 0 }
            let count = ior.stateCount(ch)
            guard count > 0 else { return 0 }
            for i in 0..<count {
                let n = cfStr(ior.stateName(ch, i))
                let r = ior.stateRes(ch, i)
                total &+= r
                if n == "IDLE_OFF" { idle &+= r }
            }
            return 0
        })

        guard total > 0 else { return GPUReading(busy: 0) }
        let busy = 1 - Double(idle) / Double(total)
        return GPUReading(busy: max(0, min(1, busy)))
    }
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
