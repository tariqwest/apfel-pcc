// ============================================================================
// ColorPolicyTests.swift - Coverage for the pure ANSI color-gating policy.
// ============================================================================

import Foundation
import ApfelCLI

func runColorPolicyTests() {
    // #258: NO_COLOR only counts when non-empty.
    test("NO_COLOR unset -> color allowed") {
        try assertEqual(ColorPolicy.noColorFromEnv(nil), false)
    }

    test("NO_COLOR empty string -> color allowed") {
        try assertEqual(ColorPolicy.noColorFromEnv(""), false)
    }

    test("NO_COLOR=1 -> color disabled") {
        try assertEqual(ColorPolicy.noColorFromEnv("1"), true)
    }

    test("NO_COLOR=any-non-empty -> color disabled") {
        try assertEqual(ColorPolicy.noColorFromEnv("true"), true)
    }

    // #249: colorization keys off the destination fd's own TTY-ness.
    test("colorize when TTY and no suppressors") {
        try assertEqual(ColorPolicy.shouldColorize(isTTY: true, noColorEnv: false, noColorFlag: false), true)
    }

    test("no color when destination is not a TTY") {
        try assertEqual(ColorPolicy.shouldColorize(isTTY: false, noColorEnv: false, noColorFlag: false), false)
    }

    test("no color when NO_COLOR set even on a TTY") {
        try assertEqual(ColorPolicy.shouldColorize(isTTY: true, noColorEnv: true, noColorFlag: false), false)
    }

    test("no color when --no-color set even on a TTY") {
        try assertEqual(ColorPolicy.shouldColorize(isTTY: true, noColorEnv: false, noColorFlag: true), false)
    }
}
