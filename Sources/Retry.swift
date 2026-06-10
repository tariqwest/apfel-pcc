// ============================================================================
// Retry.swift — AsyncSemaphore for server concurrency limiting
// Part of apfel-plus — Apple Intelligence from the command line
// ============================================================================
// NOTE: withRetry() and isRetryableError() have been moved to
// ApfelCore (Sources/Core/Retry.swift and Sources/Core/ApfelError.swift)
// for testability and locale-safe error detection.
// ============================================================================

import Foundation

// MARK: - Async Semaphore

/// A simple async semaphore for limiting concurrent operations.
/// Uses ID-based waiter tracking to prevent double-resume on timeout.
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    init(value: Int) {
        self.count = value
    }

    /// Wait until a slot is available. Times out after the specified duration.
    func wait(timeout: Duration = .seconds(30)) async throws {
        if count > 0 {
            count -= 1
            return
        }

        let id = UUID()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            waiters.append((id: id, continuation: cont))
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.timeoutWaiter(id: id)
            }
        }
    }

    /// Remove a waiter by ID and resume with timeout error.
    /// If signal() already resumed it, the waiter won't be in the array — no-op.
    private func timeoutWaiter(id: UUID) {
        if let idx = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: idx)
            waiter.continuation.resume(throwing: SemaphoreTimeoutError())
        }
    }

    /// Signal that a slot is available.
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume()
        } else {
            count += 1
        }
    }
}

struct SemaphoreTimeoutError: Error, LocalizedError {
    var errorDescription: String? { "Request queued too long — server at max concurrent capacity" }
}
