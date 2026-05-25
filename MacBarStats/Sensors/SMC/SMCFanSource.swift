import Foundation

/// Reads fan count and per-fan RPM/target/min/max through the AppleSMC
/// user-client. On a MacBook Air (`FNum == 0`) the source is considered
/// inactive and `read()` returns an empty array.
final class SMCFanSource {

    private let smc: SMC
    let fanCount: Int

    init?() {
        do {
            let smc = try SMC()
            let n = (try? smc.readUInt8("FNum")) ?? 0
            self.smc = smc
            self.fanCount = Int(n)
        } catch {
            return nil
        }
    }

    func read() -> [FanReading] {
        guard fanCount > 0 else { return [] }
        return (0..<fanCount).map { i in
            FanReading(
                id: i,
                actualRPM: Double(tryRead("F\(i)Ac")),
                targetRPM: Double(tryRead("F\(i)Tg")),
                minRPM:    Double(tryRead("F\(i)Mn")),
                maxRPM:    Double(tryRead("F\(i)Mx"))
            )
        }
    }

    private func tryRead(_ key: String) -> Float {
        (try? smc.readFloat(key)) ?? 0
    }
}
