// ============================================================================
// AsyncSemaphore.swift - Async semaphore for server concurrency limiting
// Part of apfel - Apple Intelligence from the command line
// ============================================================================
// Moved from Sources/Retry.swift (root target) into ApfelCore so the pure
// Swift unit-test runner (apfel-tests) can exercise it (#214).
// ============================================================================

import Foundation

/// A simple async semaphore for limiting concurrent operations.
///
/// Uses ID-based waiter tracking so signal() and a timeout can race safely:
/// whichever runs first on the actor removes the waiter and resumes it;
/// the loser finds nothing and is a no-op.
///
/// Timeout crash fix (#214): a genuine wait timeout used to abort the whole
/// process (SIGABRT, "freed pointer was not the last allocation" in
/// swift_task_dealloc, faulting frame inside Task.sleep). Two changes keep it
/// from recurring, both verified against the live server reproduction:
/// - The timeout task uses Task.sleep(nanoseconds:), NOT the generic
///   clock-based Task.sleep(for:). The clock-based sleep inside this
///   isolation-inheriting child task crashed the task allocator on resume
///   under the server executor (deterministic at every timeout). Do not
///   switch it back to Task.sleep(for:).
/// - The timeout task is created outside the withCheckedThrowingContinuation
///   body, stored on the actor keyed by waiter ID, and cancelled by signal()
///   when a permit is handed over, so no orphan timers accumulate.
public actor AsyncSemaphore {
    private var count: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    public init(value: Int) {
        self.count = value
    }

    /// Wait until a slot is available. Times out after the specified duration
    /// by throwing SemaphoreTimeoutError (never by crashing).
    public func wait(timeout: Duration = .seconds(30)) async throws {
        if count > 0 {
            count -= 1
            return
        }

        let id = UUID()
        // Start the timeout clock before suspending. There is no suspension
        // point between here and the waiter enqueue inside the continuation
        // body, so timeoutWaiter (actor-isolated) cannot observe a state
        // where the clock is running but the waiter is missing.
        let nanoseconds = Self.nanoseconds(from: timeout)
        timeoutTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.timeoutWaiter(id: id)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            waiters.append((id: id, continuation: cont))
        }
    }

    /// Convert a Duration to whole nanoseconds, saturating instead of trapping.
    private static func nanoseconds(from duration: Duration) -> UInt64 {
        let (seconds, attoseconds) = duration.components
        guard seconds >= 0 else { return 0 }
        let (scaled, overflow) = UInt64(seconds).multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow else { return .max }
        let (total, overflow2) = scaled.addingReportingOverflow(UInt64(max(0, attoseconds) / 1_000_000_000))
        return overflow2 ? .max : total
    }

    /// Remove a waiter by ID and resume with timeout error.
    /// If signal() already resumed it, the waiter won't be in the array - no-op.
    private func timeoutWaiter(id: UUID) {
        timeoutTasks[id] = nil
        if let idx = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: idx)
            waiter.continuation.resume(throwing: SemaphoreTimeoutError())
        }
    }

    /// Signal that a slot is available.
    public func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            timeoutTasks.removeValue(forKey: waiter.id)?.cancel()
            waiter.continuation.resume()
        } else {
            count += 1
        }
    }
}

public struct SemaphoreTimeoutError: Error, LocalizedError {
    public init() {}
    public var errorDescription: String? { "Request queued too long - server at max concurrent capacity" }
}
