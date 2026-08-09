// ============================================================================
// StreamingToolCallGate.swift - Decide whether streamed content so far could
// still be the beginning of a tool call, so the SSE loop can hold it back
// instead of leaking raw tool-call JSON as content deltas (#224).
// Part of ApfelCore - pure Swift, no external dependencies.
// ============================================================================

import Foundation

/// When client tools (or MCP) are in play on `stream: true`, apfel must not
/// forward the model's tool-call JSON to the client as `delta.content` (OpenAI
/// never emits tool calls as assistant text). The SSE loop buffers while this
/// gate reports the accumulated content could still become a tool call, and
/// flushes it as plain content the moment it diverges from every tool-call
/// shape - so genuine text answers still stream token-by-token.
public enum StreamingToolCallGate {

    /// The bare-JSON tool-call opener the model is instructed to emit
    /// (see `ToolCallHandler.toolCallResponseFormat`).
    private static let jsonOpener = "{\"tool_calls\""
    /// A markdown fence may wrap the JSON tool call (```` ```json {...} ```` ).
    private static let fenceOpener = "```"

    /// True while `accumulated` could still be the start of a tool call and must
    /// therefore be held back. False once it has diverged and is safe to stream
    /// as content.
    ///
    /// Plausible prefixes (per #224): leading whitespace only, or a (partial)
    /// markdown fence, or a (partial) `{"tool_calls"` object opener. Anything
    /// else - including a JSON object that is clearly not `tool_calls`
    /// (e.g. `{"answer"`) or ordinary prose - is not held back.
    public static func isPlausibleToolCallPrefix(_ accumulated: String) -> Bool {
        let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing but whitespace has arrived yet - keep waiting.
        if trimmed.isEmpty { return true }
        // A (partial) fence, or a (partial) bare tool-call object.
        return sharesPrefix(trimmed, fenceOpener) || sharesPrefix(trimmed, jsonOpener)
    }

    /// True when one string is a prefix of the other (either direction),
    /// case-sensitive. Lets a still-growing snapshot match a target opener it
    /// has not fully reached yet (`{` vs `{"tool_calls"`) and a longer snapshot
    /// match an opener it has already committed to (`{"tool_calls": [...` ).
    private static func sharesPrefix(_ a: String, _ b: String) -> Bool {
        a.hasPrefix(b) || b.hasPrefix(a)
    }
}
