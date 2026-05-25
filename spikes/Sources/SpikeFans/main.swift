import Foundation

private func stderrPrint(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

let smc: SMC
do {
    smc = try SMC()
} catch {
    stderrPrint("error: opening AppleSMC failed: \(error)")
    exit(2)
}

let fanCount: UInt8
do {
    fanCount = try smc.readUInt8("FNum")
} catch {
    stderrPrint("error: reading FNum failed: \(error)")
    exit(3)
}

stderrPrint("info: FNum=\(fanCount)")

if fanCount == 0 {
    print("no_fans=true")
    exit(0)
}

func tryRead(_ key: String) -> String {
    do {
        let v = try smc.readFloat(key)
        return String(format: "%.0f", v)
    } catch {
        return "?(\(error))"
    }
}

let start = Date()
for tick in 0..<10 {
    let t = Date().timeIntervalSince(start)
    var parts: [String] = ["t=\(String(format: "%.2f", t))"]
    for i in 0..<Int(fanCount) {
        let actual = tryRead("F\(i)Ac")
        let target = tryRead("F\(i)Tg")
        let minV = tryRead("F\(i)Mn")
        let maxV = tryRead("F\(i)Mx")
        parts.append("fan\(i)=\(actual)rpm target=\(target) range=\(minV)-\(maxV)")
    }
    print(parts.joined(separator: " "))
    if tick < 9 { Thread.sleep(forTimeInterval: 1.0) }
}
