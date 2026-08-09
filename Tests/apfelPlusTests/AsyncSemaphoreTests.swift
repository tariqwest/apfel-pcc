// ============================================================================
// AsyncSemaphoreTests.swift - Concurrency-limit semaphore behavior (#214)
// Regression coverage: a wait(timeout:) that genuinely times out must throw
// SemaphoreTimeoutError - it previously crashed the whole process (SIGABRT,
// "freed pointer was not the last allocation") because the timeout resumed
// the continuation from an unstructured Task spawned inside the
// withCheckedThrowingContinuation body.
// ============================================================================

import Foundation
import ApfelCore

func runAsyncSemaphoreTests() {
    testAsync("wait succeeds immediately when a permit is available") {
        let sem = AsyncSemaphore(value: 1)
        try await sem.wait(timeout: .milliseconds(100))
    }

    testAsync("wait throws SemaphoreTimeoutError on genuine timeout (no crash)") {
        let sem = AsyncSemaphore(value: 1)
        try await sem.wait() // take the only permit
        do {
            try await sem.wait(timeout: .milliseconds(100))
            throw TestFailure("expected SemaphoreTimeoutError, wait returned normally")
        } catch let error as SemaphoreTimeoutError {
            // Inspect the error, not just the throw
            try assertTrue(
                error.errorDescription?.contains("max concurrent capacity") == true,
                "unexpected description: \(String(describing: error.errorDescription))"
            )
        }
    }

    testAsync("signal releases a queued waiter before its timeout") {
        let sem = AsyncSemaphore(value: 1)
        try await sem.wait() // take the only permit
        let waiter = Task {
            try await sem.wait(timeout: .seconds(5))
        }
        // Give the waiter time to enqueue, then release the permit.
        try await Task.sleep(for: .milliseconds(100))
        await sem.signal()
        try await waiter.value // must resume without throwing
    }

    testAsync("permit accounting stays correct after a timeout") {
        let sem = AsyncSemaphore(value: 1)
        try await sem.wait() // take the only permit
        do {
            try await sem.wait(timeout: .milliseconds(100))
            throw TestFailure("expected SemaphoreTimeoutError, wait returned normally")
        } catch is SemaphoreTimeoutError {
            // expected
        }
        // Release the original permit: no waiters left, so the count goes back
        // to 1 and the next wait must succeed immediately.
        await sem.signal()
        try await sem.wait(timeout: .milliseconds(100))
    }

    testAsync("many concurrent waiters all time out cleanly") {
        let sem = AsyncSemaphore(value: 1)
        try await sem.wait() // take the only permit
        let timeouts = TimeoutCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        try await sem.wait(timeout: .milliseconds(100))
                    } catch is SemaphoreTimeoutError {
                        await timeouts.bump()
                    } catch {
                        // wrong error type: do not count it
                    }
                }
            }
        }
        let count = await timeouts.value
        guard count == 10 else {
            throw TestFailure("expected 10 SemaphoreTimeoutErrors, got \(count)")
        }
    }
}

private actor TimeoutCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
