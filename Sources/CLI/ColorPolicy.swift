// ============================================================================
// ColorPolicy.swift - Pure ANSI color-gating policy.
//
// Kept in ApfelCLI (FoundationModels-free) so the gating rules are
// unit-testable. Output.swift wires the process's real isatty()/env/flag
// state into these pure decisions.
// ============================================================================

import Foundation

/// Pure decisions for whether apfel should emit ANSI color codes.
public enum ColorPolicy {
    /// True when `NO_COLOR` is present AND non-empty.
    ///
    /// Per https://no-color.org and apfel's man page, only a non-empty value
    /// disables color; an empty `NO_COLOR=` must not (#258).
    public static func noColorFromEnv(_ value: String?) -> Bool {
        value.map { !$0.isEmpty } ?? false
    }

    /// Whether to emit ANSI color codes for a given output destination.
    ///
    /// Colorize only when the destination is a TTY and neither `NO_COLOR` nor
    /// `--no-color` is in effect. Callers pass the isatty() result for the
    /// specific file descriptor they are writing to: stdout for stdout writes,
    /// stderr for stderr writes (#249).
    public static func shouldColorize(isTTY: Bool, noColorEnv: Bool, noColorFlag: Bool) -> Bool {
        isTTY && !noColorEnv && !noColorFlag
    }
}
