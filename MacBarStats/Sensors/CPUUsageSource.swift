import Foundation
import Darwin

/// Per-core and aggregate CPU utilization via `host_processor_info`. Each
/// `read()` compares the current tick counts against the previous sample to
/// derive percentages. On the first call we have no previous sample, so
/// values come back as 0 — the second tick onward they're real.
///
/// The kernel returns four tick counters per logical core (user, system,
/// idle, nice). Busy = (user + system + nice) / total.
final class CPUUsageSource {

    private var previous: [CoreTicks]?

    private struct CoreTicks {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32

        var total: UInt32 { user &+ system &+ idle &+ nice }
        var busy: UInt32  { user &+ system &+ nice }
    }

    func read() -> CPUReading {
        let current = Self.fetchTicks()

        defer { previous = current }
        guard let previous, previous.count == current.count else {
            // First sample: return zeroes; UI will fill in on the next tick.
            return CPUReading(perCore: Array(repeating: 0, count: current.count), aggregate: 0)
        }

        var perCore = [Double](repeating: 0, count: current.count)
        var busySum: UInt64 = 0
        var totalSum: UInt64 = 0
        for i in 0..<current.count {
            let dBusy  = current[i].busy  &- previous[i].busy
            let dTotal = current[i].total &- previous[i].total
            perCore[i] = dTotal == 0 ? 0 : min(1, Double(dBusy) / Double(dTotal))
            busySum  &+= UInt64(dBusy)
            totalSum &+= UInt64(dTotal)
        }
        let aggregate = totalSum == 0 ? 0 : Double(busySum) / Double(totalSum)
        return CPUReading(perCore: perCore, aggregate: aggregate)
    }

    private static func fetchTicks() -> [CoreTicks] {
        var count: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let r = host_processor_info(mach_host_self(),
                                    PROCESSOR_CPU_LOAD_INFO,
                                    &count,
                                    &infoArray,
                                    &infoCount)
        guard r == KERN_SUCCESS, let infoArray else { return [] }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }
        let stride = Int(CPU_STATE_MAX)
        let cores = Int(count)
        var out = [CoreTicks]()
        out.reserveCapacity(cores)
        for i in 0..<cores {
            let base = i * stride
            out.append(CoreTicks(
                user:   UInt32(bitPattern: infoArray[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: infoArray[base + Int(CPU_STATE_SYSTEM)]),
                idle:   UInt32(bitPattern: infoArray[base + Int(CPU_STATE_IDLE)]),
                nice:   UInt32(bitPattern: infoArray[base + Int(CPU_STATE_NICE)])
            ))
        }
        return out
    }
}
