// ============================================================================
// CLIValidateTests.swift - Unit tests for CLIArguments.validate(context:).
//
// validate() is the post-parse semantic check phase. parse() populates a
// CLIArguments struct syntactically; validate() runs cross-flag invariants
// (currently just mode-conflict detection, more in the future). Tests here
// exercise validate() directly on hand-built CLIArguments + ValidationContext
// values without going through parse().
//
// The end-to-end mode-conflict tests that call parse(["--chat", "--serve"])
// live in CLIArgumentsTests.swift and are unchanged by PR #2 - parse() still
// throws the same error via its internal validate() call.
// ============================================================================

import Foundation
import ApfelCLI

func runCLIValidateTests() {

    // -- ValidationContext construction --

    test("ValidationContext default-inits empty") {
        let ctx = ValidationContext()
        try assertEqual(ctx.modeFlagsSeen.count, 0)
    }

    test("ValidationContext can be constructed with a non-empty flag list") {
        let ctx = ValidationContext(modeFlagsSeen: ["--chat"])
        try assertEqual(ctx.modeFlagsSeen, ["--chat"])
    }

    // -- validate() clean cases --

    test("validate() returns cleanly for empty context") {
        try CLIArguments().validate()
    }

    test("validate() returns cleanly for context with default init") {
        try CLIArguments().validate(context: .init())
    }

    test("validate() returns cleanly for single mode flag seen") {
        try CLIArguments().validate(context: .init(modeFlagsSeen: ["--chat"]))
    }

    test("validate() returns cleanly for any single-mode variant") {
        for flag in ["--chat", "--serve", "--stream", "--benchmark", "--model-info", "--update"] {
            try CLIArguments().validate(context: .init(modeFlagsSeen: [flag]))
        }
    }

    // -- validate() throws on mode conflicts --

    test("validate() throws on two mode flags seen") {
        do {
            try CLIArguments().validate(context: .init(modeFlagsSeen: ["--chat", "--serve"]))
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("cannot combine"))
            try assertTrue(e.message.contains("--chat"))
            try assertTrue(e.message.contains("--serve"))
        }
    }

    test("validate() error preserves flag order (first two win)") {
        do {
            try CLIArguments().validate(context: .init(modeFlagsSeen: ["--chat", "--serve", "--benchmark"]))
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--chat"))
            try assertTrue(e.message.contains("--serve"))
            // The third flag "--benchmark" is NOT mentioned in the error.
            // First-two-wins mirrors the pre-refactor behavior.
            try assertTrue(!e.message.contains("--benchmark"))
        }
    }

    test("validate() throws modeConflict via CLIErrors template") {
        // The error should match the exact wording produced by
        // CLIErrors.modeConflict, confirming validate() reuses the same
        // helper as the in-parse flow.
        do {
            try CLIArguments().validate(context: .init(modeFlagsSeen: ["--serve", "--chat"]))
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            let expected = CLIErrors.modeConflict("--serve", "--chat").message
            try assertEqual(e.message, expected)
        }
    }

    // -- validate() silent-drop guard (#370 audit): input-ignoring modes --

    test("validate() rejects a positional prompt in serve mode") {
        var a = CLIArguments(); a.mode = .serve; a.prompt = "hello"
        do { try a.validate(); try assertTrue(false, "should have thrown") }
        catch let e as CLIParseError { try assertTrue(e.message.contains("positional prompt")) }
    }

    test("validate() rejects -f file content in benchmark mode") {
        var a = CLIArguments(); a.mode = .benchmark; a.fileContents = ["some file"]
        do { try a.validate(); try assertTrue(false, "should have thrown") }
        catch let e as CLIParseError { try assertTrue(e.message.contains("file")) }
    }

    test("validate() rejects -s/--system in serve mode") {
        var a = CLIArguments(); a.mode = .serve; a.systemPrompt = "be terse"
        do { try a.validate(); try assertTrue(false, "should have thrown") }
        catch let e as CLIParseError { try assertTrue(e.message.contains("system")) }
    }

    test("validate() rejects generation tuning in model-info mode") {
        var a = CLIArguments(); a.mode = .modelInfo; a.temperature = 0.5
        do { try a.validate(); try assertTrue(false, "should have thrown") }
        catch let e as CLIParseError { try assertTrue(e.message.contains("temperature")) }
    }

    test("validate() rejects --seed in update mode") {
        var a = CLIArguments(); a.mode = .update; a.seed = 7
        do { try a.validate(); try assertTrue(false, "should have thrown") }
        catch let e as CLIParseError { try assertTrue(e.message.contains("seed")) }
    }

    test("validate() rejects --context-status outside chat") {
        var a = CLIArguments(); a.mode = .single; a.contextStatus = true
        do { try a.validate(); try assertTrue(false, "should have thrown") }
        catch let e as CLIParseError { try assertTrue(e.message.contains("context-status")) }
    }

    // -- validate() still allows the legitimate combinations --

    test("validate() allows --context-status in chat mode") {
        var a = CLIArguments(); a.mode = .chat; a.contextStatus = true
        try a.validate()
    }

    test("validate() allows serve mode with server-consumed flags") {
        var a = CLIArguments(); a.mode = .serve; a.permissive = true; a.retryEnabled = true
        try a.validate()
    }

    test("validate() still allows a prompt and tuning in single mode") {
        var a = CLIArguments(); a.mode = .single; a.prompt = "hello"; a.temperature = 0.5; a.seed = 3
        try a.validate()
    }

    // -- parse() end-to-end still works: parse() should internally invoke validate() --

    test("parse() still throws on mode conflicts (parse internally calls validate)") {
        do {
            _ = try CLIArguments.parse(["--chat", "--serve"])
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("cannot combine"))
        }
    }

    test("parse() accepts a single mode flag without throwing") {
        let args = try CLIArguments.parse(["--chat"])
        try assertEqual(args.mode, .chat)
    }
}
