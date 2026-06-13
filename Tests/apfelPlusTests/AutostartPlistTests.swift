// ============================================================================
// AutostartPlistTests.swift - Tests for the pure XML-plist generator that
// `apfel-plus --autostart` uses to install a LaunchAgent.
// ============================================================================

import Foundation
import ApfelCore

func runAutostartPlistTests() {

    func makeDefault() -> AutostartPlist {
        AutostartPlist(
            label: "com.apfel-plus.serve",
            binaryPath: "/usr/local/bin/apfel-plus",
            arguments: ["--serve", "--port", "11434"],
            stdoutPath: "/Users/x/Library/Logs/apfel-plus.out.log",
            stderrPath: "/Users/x/Library/Logs/apfel-plus.err.log",
            workingDirectory: "/Users/x"
        )
    }

    test("rendered plist starts with the XML prolog and DOCTYPE") {
        let xml = makeDefault().render()
        try assertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"),
                       "missing prolog: \(String(xml.prefix(60)))")
        try assertTrue(xml.contains("<!DOCTYPE plist"),
                       "missing DOCTYPE")
        try assertTrue(xml.contains("<plist version=\"1.0\">"),
                       "missing <plist> open tag")
        try assertTrue(xml.hasSuffix("</plist>\n") || xml.hasSuffix("</plist>"),
                       "missing </plist> close")
    }

    test("rendered plist contains the label as a top-level entry") {
        let xml = makeDefault().render()
        try assertTrue(xml.contains("<key>Label</key>"))
        try assertTrue(xml.contains("<string>com.apfel-plus.serve</string>"))
    }

    test("ProgramArguments puts binary path first, then every argument in order") {
        let plist = AutostartPlist(
            label: "com.apfel-plus.serve",
            binaryPath: "/usr/local/bin/apfel-plus",
            arguments: ["--serve", "--port", "1337", "--token", "sk-abc"],
            stdoutPath: "/tmp/out.log",
            stderrPath: "/tmp/err.log",
            workingDirectory: "/Users/x"
        )
        let xml = plist.render()
        // Search for the substring containing the binary plus every arg, in order.
        // We don't pin exact whitespace because that's a rendering detail; the
        // plist parser only cares about element order inside the <array>.
        let argsBlock = xml.components(separatedBy: "<key>ProgramArguments</key>")
            .dropFirst().first ?? ""
        let endIdx = argsBlock.range(of: "</array>")?.lowerBound ?? argsBlock.endIndex
        let argsXML = String(argsBlock[..<endIdx])
        let expected = ["/usr/local/bin/apfel-plus", "--serve", "--port", "1337", "--token", "sk-abc"]
        var cursor = argsXML.startIndex
        for token in expected {
            guard let range = argsXML.range(of: "<string>\(token)</string>", range: cursor..<argsXML.endIndex) else {
                throw TestFailure("argument '\(token)' missing or out of order in ProgramArguments")
            }
            cursor = range.upperBound
        }
    }

    test("XML-special characters in arguments are escaped") {
        let plist = AutostartPlist(
            label: "com.apfel-plus.serve",
            binaryPath: "/usr/local/bin/apfel-plus",
            arguments: ["--serve", "--token", "a&b<c>\"d'e"],
            stdoutPath: "/tmp/out.log",
            stderrPath: "/tmp/err.log",
            workingDirectory: "/Users/x"
        )
        let xml = plist.render()
        // Raw special chars must NOT appear unescaped inside a <string> body.
        // (The XML prolog uses an unescaped '"' inside attribute quotes, so we
        // restrict the search to <string>...</string> regions.)
        try assertTrue(xml.contains("<string>a&amp;b&lt;c&gt;&quot;d&apos;e</string>"),
                       "expected fully escaped string in plist, got: \(xml)")
        try assertTrue(!xml.contains("<string>a&b<c>\"d'e</string>"),
                       "raw unescaped special chars found in plist")
    }

    test("RunAtLoad is true (start at login)") {
        let xml = makeDefault().render()
        // The exact rendering uses <true/> on its own line.
        try assertTrue(xml.contains("<key>RunAtLoad</key>"))
        // The very next non-whitespace element after the RunAtLoad key must be <true/>.
        let afterKey = xml.components(separatedBy: "<key>RunAtLoad</key>").last ?? ""
        let trimmed = afterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try assertTrue(trimmed.hasPrefix("<true/>"),
                       "RunAtLoad should be <true/>, got: \(trimmed.prefix(40))")
    }

    test("KeepAlive restarts on crash but not on a successful exit") {
        let xml = makeDefault().render()
        try assertTrue(xml.contains("<key>KeepAlive</key>"))
        try assertTrue(xml.contains("<key>SuccessfulExit</key>"))
        try assertTrue(xml.contains("<key>Crashed</key>"))
        // Hard-pin the policy: SuccessfulExit=false (only respawn on abnormal
        // termination), Crashed=true (respawn on crash). Future edits that
        // accidentally flip these to a launchd default fall through to this test.
        let keepAliveBlock = xml.components(separatedBy: "<key>KeepAlive</key>")
            .dropFirst().first ?? ""
        let endIdx = keepAliveBlock.range(of: "</dict>")?.lowerBound ?? keepAliveBlock.endIndex
        let kaXML = String(keepAliveBlock[..<endIdx])
        try assertTrue(kaXML.contains("<key>SuccessfulExit</key>\n        <false/>"),
                       "SuccessfulExit must be <false/> inside KeepAlive")
        try assertTrue(kaXML.contains("<key>Crashed</key>\n        <true/>"),
                       "Crashed must be <true/> inside KeepAlive")
    }

    test("log paths land in stdout/stderr entries verbatim") {
        let plist = AutostartPlist(
            label: "com.apfel-plus.serve",
            binaryPath: "/usr/local/bin/apfel-plus",
            arguments: ["--serve"],
            stdoutPath: "/var/log/o.log",
            stderrPath: "/var/log/e.log",
            workingDirectory: "/Users/x"
        )
        let xml = plist.render()
        try assertTrue(xml.contains("<key>StandardOutPath</key>\n    <string>/var/log/o.log</string>"))
        try assertTrue(xml.contains("<key>StandardErrorPath</key>\n    <string>/var/log/e.log</string>"))
    }

    test("WorkingDirectory is set") {
        let plist = AutostartPlist(
            label: "com.apfel-plus.serve",
            binaryPath: "/usr/local/bin/apfel-plus",
            arguments: ["--serve"],
            stdoutPath: "/tmp/out.log",
            stderrPath: "/tmp/err.log",
            workingDirectory: "/Users/x"
        )
        let xml = plist.render()
        try assertTrue(xml.contains("<key>WorkingDirectory</key>\n    <string>/Users/x</string>"))
    }

    test("ThrottleInterval renders an integer, not a string") {
        let xml = makeDefault().render()
        try assertTrue(xml.contains("<key>ThrottleInterval</key>"))
        // Must use <integer>, not <string>, or launchd rejects the plist.
        try assertTrue(xml.contains("<integer>10</integer>"))
    }

    test("default plist path is ~/Library/LaunchAgents/<label>.plist") {
        let path = AutostartPlist.defaultInstallPath(
            homeDirectory: "/Users/x",
            label: "com.apfel-plus.serve"
        )
        try assertEqual(path, "/Users/x/Library/LaunchAgents/com.apfel-plus.serve.plist")
    }

    test("default log paths land under ~/Library/Logs") {
        let stdout = AutostartPlist.defaultStdoutPath(homeDirectory: "/Users/x")
        let stderr = AutostartPlist.defaultStderrPath(homeDirectory: "/Users/x")
        try assertEqual(stdout, "/Users/x/Library/Logs/apfel-plus.out.log")
        try assertEqual(stderr, "/Users/x/Library/Logs/apfel-plus.err.log")
    }

    test("default label is com.apfel-plus.serve") {
        try assertEqual(AutostartPlist.defaultLabel, "com.apfel-plus.serve")
    }

    test("rendered plist round-trips through plutil") {
        // Functional check: the rendered plist must be valid XML plist syntax,
        // not just contain the right substrings. plutil -lint reads from a path
        // so write a temp file.
        let xml = makeDefault().render()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("autostart-plist-test-\(UUID().uuidString).plist")
        try xml.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        proc.arguments = ["-lint", tmp.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw TestFailure("plutil -lint rejected the rendered plist: \(output)")
        }
    }
}
