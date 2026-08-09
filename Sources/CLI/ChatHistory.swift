// ============================================================================
// ChatHistory.swift - Persistent chat-history file policy (pure, testable)
// Part of ApfelCLI - decides *whether* and *where* chat history persists.
//
// The actual libedit read_history/write_history wiring lives in the root
// target (Sources/ChatLineEditor.swift), which is not unit-testable. The
// opt-in decision - the security-relevant part - lives here so apfel-tests
// can cover it.
// ============================================================================

import Foundation

/// Persistent chat-history policy for interactive `--chat` sessions.
///
/// History persistence is OFF by default: chat history is in-memory only
/// unless the user explicitly opts in by setting `APFEL_HISTFILE` to a path.
/// This is the honest, secure default - apfel never writes a transcript of
/// your prompts to disk unless you ask it to.
public enum ChatHistory {

    /// Environment variable that opts into persistent history and names the file.
    public static let envVar = "APFEL_HISTFILE"

    /// Maximum number of history entries retained in the file (matches the
    /// in-memory `stifle_history` bound so the file stays bounded).
    public static let maxEntries = 500

    /// Resolve the history file path from the environment.
    ///
    /// Returns `nil` (in-memory-only, the default) unless `APFEL_HISTFILE` is
    /// set to a non-empty value. A set-but-blank value (empty or whitespace)
    /// is treated as absence, consistent with how the parser treats other
    /// `APFEL_*` vars. A leading `~` is expanded to the user's home directory
    /// so `APFEL_HISTFILE=~/.apfel_history` works without shell expansion.
    public static func filePath(env: [String: String]) -> String? {
        guard let raw = env[envVar] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).expandingTildeInPath
    }
}
