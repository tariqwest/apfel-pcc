// ============================================================================
// LRUCache.swift - Pure bounded least-recently-used cache
// Part of ApfelCore - no FoundationModels dependency
//
// A minimal fixed-capacity cache that, when full, evicts the single
// least-recently-used entry instead of wiping everything. Kept deliberately
// simple: a dictionary for storage plus an order array (front = LRU, back =
// most-recently-used). Both reads (`value(forKey:)`) and writes
// (`insert(_:forKey:)`) count as a "use" and refresh recency.
// ============================================================================

import Foundation

/// A fixed-capacity least-recently-used cache.
///
/// When at capacity, inserting a new key evicts the least-recently-used entry
/// (the one not read or written for the longest). Accessing an entry marks it
/// as most-recently-used, so hot entries survive churn from cold ones.
public struct LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    /// Keys ordered least-recently-used (first) to most-recently-used (last).
    private var order: [Key] = []
    /// Maximum number of entries retained.
    public let capacity: Int

    /// Creates a cache holding at most `capacity` entries.
    /// - Precondition: `capacity > 0`.
    public init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be positive")
        self.capacity = capacity
    }

    /// The current number of stored entries.
    public var count: Int { storage.count }

    /// Whether a value is currently cached for `key` (does not affect recency).
    public func contains(_ key: Key) -> Bool { storage[key] != nil }

    /// Returns the cached value for `key`, marking it most-recently-used.
    public mutating func value(forKey key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    /// Inserts or updates the value for `key`, marking it most-recently-used.
    /// If the cache is full and `key` is new, the least-recently-used entry is
    /// evicted first.
    public mutating func insert(_ value: Value, forKey key: Key) {
        if storage[key] != nil {
            storage[key] = value
            touch(key)
            return
        }
        if storage.count >= capacity, let lru = order.first {
            order.removeFirst()
            storage[lru] = nil
        }
        storage[key] = value
        order.append(key)
    }

    private mutating func touch(_ key: Key) {
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
        }
        order.append(key)
    }
}
