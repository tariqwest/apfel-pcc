// ============================================================================
// CodeFlagTests.swift - Unit tests for --code (#373)
// Parse behavior and every cross-flag rule from the issue's interaction
// matrix. The extraction itself is covered by CodeCropperTests.
// ============================================================================

import Foundation
import ApfelCore
import ApfelCLI

private let oneTurn = "[{\"role\":\"user\",\"content\":\"battery one-liner\"}]"

func runCodeFlagTests() {

    // ========================================================================
    // MARK: - Parse
    // ========================================================================

    test("--code parses with a positional prompt") {
        let args = try CLIArguments.parse(["--code", "python calculator"])
        try assertEqual(args.mode, .single)
        try assertTrue(args.codeOnly)
        try assertEqual(args.prompt, "python calculator")
    }

    test("codeOnly defaults to false") {
        let args = try CLIArguments.parse(["hello"])
        try assertTrue(!args.codeOnly)
    }

    test("--code is a known flag (flag-after-prompt warning machinery)") {
        try assertTrue(CLIArguments.isKnownFlag("--code"))
    }

    // ========================================================================
    // MARK: - Compositions (allowed per #373 matrix)
    // ========================================================================

    test("--code composes with -s system prompt") {
        let args = try CLIArguments.parse(["--code", "-s", "you are a bash expert", "battery one-liner"])
        try assertTrue(args.codeOnly)
        try assertEqual(args.systemPrompt, "you are a bash expert")
    }

    test("--code composes with --messages") {
        let args = try CLIArguments.parse(["--code", "--messages", "conv.json"], readFile: { _ in oneTurn })
        try assertTrue(args.codeOnly)
        try assertNotNil(args.messagesJSON)
        try assertEqual(args.mode, .single)
    }

    test("--code composes with -o json") {
        let args = try CLIArguments.parse(["--code", "-o", "json", "fizzbuzz"])
        try assertTrue(args.codeOnly)
        try assertEqual(args.outputFormat, .json)
    }

    test("--code composes with --retry and --max-tokens") {
        let args = try CLIArguments.parse(["--code", "--retry", "--max-tokens", "200", "fizzbuzz"])
        try assertTrue(args.codeOnly)
        try assertTrue(args.retryEnabled)
        try assertEqual(args.maxTokens, 200)
    }

    // ========================================================================
    // MARK: - Rejections (usage error, #370 doctrine: nothing silently dropped)
    // ========================================================================

    test("--code --stream throws") {
        do {
            _ = try CLIArguments.parse(["--code", "--stream", "hi"])
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--code"))
            try assertTrue(e.message.contains("stream"))
        }
    }

    test("--code --chat throws") {
        do {
            _ = try CLIArguments.parse(["--code", "--chat"])
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--code"))
        }
    }

    test("--code --serve throws") {
        do {
            _ = try CLIArguments.parse(["--code", "--serve"])
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--code"))
        }
    }

    test("--code --benchmark throws") {
        do {
            _ = try CLIArguments.parse(["--code", "--benchmark"])
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--code"))
        }
    }

    test("--code --count-tokens throws") {
        do {
            _ = try CLIArguments.parse(["--code", "--count-tokens", "hi"])
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--code"))
        }
    }

    test("--code --model-info throws") {
        do {
            _ = try CLIArguments.parse(["--code", "--model-info"])
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--code"))
        }
    }

    test("--code --schema throws (contradictory output contracts)") {
        do {
            _ = try CLIArguments.parse(
                ["--code", "--schema", "s.json", "hi"],
                readFile: { _ in "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\"}}}" })
            try assertTrue(false, "should have thrown")
        } catch let e as CLIParseError {
            try assertTrue(e.message.contains("--code"))
            try assertTrue(e.message.contains("--schema"))
        }
    }
}
