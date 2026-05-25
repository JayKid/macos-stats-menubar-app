import Foundation
import IOKit

// Low-level AppleSMC user-client wrapper. Ported from
// spikes/Sources/SMCKit/SMC.swift; the explicit 3-byte padding inside
// SMCKeyData_keyInfo_t is the load-bearing fix for Swift vs C struct embedding
// (Swift packs by size, C uses stride). Without that, `bytes[]` ends up at the
// wrong offset and reads come back garbled.

enum SMCError: Error, CustomStringConvertible {
    case driverNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t, smcResult: UInt8)
    case unsupportedType(key: String, type: String)

    var description: String {
        switch self {
        case .driverNotFound:
            return "AppleSMC IOService not found"
        case .openFailed(let r):
            return "IOServiceOpen failed: 0x\(String(r, radix: 16))"
        case .callFailed(let r, let s):
            return "SMC call failed: kern_return=0x\(String(r, radix: 16)) smcResult=\(s)"
        case .unsupportedType(let key, let type):
            return "Unsupported SMC type '\(type)' for key '\(key)'"
        }
    }
}

struct SMCKeyInfo {
    let dataSize: UInt32
    let dataType: String
}

struct SMCValue {
    let key: String
    let info: SMCKeyInfo
    let bytes: [UInt8]
}

final class SMC {
    private var conn: io_connect_t = 0

    init() throws {
        precondition(MemoryLayout<SMCKeyData_t>.stride == 80,
                     "SMCKeyData_t stride is \(MemoryLayout<SMCKeyData_t>.stride), expected 80 — struct layout drifted")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }

        let r = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard r == kIOReturnSuccess else { throw SMCError.openFailed(r) }
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    func read(_ key: String) throws -> SMCValue {
        var input = SMCKeyData_t()
        input.key = fourCharCode(key)
        input.data8 = SMCSubcommand.getKeyInfo.rawValue
        var output = try call(input)

        let info = SMCKeyInfo(
            dataSize: output.keyInfo.dataSize,
            dataType: typeAsString(output.keyInfo.dataType)
        )

        input.keyInfo = output.keyInfo
        input.data8 = SMCSubcommand.readKey.rawValue
        output = try call(input)

        let n = Int(info.dataSize)
        var raw = [UInt8](repeating: 0, count: n)
        withUnsafeBytes(of: output.bytes) { buf in
            for i in 0..<n { raw[i] = buf[i] }
        }
        return SMCValue(key: key, info: info, bytes: raw)
    }

    func readUInt8(_ key: String) throws -> UInt8 {
        let v = try read(key)
        guard v.info.dataType == "ui8 ", v.bytes.count >= 1 else {
            throw SMCError.unsupportedType(key: key, type: v.info.dataType)
        }
        return v.bytes[0]
    }

    func readFloat(_ key: String) throws -> Float {
        let v = try read(key)
        switch v.info.dataType {
        case "flt ":
            guard v.bytes.count >= 4 else {
                throw SMCError.unsupportedType(key: key, type: v.info.dataType)
            }
            return v.bytes.withUnsafeBufferPointer { ptr -> Float in
                var f: Float = 0
                memcpy(&f, ptr.baseAddress, 4)
                return f
            }
        case "fpe2":
            guard v.bytes.count >= 2 else {
                throw SMCError.unsupportedType(key: key, type: v.info.dataType)
            }
            let raw = (UInt16(v.bytes[0]) << 8) | UInt16(v.bytes[1])
            return Float(raw) / 4.0
        case "ui16":
            guard v.bytes.count >= 2 else {
                throw SMCError.unsupportedType(key: key, type: v.info.dataType)
            }
            let raw = (UInt16(v.bytes[0]) << 8) | UInt16(v.bytes[1])
            return Float(raw)
        default:
            throw SMCError.unsupportedType(key: key, type: v.info.dataType)
        }
    }

    private func call(_ inputStruct: SMCKeyData_t) throws -> SMCKeyData_t {
        var input = inputStruct
        var output = SMCKeyData_t()
        var outputSize = MemoryLayout<SMCKeyData_t>.stride

        let r = IOConnectCallStructMethod(
            conn,
            kSMCSelectorHandleYPCEvent,
            &input,
            MemoryLayout<SMCKeyData_t>.stride,
            &output,
            &outputSize
        )
        guard r == kIOReturnSuccess else {
            throw SMCError.callFailed(r, smcResult: output.result)
        }
        return output
    }
}

private let kSMCSelectorHandleYPCEvent: UInt32 = 2

private enum SMCSubcommand: UInt8 {
    case readKey = 5
    case getKeyInfo = 9
}

private func fourCharCode(_ s: String) -> UInt32 {
    precondition(s.utf8.count == 4, "SMC key must be exactly 4 bytes: \(s)")
    var v: UInt32 = 0
    for b in s.utf8 { v = (v << 8) | UInt32(b) }
    return v
}

private func typeAsString(_ code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff),
    ]
    return String(decoding: bytes, as: UTF8.self)
}

// MARK: - SMCKeyData_t (must match canonical 80-byte layout)

private typealias SMCBytes_t = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // Pad to stride 12. Swift embeds nested structs by size, not stride; the
    // kernel driver expects the canonical C layout where keyInfo occupies 12
    // bytes (9 used + 3 trailing pad). Without this padding `bytes[]` lands 3
    // bytes too early in the struct and reads come back wrong.
    var _pad1: UInt8 = 0
    var _pad2: UInt8 = 0
    var _pad3: UInt8 = 0
}

private struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers: SMCKeyData_vers_t = .init()
    var pLimitData: SMCKeyData_pLimitData_t = .init()
    var keyInfo: SMCKeyData_keyInfo_t = .init()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
