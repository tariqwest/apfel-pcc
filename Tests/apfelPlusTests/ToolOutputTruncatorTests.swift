// ============================================================================
// ToolOutputTruncatorTests.swift - Pure head+tail tool-output truncation (#221)
// ============================================================================

import Foundation
import ApfelCore

func runToolOutputTruncatorTests() {

    test("no truncation when the result already fits the budget (#221)") {
        let r = ToolOutputTruncator.truncate("small result", tokenCount: 3, budgetTokens: 100)
        try assertEqual(r.text, "small result")
        try assertTrue(!r.wasTruncated)
    }

    test("no truncation when token count equals budget (#221)") {
        let r = ToolOutputTruncator.truncate("abc", tokenCount: 50, budgetTokens: 50)
        try assertTrue(!r.wasTruncated)
        try assertEqual(r.text, "abc")
    }

    test("empty text is never truncated (#221)") {
        let r = ToolOutputTruncator.truncate("", tokenCount: 0, budgetTokens: 0)
        try assertEqual(r.text, "")
        try assertTrue(!r.wasTruncated)
    }

    test("over-budget result keeps head and tail with a marker (#221)") {
        // 1000 'a' chars, measured as 1000 tokens (1 token/char), budget 100.
        let text = String(repeating: "a", count: 500) + String(repeating: "b", count: 500)
        let r = ToolOutputTruncator.truncate(text, tokenCount: 1000, budgetTokens: 100)
        try assertTrue(r.wasTruncated)
        try assertTrue(r.text.hasPrefix("a"), "must keep the head")
        try assertTrue(r.text.hasSuffix("b"), "must keep the tail")
        try assertTrue(r.text.contains("[tool output truncated:"), "must carry the marker")
        try assertTrue(r.text.contains("of 1000 tokens shown]"), "marker must report the original total")
        // The kept content is far smaller than the original.
        try assertTrue(r.text.count < text.count, "must be shorter than the original")
    }

    test("marker reports fewer shown tokens than the total (#221)") {
        let text = String(repeating: "x", count: 2000)
        let r = ToolOutputTruncator.truncate(text, tokenCount: 2000, budgetTokens: 200)
        try assertTrue(r.wasTruncated)
        // Extract N from "truncated: N of 2000".
        guard let range = r.text.range(of: "truncated: "),
              let end = r.text.range(of: " of 2000") else {
            throw TestFailure("marker not found in \(r.text)")
        }
        let n = Int(r.text[range.upperBound..<end.lowerBound]) ?? -1
        try assertTrue(n >= 0 && n < 2000, "shown tokens \(n) must be in [0, 2000)")
    }

    test("tiny budget still produces a valid marked result without crashing (#221)") {
        let text = String(repeating: "z", count: 1000)
        let r = ToolOutputTruncator.truncate(text, tokenCount: 1000, budgetTokens: 1)
        try assertTrue(r.wasTruncated)
        try assertTrue(r.text.contains("[tool output truncated:"))
    }
}
