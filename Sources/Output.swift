// ============================================================================
// Output.swift — Terminal output helpers (colors, stderr, formatting)
// Part of apfel-plus — Apple Intelligence from the command line
// ============================================================================

import Foundation
import ApfelCore
import ApfelCLI

// MARK: - Global State
// Set during argument parsing (before any async work) and read during execution.
// Marked `nonisolated(unsafe)` because Swift 6 strict concurrency treats global
// mutable state as @MainActor-isolated. Safe here: single-threaded CLI, write-once.

/// True if the NO_COLOR environment variable is set to a non-empty value
/// (https://no-color.org). An empty `NO_COLOR=` must not disable color (#258).
let noColorEnv = ColorPolicy.noColorFromEnv(ProcessInfo.processInfo.environment["NO_COLOR"])

/// True if --no-color flag was passed
nonisolated(unsafe) var noColorFlag = false

/// Output format: plain (default) or json
nonisolated(unsafe) var outputFormat: OutputFormat = .plain

/// True if --quiet flag was passed (suppresses headers, prompts, chrome)
nonisolated(unsafe) var quietMode = false

// MARK: - ANSI Colors

enum ANSIColor: String, Sendable {
    case reset   = "\u{001B}[0m"
    case bold    = "\u{001B}[1m"
    case dim     = "\u{001B}[2m"
    case cyan    = "\u{001B}[36m"
    case green   = "\u{001B}[32m"
    case yellow  = "\u{001B}[33m"
    case magenta = "\u{001B}[35m"
    case red     = "\u{001B}[31m"
}

/// Wrap `text` in ANSI codes when `colorize` is true; otherwise return it plain.
func applyStyle(_ text: String, colorize: Bool, _ colors: [ANSIColor]) -> String {
    guard colorize else { return text }
    let prefix = colors.map(\.rawValue).joined()
    return "\(prefix)\(text)\(ANSIColor.reset.rawValue)"
}

/// Apply ANSI color codes to text destined for stdout. Returns plain text if
/// stdout is not a TTY, NO_COLOR is set, or --no-color was passed.
func styled(_ text: String, _ colors: ANSIColor...) -> String {
    applyStyle(text, colorize: ColorPolicy.shouldColorize(
        isTTY: isatty(STDOUT_FILENO) != 0, noColorEnv: noColorEnv, noColorFlag: noColorFlag), colors)
}

/// Apply ANSI color codes to text destined for stderr. Keys colorization off
/// stderr's own TTY-ness so redirected stderr (e.g. `apfel ... 2>err.log`) stays
/// escape-free even when stdout is a terminal (#249).
func styledErr(_ text: String, _ colors: ANSIColor...) -> String {
    applyStyle(text, colorize: ColorPolicy.shouldColorize(
        isTTY: isatty(STDERR_FILENO) != 0, noColorEnv: noColorEnv, noColorFlag: noColorFlag), colors)
}

// MARK: - Output Helpers

let stderr = FileHandle.standardError

/// Print a message to stderr with a trailing newline.
func printStderr(_ message: String) {
    stderr.write(Data("\(message)\n".utf8))
}

/// Print a styled error message to stderr. Format: "error: <message>"
func printError(_ message: String) {
    stderr.write(Data("\(styledErr("error:", .red, .bold)) \(message)\n".utf8))
}

// MARK: - Debug Output

/// Print a debug message to stderr. Zero-cost when debug logging is disabled.
func debugLog(_ message: @autoclosure () -> String) {
    guard ApfelDebugConfiguration.isEnabled else { return }
    printStderr("\(styledErr("debug:", .dim)) \(message())")
}

/// Print a categorized debug message to stderr. Zero-cost when debug logging is disabled.
func debugLog(_ category: String, _ message: @autoclosure () -> String) {
    guard ApfelDebugConfiguration.isEnabled else { return }
    printStderr("\(styledErr("debug[\(category)]:", .dim)) \(message())")
}
