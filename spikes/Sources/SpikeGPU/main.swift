import Foundation

private func stderrPrint(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

// MARK: - IOReport bindings (resolved via dlsym)

private typealias IOReportSubscriptionRef = OpaquePointer

private typealias IOReportCopyChannelsInGroupFn = @convention(c) (
    CFString?, CFString?, UInt64, UInt64, UInt64
) -> Unmanaged<CFMutableDictionary>?

private typealias IOReportCreateSubscriptionFn = @convention(c) (
    UnsafeMutableRawPointer?, CFMutableDictionary,
    UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
    UInt64, CFTypeRef?
) -> IOReportSubscriptionRef?

private typealias IOReportCreateSamplesFn = @convention(c) (
    IOReportSubscriptionRef, CFMutableDictionary, CFTypeRef?
) -> Unmanaged<CFDictionary>?

private typealias IOReportCreateSamplesDeltaFn = @convention(c) (
    CFDictionary, CFDictionary, CFTypeRef?
) -> Unmanaged<CFDictionary>?

private typealias IOReportIterateCallback = @convention(block) (CFDictionary) -> Int32
private typealias IOReportIterateFn = @convention(c) (CFDictionary, IOReportIterateCallback) -> Void

private typealias CFDictionaryToCFStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
private typealias IOReportChannelGetFormatFn = @convention(c) (CFDictionary) -> Int32
private typealias IOReportStateGetCountFn = @convention(c) (CFDictionary) -> Int32
private typealias IOReportStateGetNameForIndexFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
private typealias IOReportStateGetResidencyFn = @convention(c) (CFDictionary, Int32) -> Int64
private typealias IOReportSimpleGetValueFn = @convention(c) (CFDictionary) -> Int64

private struct IOR {
    let copyChannels: IOReportCopyChannelsInGroupFn
    let createSub: IOReportCreateSubscriptionFn
    let createSamples: IOReportCreateSamplesFn
    let createDelta: IOReportCreateSamplesDeltaFn
    let iterate: IOReportIterateFn
    let getGroup: CFDictionaryToCFStringFn
    let getSubGroup: CFDictionaryToCFStringFn
    let getChannelName: CFDictionaryToCFStringFn
    let getFormat: IOReportChannelGetFormatFn
    let stateCount: IOReportStateGetCountFn
    let stateName: IOReportStateGetNameForIndexFn
    let stateRes: IOReportStateGetResidencyFn
    let simpleValue: IOReportSimpleGetValueFn?

    static func load() -> IOR? {
        let candidates = [
            "/usr/lib/libIOReport.dylib",
            "/System/Library/PrivateFrameworks/IOReport.framework/IOReport",
            "/System/Library/Frameworks/IOReport.framework/IOReport"
        ]
        var h: UnsafeMutableRawPointer?
        for p in candidates {
            if let opened = dlopen(p, RTLD_LAZY) {
                stderrPrint("info: loaded \(p)")
                h = opened
                break
            }
        }
        guard let handle = h else {
            stderrPrint("error: could not dlopen any IOReport binary")
            return nil
        }
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
            let gg = sym("IOReportChannelGetGroup", CFDictionaryToCFStringFn.self),
            let gs = sym("IOReportChannelGetSubGroup", CFDictionaryToCFStringFn.self),
            let gn = sym("IOReportChannelGetChannelName", CFDictionaryToCFStringFn.self),
            let gf = sym("IOReportChannelGetFormat", IOReportChannelGetFormatFn.self),
            let sc = sym("IOReportStateGetCount", IOReportStateGetCountFn.self),
            let sn = sym("IOReportStateGetNameForIndex", IOReportStateGetNameForIndexFn.self),
            let sr = sym("IOReportStateGetResidency", IOReportStateGetResidencyFn.self)
        else { return nil }
        // IOReportSimpleGetValue isn't always exported under that exact name;
        // optional so we can still read state channels (which is all we need
        // for GPU busy%).
        let sv = sym("IOReportSimpleGetValue", IOReportSimpleGetValueFn.self)
        return IOR(copyChannels: cc, createSub: cs, createSamples: cr, createDelta: cd,
                   iterate: it, getGroup: gg, getSubGroup: gs, getChannelName: gn,
                   getFormat: gf, stateCount: sc, stateName: sn, stateRes: sr,
                   simpleValue: sv)
    }
}

private func cfStr(_ u: Unmanaged<CFString>?) -> String {
    guard let u else { return "?" }
    return (u.takeUnretainedValue() as String)
}

guard let ior = IOR.load() else { exit(2) }

guard let channelsRef = ior.copyChannels("GPU Stats" as CFString, nil, 0, 0, 0) else {
    stderrPrint("error: IOReportCopyChannelsInGroup(\"GPU Stats\") returned nil")
    exit(3)
}
let channels = channelsRef.takeRetainedValue()

var subbed: Unmanaged<CFMutableDictionary>? = nil
guard let sub = ior.createSub(nil, channels, &subbed, 0, nil) else {
    stderrPrint("error: IOReportCreateSubscription failed")
    exit(3)
}
guard let subbedChannels = subbed?.takeRetainedValue() else {
    stderrPrint("error: subscription returned no channel dict")
    exit(3)
}

// One-shot dump of channels at startup so we can see what this Mac exposes.
stderrPrint("--- IOReport GPU Stats channels (startup dump) ---")
guard let firstSampleRef = ior.createSamples(sub, subbedChannels, nil) else {
    stderrPrint("error: IOReportCreateSamples returned nil")
    exit(3)
}
let firstSample = firstSampleRef.takeRetainedValue()
ior.iterate(firstSample, { ch in
    let g = cfStr(ior.getGroup(ch))
    let sg = cfStr(ior.getSubGroup(ch))
    let name = cfStr(ior.getChannelName(ch))
    let format = ior.getFormat(ch)
    var detail = ""
    switch format {
    case 1: // Simple
        if let f = ior.simpleValue {
            detail = "simple=\(f(ch))"
        } else {
            detail = "simple=<reader unavailable>"
        }
    case 2: // State
        let count = ior.stateCount(ch)
        var states: [String] = []
        if count > 0 {
            for i in 0..<count {
                let n = cfStr(ior.stateName(ch, i))
                let r = ior.stateRes(ch, i)
                states.append("\(n)=\(r)")
            }
        }
        detail = "states=[\(states.joined(separator: ", "))]"
    default:
        detail = "format=\(format) (unhandled)"
    }
    stderrPrint("group=\"\(g)\" subgroup=\"\(sg)\" channel=\"\(name)\" \(detail)")
    return 0
})
stderrPrint("---")
stderrPrint("info: GPU busy% below is computed from the PWRCTRL state channel")
stderrPrint("      (subgroup 'GPU Power Controller States'). busy = 1 - IDLE_OFF/total.")

// Loop: take a snapshot, sleep 1s, take another, derive busy% from delta.
var previousSample = firstSample
let start = Date()
for _ in 0..<10 {
    Thread.sleep(forTimeInterval: 1.0)
    guard let curRef = ior.createSamples(sub, subbedChannels, nil) else {
        stderrPrint("error: IOReportCreateSamples (loop) returned nil")
        exit(3)
    }
    let cur = curRef.takeRetainedValue()
    guard let deltaRef = ior.createDelta(previousSample, cur, nil) else {
        stderrPrint("error: IOReportCreateSamplesDelta returned nil")
        exit(3)
    }
    let delta = deltaRef.takeRetainedValue()

    var totalRes: Int64 = 0
    var idleRes: Int64 = 0
    ior.iterate(delta, { ch in
        // Only count the PWRCTRL channel — summing all GPU state channels
        // triple-counts elapsed time and gives nonsense percentages.
        guard cfStr(ior.getChannelName(ch)) == "PWRCTRL" else { return 0 }
        guard ior.getFormat(ch) == 2 else { return 0 }
        let count = ior.stateCount(ch)
        guard count > 0 else { return 0 }
        for i in 0..<count {
            let n = cfStr(ior.stateName(ch, i))
            let r = ior.stateRes(ch, i)
            totalRes += r
            if n == "IDLE_OFF" { idleRes += r }
        }
        return 0
    })

    let busyPct: Double
    if totalRes > 0 {
        busyPct = Double(totalRes - idleRes) / Double(totalRes) * 100.0
    } else {
        busyPct = .nan
    }
    let t = Date().timeIntervalSince(start)
    print(String(format: "t=%.2f gpuBusy=%.1f%% total=%lld idle=%lld", t, busyPct, totalRes, idleRes))

    previousSample = cur
}
