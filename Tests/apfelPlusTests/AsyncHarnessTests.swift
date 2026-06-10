// ============================================================================
// AsyncHarnessTests.swift — Validate testAsync() harness works correctly
// ============================================================================

import Foundation

func runAsyncHarnessTests() {

    testAsync("async passing test runs") {
        let value = await Task { 42 }.value
        try assertEqual(value, 42)
    }

    testAsync("async assertTrue works") {
        let result = await Task { true }.value
        try assertTrue(result)
    }

    testAsync("async assertNil works") {
        let result: Int? = await Task { nil }.value
        try assertNil(result)
    }

    testAsync("async assertNotNil works") {
        let result: Int? = await Task { 1 }.value
        try assertNotNil(result)
    }

    testAsync("async assertEqual with strings") {
        let greeting = await Task { "hello" }.value
        try assertEqual(greeting, "hello")
    }

    testAsync("async work completes before assertion") {
        // Verify that the semaphore actually waits for the Task to finish
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                continuation.resume(returning: "done")
            }
        }
        try assertEqual(result, "done")
    }
}
