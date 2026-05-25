import Foundation
import IOKit

/// Reads Apple Silicon temperature sensors via the private
/// `IOHIDEventSystemClient` API. Symbols are resolved at runtime through
/// `dlsym` so we don't fail at link time if Apple ever removes them.
///
/// Spike output on the dev MacBook Pro showed 46 sensors with many duplicate
/// `Product` strings (e.g., four entries named `PMU tdie5`). To keep
/// identities stable across ticks we assign each sensor an occurrence index
/// at discovery time and ID it as `"<rawName>#<occurrence>"`.
final class IOHIDTemperatureSource {

    struct Sensor {
        let id: String
        let rawName: String
        let category: TempCategory?
        fileprivate let service: AnyObject
    }

    private let hid: HIDBindings
    private let client: AnyObject
    private let sensors: [Sensor]

    init?() {
        guard let hid = HIDBindings.load() else { return nil }
        self.hid = hid

        let matching: CFDictionary = [
            "PrimaryUsagePage": kPageAppleVendor,
            "PrimaryUsage": kUsageTemperatureSensor
        ] as CFDictionary

        guard let clientRef = hid.create(kCFAllocatorDefault) else { return nil }
        let client = clientRef.takeRetainedValue()
        self.client = client
        hid.setMatching(client, matching)

        guard let servicesRef = hid.copyServices(client) else { return nil }
        let services = servicesRef.takeRetainedValue() as [AnyObject]

        // Discover sensors once. We assign occurrence indices per rawName so
        // duplicate-named sensors get stable IDs across samples.
        var counters: [String: Int] = [:]
        var found: [Sensor] = []
        for svc in services {
            let name: String
            if let raw = hid.copyProperty(svc, "Product" as CFString) {
                name = (raw.takeRetainedValue() as? String) ?? ""
            } else {
                name = ""
            }
            guard !name.isEmpty else { continue }

            let occurrence = counters[name, default: 0]
            counters[name] = occurrence + 1

            // Sanity check: skip sensors that never produce a temperature.
            guard let evRef = hid.copyEvent(svc, kEventTypeTemperature, 0, 0) else { continue }
            let ev = evRef.takeRetainedValue()
            let v = hid.getFloat(ev, kEventFieldTemperatureLevel)
            guard v.isFinite, v > -50, v < 200 else { continue }

            found.append(Sensor(
                id: "\(name)#\(occurrence)",
                rawName: name,
                category: TemperatureCategorizer.categorize(name: name),
                service: svc
            ))
        }
        self.sensors = found
    }

    func read() -> [TemperatureReading] {
        sensors.compactMap { sensor in
            guard let evRef = hid.copyEvent(sensor.service, kEventTypeTemperature, 0, 0) else {
                return nil
            }
            let ev = evRef.takeRetainedValue()
            let v = hid.getFloat(ev, kEventFieldTemperatureLevel)
            guard v.isFinite else { return nil }
            return TemperatureReading(
                id: sensor.id,
                rawName: sensor.rawName,
                category: sensor.category,
                celsius: v
            )
        }
    }

    var discoveredCount: Int { sensors.count }
}

// MARK: - dlsym bindings

private typealias IOHIDEventSystemClientCreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
private typealias IOHIDEventSystemClientSetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
private typealias IOHIDEventSystemClientCopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
private typealias IOHIDServiceClientCopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
private typealias IOHIDServiceClientCopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
private typealias IOHIDEventGetFloatValueFn = @convention(c) (AnyObject, Int32) -> Double

private struct HIDBindings {
    let create: IOHIDEventSystemClientCreateFn
    let setMatching: IOHIDEventSystemClientSetMatchingFn
    let copyServices: IOHIDEventSystemClientCopyServicesFn
    let copyEvent: IOHIDServiceClientCopyEventFn
    let copyProperty: IOHIDServiceClientCopyPropertyFn
    let getFloat: IOHIDEventGetFloatValueFn

    static func load() -> HIDBindings? {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return nil
        }
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
        return HIDBindings(create: c, setMatching: m, copyServices: s,
                           copyEvent: e, copyProperty: p, getFloat: g)
    }
}

private let kPageAppleVendor: Int32 = 0xff00
private let kUsageTemperatureSensor: Int32 = 0x0005
private let kEventTypeTemperature: Int64 = 15
private let kEventFieldTemperatureLevel: Int32 = Int32(15 << 16)
