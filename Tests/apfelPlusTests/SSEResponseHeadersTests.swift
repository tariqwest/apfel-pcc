// ============================================================================
// SSEResponseHeadersTests.swift — lockdown for the event-stream (SSE) response
// header policy in ApfelCore. Every streaming endpoint (/v1/chat/completions
// with stream=true, /v1/responses with stream=true) must send exactly these
// headers, in this order, with this casing. The Hummingbird glue in the
// executable builds its HTTPFields from this single source of truth, so any
// drift here is a wire-format change for every SSE client.
// ============================================================================

import Foundation
import ApfelCore

func runSSEResponseHeadersTests() {

    test("EventStreamResponseHeaders.fields is exactly the three SSE headers, in order") {
        let fields = EventStreamResponseHeaders.fields
        try assertEqual(fields.count, 3)
        try assertEqual(fields[0].name, "Content-Type")
        try assertEqual(fields[0].value, "text/event-stream")
        try assertEqual(fields[1].name, "Cache-Control")
        try assertEqual(fields[1].value, "no-cache")
        try assertEqual(fields[2].name, "Connection")
        try assertEqual(fields[2].value, "keep-alive")
    }
}
