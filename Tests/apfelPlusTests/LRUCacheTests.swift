// ============================================================================
// LRUCacheTests.swift - Unit tests for the pure LRUCache (#247)
// ============================================================================

import Foundation
import ApfelCore

func runLRUCacheTests() {
    test("stores and retrieves a value") {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, forKey: "a")
        try assertEqual(cache.value(forKey: "a"), 1)
    }

    test("missing key returns nil") {
        var cache = LRUCache<String, Int>(capacity: 2)
        try assertNil(cache.value(forKey: "nope"))
    }

    test("count reflects stored entries and caps at capacity") {
        var cache = LRUCache<Int, Int>(capacity: 3)
        for i in 0..<10 { cache.insert(i, forKey: i) }
        try assertEqual(cache.count, 3)
    }

    test("full cache evicts exactly one LRU entry, not everything (#247)") {
        var cache = LRUCache<Int, Int>(capacity: 3)
        cache.insert(0, forKey: 0)
        cache.insert(1, forKey: 1)
        cache.insert(2, forKey: 2)
        // Cache full. Inserting a fourth evicts only the LRU (key 0).
        cache.insert(3, forKey: 3)
        try assertEqual(cache.count, 3, "must evict one, not removeAll")
        try assertNil(cache.value(forKey: 0), "key 0 (LRU) must be evicted")
        try assertEqual(cache.value(forKey: 1), 1, "key 1 must survive")
        try assertEqual(cache.value(forKey: 2), 2, "key 2 must survive")
        try assertEqual(cache.value(forKey: 3), 3, "newest key must be present")
    }

    test("reading an entry marks it most-recently-used so it survives eviction (#247)") {
        var cache = LRUCache<Int, Int>(capacity: 3)
        cache.insert(0, forKey: 0)   // insertion order: 0,1,2 (0 is LRU)
        cache.insert(1, forKey: 1)
        cache.insert(2, forKey: 2)
        // Touch key 0 -> it becomes most-recently-used; key 1 is now LRU.
        _ = cache.value(forKey: 0)
        cache.insert(3, forKey: 3)   // should evict key 1, not the hot key 0
        try assertEqual(cache.value(forKey: 0), 0, "hot (recently-read) entry must survive")
        try assertNil(cache.value(forKey: 1), "key 1 (now LRU) must be evicted")
        try assertEqual(cache.value(forKey: 2), 2)
        try assertEqual(cache.value(forKey: 3), 3)
    }

    test("re-inserting an existing key refreshes recency and updates value") {
        var cache = LRUCache<Int, Int>(capacity: 3)
        cache.insert(0, forKey: 0)
        cache.insert(1, forKey: 1)
        cache.insert(2, forKey: 2)
        // Update key 0 -> value changes and it becomes MRU; key 1 becomes LRU.
        cache.insert(100, forKey: 0)
        try assertEqual(cache.count, 3, "update must not grow the cache")
        try assertEqual(cache.value(forKey: 0), 100, "value must be updated")
        cache.insert(3, forKey: 3)   // evicts key 1
        try assertEqual(cache.value(forKey: 0), 100, "refreshed key must survive")
        try assertNil(cache.value(forKey: 1), "key 1 (LRU) evicted")
    }

    test("hot entry survives repeated cold churn") {
        var cache = LRUCache<Int, Int>(capacity: 4)
        cache.insert(-1, forKey: -1)   // the hot key
        cache.insert(0, forKey: 0)
        cache.insert(1, forKey: 1)
        cache.insert(2, forKey: 2)
        // Repeatedly read the hot key and push new cold keys; hot must persist.
        for i in 3..<50 {
            _ = cache.value(forKey: -1)
            cache.insert(i, forKey: i)
        }
        try assertEqual(cache.value(forKey: -1), -1, "hot entry must never be evicted")
        try assertEqual(cache.count, 4)
    }

    test("capacity of one keeps only the newest") {
        var cache = LRUCache<Int, Int>(capacity: 1)
        cache.insert(1, forKey: 1)
        cache.insert(2, forKey: 2)
        try assertNil(cache.value(forKey: 1))
        try assertEqual(cache.value(forKey: 2), 2)
        try assertEqual(cache.count, 1)
    }
}
