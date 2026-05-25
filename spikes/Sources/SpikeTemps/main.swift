import Foundation
import IOKit

// MARK: - Private IOHIDEventSystemClient bindings (resolved at runtime via dlsym)

private typealias IOHIDEventSystemClientCreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
private typealias IOHIDEventSystemClientSetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
private typealias IOHIDEventSystemClientCopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
private typealias IOHIDServiceClientCopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
private typealias IOHIDServiceClientCopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
private typealias IOHIDEventGetFloatValueFn = @convention(c) (AnyObject, Int32) -> Double

private struct HID {
    let create: IOHIDEventSystemClientCreateFn
    let setMatching: IOHIDEventSystemClientSetMatchingFn
    let copyServices: IOHIDEventSystemClientCopyServicesFn
    let copyEvent: IOHIDServiceClientCopyEventFn
    let copyProperty: IOHIDServiceClientCopyPropertyFn
    let getFloat: IOHIDEventGetFloatValueFn

    static func load() -> HID? {
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let h = dlopen(path, RTLD_LAZY) else { return nil }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard
            let c = sym("IOHIDEventSystemClientCreate", IOHIDEventSystemClientCreateFn.self),
            let m = sym("IOHIDEventSystemClientSetMatching", IOHIDEventSystemClientSetMatchingFn.self),
            let s = sym("IOHIDEventSystemClientCopyServices", IOHIDEventSystemClientCopyServicesFn.self),
            let e = sym("IOHIDServiceClientCopyEvent", IOHIDServiceClientCopyEventFn.self),
            let p = sym("IOHIDServiceClientCopyProperty", IOHIDServiceClientCopyPropertyFn.self),
            let g = sym("IOHIDEventGetFloatValue", IOHIDEventGetFloatValueFn.self)
        else { return nil }
        return HID(create: c, setMatching: m, copyServices: s, copyEvent: e, copyProperty: p, getFloat: g)
    }
}

// kHIDPage_AppleVendor = 0xff00, kHIDUsage_AppleVendor_TemperatureSensor = 0x0005
private let kPageAppleVendor: Int32 = 0xff00
private let kUsageTemperatureSensor: Int32 = 0x0005

// kIOHIDEventTypeTemperature = 15; field = (type << 16) | index, index 0 = Level
private let kEventTypeTemperature: Int64 = 15
private let kEventFieldTemperatureLevel: Int32 = Int32(15 << 16)

private func stderrPrint(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

guard let hid = HID.load() else {
    stderrPrint("error: failed to dlopen IOKit private symbols")
    exit(2)
}

let matching: CFDictionary = [
    "PrimaryUsagePage": kPageAppleVendor,
    "PrimaryUsage": kUsageTemperatureSensor
] as CFDictionary

guard let clientRef = hid.create(kCFAllocatorDefault) else {
    stderrPrint("error: IOHIDEventSystemClientCreate returned nil")
    exit(2)
}
let client = clientRef.takeRetainedValue()
hid.setMatching(client, matching)

guard let servicesRef = hid.copyServices(client) else {
    stderrPrint("error: IOHIDEventSystemClientCopyServices returned nil")
    exit(2)
}
let services = servicesRef.takeRetainedValue() as [AnyObject]

if services.isEmpty {
    stderrPrint("error: no temperature services matched (page 0x\(String(kPageAppleVendor, radix: 16)) usage \(kUsageTemperatureSensor))")
    exit(3)
}

let names: [String] = services.map { svc in
    guard let raw = hid.copyProperty(svc, "Product" as CFString) else { return "<unnamed>" }
    let val = raw.takeRetainedValue()
    return (val as? String) ?? "<unnamed>"
}

stderrPrint("info: found \(services.count) temperature sensor(s)")

let start = Date()
for tick in 0..<10 {
    let t = Date().timeIntervalSince(start)
    for (i, svc) in services.enumerated() {
        let name = names[i]
        let temp: String
        if let evRef = hid.copyEvent(svc, kEventTypeTemperature, 0, 0) {
            let ev = evRef.takeRetainedValue()
            let v = hid.getFloat(ev, kEventFieldTemperatureLevel)
            temp = String(format: "%.2f", v)
        } else {
            temp = "nan"
        }
        print("t=\(String(format: "%.2f", t)) sensor=\"\(name)\" tempC=\(temp)")
    }
    if tick < 9 { Thread.sleep(forTimeInterval: 1.0) }
}
