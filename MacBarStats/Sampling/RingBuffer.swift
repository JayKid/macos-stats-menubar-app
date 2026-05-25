import Foundation

/// Fixed-capacity ring buffer. `append` is O(1); when full, the oldest
/// element is dropped. `setCapacity(_:)` preserves the most recent N
/// elements that still fit.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private(set) var capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
    var last: Element? { storage.last }

    mutating func append(_ element: Element) {
        if storage.count >= capacity {
            storage.removeFirst(storage.count - capacity + 1)
        }
        storage.append(element)
    }

    mutating func setCapacity(_ newCapacity: Int) {
        let n = max(1, newCapacity)
        capacity = n
        if storage.count > n {
            storage.removeFirst(storage.count - n)
        } else {
            storage.reserveCapacity(n)
        }
    }

    func toArray() -> [Element] { storage }
}
