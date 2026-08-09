// ============================================================================
// PrewarmDecisionTests.swift - Unit tests for the CLI prewarm policy (#364)
// Pure decision: which modes fire a model prewarm before input I/O.
// ============================================================================

import Foundation
import ApfelCLI

func runPrewarmDecisionTests() {

    test("single mode prewarms") {
        try assertTrue(PrewarmDecision.shouldPrewarm(mode: .single))
    }

    test("stream mode prewarms") {
        try assertTrue(PrewarmDecision.shouldPrewarm(mode: .stream))
    }

    test("chat mode prewarms (covers type-time of the first message)") {
        try assertTrue(PrewarmDecision.shouldPrewarm(mode: .chat))
    }

    test("serve mode does not prewarm here (startServer owns it, #169)") {
        try assertTrue(!PrewarmDecision.shouldPrewarm(mode: .serve))
    }

    test("countTokens mode does not prewarm (never calls the model)") {
        try assertTrue(!PrewarmDecision.shouldPrewarm(mode: .countTokens))
    }

    test("benchmark mode does not prewarm (manages its own sessions)") {
        try assertTrue(!PrewarmDecision.shouldPrewarm(mode: .benchmark))
    }

    test("non-generating modes do not prewarm") {
        for mode: CLIArguments.Mode in [.modelInfo, .update, .demos, .completions, .help, .version, .release] {
            try assertTrue(!PrewarmDecision.shouldPrewarm(mode: mode), "mode \(mode) must not prewarm")
        }
    }
}
