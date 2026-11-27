/// A small least-recently-used cache with value-type keys.
/// A dictionary holds values and an array keeps keys in use order, most recent last.
nonisolated struct LRUCache<Key: Hashable, Value> {
    let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0, "An LRU cache needs room for at least one entry.")
        self.capacity = capacity
    }

    var count: Int { values.count }

    /// The value for `key`, marking it as the most recently used.
    mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        if values.updateValue(value, forKey: key) != nil {
            touch(key)
            return
        }
        order.append(key)
        if order.count > capacity {
            let evicted = order.removeFirst()
            values[evicted] = nil
        }
    }

    mutating func removeAll() {
        values.removeAll()
        order.removeAll()
    }

    /// Keys from least to most recently used.
    var keysInUseOrder: [Key] { order }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }
}
