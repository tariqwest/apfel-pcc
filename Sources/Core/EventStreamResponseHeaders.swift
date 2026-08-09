// ============================================================================
// EventStreamResponseHeaders.swift — SSE response header policy (ApfelCore)
// ============================================================================

import Foundation

/// The HTTP response headers every Server-Sent Events (SSE) streaming endpoint
/// sends, as ordered (name, value) pairs. Single source of truth for the
/// OpenAI-compatible streaming surfaces (`/v1/chat/completions` and
/// `/v1/responses` with `stream: true`). Pure policy: the executable's
/// Hummingbird glue builds its header fields from this list.
public enum EventStreamResponseHeaders {
    /// Exactly: `Content-Type: text/event-stream`, `Cache-Control: no-cache`,
    /// `Connection: keep-alive`, in that order.
    public static let fields: [(name: String, value: String)] = [
        (name: "Content-Type", value: "text/event-stream"),
        (name: "Cache-Control", value: "no-cache"),
        (name: "Connection", value: "keep-alive"),
    ]
}
