// ============================================================================
// StreamingToolCallGateTests.swift - Pure decision logic that keeps the
// streaming SSE path from leaking raw tool-call JSON as content deltas (#224).
// ============================================================================

import Foundation
import ApfelCore

func runStreamingToolCallGateTests() {

    // MARK: - Hold (still a plausible tool-call prefix)

    test("empty string holds (nothing streamed yet)") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix(""))
    }

    test("whitespace only holds") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("   \n\t "))
    }

    test("single brace holds - could grow into {\"tool_calls\"") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("{"))
    }

    test("partial tool_calls opener holds") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("{\"tool"))
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("{\"tool_calls"))
    }

    test("full tool_calls opener holds") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("{\"tool_calls\""))
    }

    test("committed tool_calls object holds") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix(
            "{\"tool_calls\": [{\"id\": \"call_1\", \"type\": \"function\""))
    }

    test("leading whitespace before tool_calls opener holds (trimmed first)") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("\n  {\"tool_calls\": ["))
    }

    test("partial fence holds - one, two, three backticks") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("`"))
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("``"))
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("```"))
    }

    test("fenced json tool call holds") {
        try assertTrue(StreamingToolCallGate.isPlausibleToolCallPrefix("```json\n{\"tool_calls\": ["))
    }

    // MARK: - Flush (diverged from every tool-call shape)

    test("plain prose flushes immediately") {
        try assertTrue(!StreamingToolCallGate.isPlausibleToolCallPrefix("Sure, here is"))
    }

    test("json object that is not tool_calls flushes") {
        try assertTrue(!StreamingToolCallGate.isPlausibleToolCallPrefix("{\"answer\": 42}"))
    }

    test("brace then a non-tool key flushes") {
        // "{\"a" diverges from "{\"tool_calls\"" at the 3rd char.
        try assertTrue(!StreamingToolCallGate.isPlausibleToolCallPrefix("{\"a"))
    }

    test("single quote-brace with wrong key char flushes") {
        try assertTrue(!StreamingToolCallGate.isPlausibleToolCallPrefix("{\"x"))
    }

    test("array literal flushes (not an object opener)") {
        try assertTrue(!StreamingToolCallGate.isPlausibleToolCallPrefix("[1, 2, 3]"))
    }

    test("text that merely contains a fence later flushes (must START with it)") {
        try assertTrue(!StreamingToolCallGate.isPlausibleToolCallPrefix("here is code ```json"))
    }
}
