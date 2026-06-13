// ============================================================================
// AutostartPlist.swift - Pure XML-plist generator for `apfel-plus --autostart`.
//
// Lives in ApfelCore (no FoundationModels / Foundation-only) so the generated
// plist can be unit-tested. The main target writes the rendered string to
// ~/Library/LaunchAgents/ and runs `launchctl bootstrap`.
// ============================================================================

import Foundation

/// Description of the LaunchAgent plist that `apfel-plus --autostart` installs.
/// `render()` returns the full XML document; the executable target wires this
/// into the file system and `launchctl`.
public struct AutostartPlist: Sendable, Equatable, Hashable {
    /// Reverse-DNS launchd label, e.g. `com.apfel-plus.serve`.
    public let label: String
    /// Absolute path to the `apfel-plus` binary the agent runs.
    public let binaryPath: String
    /// Arguments passed to the binary (e.g. `["--serve", "--port", "1337"]`).
    /// `binaryPath` is added as `argv[0]` automatically.
    public let arguments: [String]
    /// Where launchd writes the agent's stdout.
    public let stdoutPath: String
    /// Where launchd writes the agent's stderr.
    public let stderrPath: String
    /// Working directory for the agent process.
    public let workingDirectory: String

    public init(
        label: String,
        binaryPath: String,
        arguments: [String],
        stdoutPath: String,
        stderrPath: String,
        workingDirectory: String
    ) {
        self.label = label
        self.binaryPath = binaryPath
        self.arguments = arguments
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.workingDirectory = workingDirectory
    }

    // MARK: - Sensible defaults

    /// Canonical label used by the autostart command. Not tied to any user -
    /// the agent runs in the user's GUI domain so the home path scopes it.
    public static let defaultLabel = "com.apfel-plus.serve"

    /// Default plist install location under the user's home.
    public static func defaultInstallPath(homeDirectory: String, label: String = defaultLabel) -> String {
        "\(homeDirectory)/Library/LaunchAgents/\(label).plist"
    }

    /// Default stdout log path.
    public static func defaultStdoutPath(homeDirectory: String) -> String {
        "\(homeDirectory)/Library/Logs/apfel-plus.out.log"
    }

    /// Default stderr log path.
    public static func defaultStderrPath(homeDirectory: String) -> String {
        "\(homeDirectory)/Library/Logs/apfel-plus.err.log"
    }

    // MARK: - XML rendering

    /// Produce the full launchd plist as an XML string. The output is
    /// `plutil`-clean and ready to write to disk.
    public func render() -> String {
        var argv: [String] = [binaryPath]
        argv.append(contentsOf: arguments)
        let argvXML = argv
            .map { "        <string>\(escape($0))</string>" }
            .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(escape(label))</string>

            <key>ProgramArguments</key>
            <array>
        \(argvXML)
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
                <key>Crashed</key>
                <true/>
            </dict>

            <key>ThrottleInterval</key>
            <integer>10</integer>

            <key>ProcessType</key>
            <string>Interactive</string>

            <key>StandardOutPath</key>
            <string>\(escape(stdoutPath))</string>
            <key>StandardErrorPath</key>
            <string>\(escape(stderrPath))</string>

            <key>WorkingDirectory</key>
            <string>\(escape(workingDirectory))</string>

            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
            </dict>
        </dict>
        </plist>
        """ + "\n"
    }

    /// Minimal XML escaping for plist string bodies. Covers the five XML
    /// predefined entities (`&`, `<`, `>`, `"`, `'`). `&` must be first so we
    /// don't double-escape the entities we just wrote.
    private func escape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&apos;")
        return out
    }
}
