// ============================================================================
// ManPageTests.swift - Unit tests for the man/apfel-plus.1.in troff source.
// Checks that the committed man-page template is well-formed.
// Drift-prevention (flag coverage vs --help) lives in the integration suite
// since it needs the built binary.
// ============================================================================

import Foundation

func runManPageTests() {

    // Locate the repo root by walking up from the current working directory.
    // swift test runs from the package root, so this is usually unnecessary,
    // but fall back to walking up in case it is invoked differently.
    func findRepoRoot() -> URL {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<6 {
            let marker = dir.appendingPathComponent("Package.swift")
            if fm.fileExists(atPath: marker.path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: fm.currentDirectoryPath)
    }

    let root = findRepoRoot()
    let manPath = root.appendingPathComponent("man/apfel-plus.1.in").path

    test("man/apfel-plus.1.in exists") {
        try assertTrue(FileManager.default.fileExists(atPath: manPath),
                       "expected troff source at \(manPath)")
    }

    test("man page source is non-empty") {
        let data = try? Data(contentsOf: URL(fileURLWithPath: manPath))
        try assertNotNil(data)
        try assertTrue((data?.count ?? 0) > 500,
                       "man page source should be substantial, got \(data?.count ?? 0) bytes")
    }

    test("man page contains required sections") {
        let text = (try? String(contentsOfFile: manPath, encoding: .utf8)) ?? ""
        let requiredSections = [
            ".SH NAME",
            ".SH SYNOPSIS",
            ".SH DESCRIPTION",
            ".SH OPTIONS",
            ".SH \"CONTEXT OPTIONS\"",
            ".SH \"SERVER OPTIONS\"",
            ".SH ENVIRONMENT",
            ".SH \"EXIT STATUS\"",
            ".SH FILES",
            ".SH EXAMPLES",
            ".SH BUGS",
            ".SH \"SEE ALSO\"",
            ".SH AUTHORS",
        ]
        for section in requiredSections {
            try assertTrue(text.contains(section),
                           "missing section header: \(section)")
        }
    }

    test("man page has .TH header with @VERSION@ placeholder") {
        let text = (try? String(contentsOfFile: manPath, encoding: .utf8)) ?? ""
        try assertTrue(text.contains(".TH APFEL-PLUS 1"),
                       "missing .TH header")
        try assertTrue(text.contains("@VERSION@"),
                       "expected @VERSION@ placeholder in .TH header")
    }

    test("man page @VERSION@ appears exactly once") {
        let text = (try? String(contentsOfFile: manPath, encoding: .utf8)) ?? ""
        let count = text.components(separatedBy: "@VERSION@").count - 1
        try assertEqual(count, 1, "@VERSION@ should appear exactly once, found \(count)")
    }

    test("man page has no stray @PLACEHOLDER@ besides @VERSION@") {
        let text = (try? String(contentsOfFile: manPath, encoding: .utf8)) ?? ""
        let pattern = try NSRegularExpression(pattern: "@[A-Z_]+@")
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        for match in matches {
            let placeholder = String(text[Range(match.range, in: text)!])
            try assertEqual(placeholder, "@VERSION@",
                            "unexpected placeholder: \(placeholder)")
        }
    }

    test("man page starts with a properly formed .TH line") {
        let text = (try? String(contentsOfFile: manPath, encoding: .utf8)) ?? ""
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        // Expect: .TH APFEL-PLUS 1 "YYYY-MM-DD" "apfel-plus @VERSION@" "User Commands"
        try assertTrue(firstLine.hasPrefix(".TH APFEL-PLUS 1"),
                       "first line should be .TH header, got: \(firstLine)")
        try assertTrue(firstLine.contains("\"User Commands\""),
                       "expected section label \"User Commands\" in .TH")
    }

    test("man page documents every declared exit code") {
        let text = (try? String(contentsOfFile: manPath, encoding: .utf8)) ?? ""
        for code in ["0", "1", "2", "3", "4", "5", "6"] {
            try assertTrue(text.contains(".B \(code)\n"),
                           "EXIT STATUS section missing \".B \(code)\" entry")
        }
    }
}
