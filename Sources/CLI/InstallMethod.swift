// ============================================================================
// InstallMethod.swift — Detect how the apfel-plus binary was installed.
//
// The self-update flow (`apfel-plus --update`) prints different instructions per
// install method. Detection is path-based (no network, no shell-outs), which
// keeps it cheap, fast, and offline.
// ============================================================================

import Foundation

public enum InstallMethod: Equatable, Sendable {
    case homebrew
    case macports
    case source
}

/// Classify how a binary was installed based on its absolute (symlink-resolved)
/// path on disk.
///
/// - `homebrew`: path lives under `*/homebrew/Cellar/apfel-plus/` or `*/homebrew/opt/apfel-plus/`.
/// - `macports`: binary lives at `<prefix>/bin/apfel-plus` and `<prefix>/var/macports`
///   exists as a directory. This is the canonical MacPorts marker and works for
///   the default `/opt/local` prefix and custom prefixes alike.
/// - `source`: anything else (manual `make install`, `swift build`, custom dir).
public func detectInstallMethod(
    binaryPath: String,
    fileManager: FileManager = .default
) -> InstallMethod {
    if binaryPath.contains("/homebrew/Cellar/apfel-plus/") || binaryPath.contains("/homebrew/opt/apfel-plus/") {
        return .homebrew
    }

    let prefixURL = URL(fileURLWithPath: binaryPath)
        .deletingLastPathComponent()  // <prefix>/bin
        .deletingLastPathComponent()  // <prefix>
    let macportsMarker = prefixURL.appendingPathComponent("var/macports").path
    var isDir: ObjCBool = false
    if fileManager.fileExists(atPath: macportsMarker, isDirectory: &isDir), isDir.boolValue {
        return .macports
    }

    return .source
}

/// Derive the Homebrew prefix from a resolved apfel binary path.
///
/// For a Cellar install `<prefix>/Cellar/apfel/<version>/bin/apfel` or an opt
/// symlink `<prefix>/opt/apfel/bin/apfel`, returns `<prefix>` - e.g.
/// `/opt/homebrew` (Apple Silicon default), `/usr/local` (Intel default), or a
/// custom prefix such as `/Users/me/homebrew`. `brew` and the installed `apfel`
/// then live at `<prefix>/bin/brew` and `<prefix>/bin/apfel`.
///
/// Returns nil when the path is not a recognizable Homebrew layout, so callers
/// can fall back to locating `brew` on `PATH` instead of hardcoding a prefix
/// (#260).
public func homebrewPrefix(fromBinaryPath path: String) -> String? {
    for marker in ["/Cellar/apfel/", "/opt/apfel/"] {
        if let range = path.range(of: marker) {
            let prefix = String(path[path.startIndex..<range.lowerBound])
            return prefix.isEmpty ? nil : prefix
        }
    }
    return nil
}
