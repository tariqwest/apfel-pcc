// ============================================================================
// InstallMethodTests.swift — Coverage for path-based install method detection.
//
// Real filesystem test: lay down a synthetic <prefix>/bin/apfel-plus layout in a
// temp dir, then assert detection picks the right enum case. No mocking, no DI.
// ============================================================================

import Foundation
import ApfelCLI

func runInstallMethodTests() {
    test("Homebrew Cellar path -> .homebrew") {
        let path = "/opt/homebrew/Cellar/apfel-plus/1.3.5/bin/apfel-plus"
        try assertEqual(detectInstallMethod(binaryPath: path), .homebrew)
    }

    test("Homebrew opt symlink path -> .homebrew") {
        let path = "/opt/homebrew/opt/apfel-plus/bin/apfel-plus"
        try assertEqual(detectInstallMethod(binaryPath: path), .homebrew)
    }

    test("Intel Homebrew path -> .homebrew") {
        let path = "/usr/local/homebrew/Cellar/apfel-plus/1.3.5/bin/apfel-plus"
        try assertEqual(detectInstallMethod(binaryPath: path), .homebrew)
    }

    test("MacPorts default prefix with var/macports marker -> .macports") {
        let tmp = makeTempPrefix()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("var/macports"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("bin/apfel-plus").path, contents: nil)

        let result = detectInstallMethod(binaryPath: tmp.appendingPathComponent("bin/apfel-plus").path)
        try assertEqual(result, .macports)
    }

    test("Custom MacPorts prefix is detected the same way") {
        let tmp = makeTempPrefix()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let prefix = tmp.appendingPathComponent("opt/macports-custom")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("var/macports"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: prefix.appendingPathComponent("bin/apfel-plus").path, contents: nil)

        let result = detectInstallMethod(binaryPath: prefix.appendingPathComponent("bin/apfel-plus").path)
        try assertEqual(result, .macports)
    }

    test("MacPorts marker that is a file (not a directory) -> .source") {
        let tmp = makeTempPrefix()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("var"), withIntermediateDirectories: true)
        // var/macports as a regular file, not a directory — should NOT count as MacPorts
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("var/macports").path, contents: nil)
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("bin/apfel-plus").path, contents: nil)

        let result = detectInstallMethod(binaryPath: tmp.appendingPathComponent("bin/apfel-plus").path)
        try assertEqual(result, .source)
    }

    test("Manual install at /usr/local/bin -> .source") {
        // Nothing on disk at /usr/local/var/macports, so this resolves to .source.
        // (If a user happens to have MacPorts at /usr/local with apfel-plus hand-installed
        // there too, MacPorts wins — acceptable edge case.)
        let result = detectInstallMethod(binaryPath: "/usr/local/bin/apfel-plus")
        // Real filesystem on a dev machine has no /usr/local/var/macports — assert source.
        var isDir: ObjCBool = false
        let macportsExists = FileManager.default.fileExists(atPath: "/usr/local/var/macports", isDirectory: &isDir) && isDir.boolValue
        if macportsExists {
            try assertEqual(result, .macports)
        } else {
            try assertEqual(result, .source)
        }
    }

    test("Arbitrary source path -> .source") {
        let tmp = makeTempPrefix()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("bin"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("bin/apfel-plus").path, contents: nil)

        let result = detectInstallMethod(binaryPath: tmp.appendingPathComponent("bin/apfel-plus").path)
        try assertEqual(result, .source)
    }
}

func runHomebrewPrefixTests() {
    // #260: derive the brew prefix from the resolved binary path.
    test("Apple Silicon Cellar path -> /opt/homebrew") {
        try assertEqual(
            homebrewPrefix(fromBinaryPath: "/opt/homebrew/Cellar/apfel/1.6.1/bin/apfel"),
            "/opt/homebrew")
    }

    test("Apple Silicon opt symlink path -> /opt/homebrew") {
        try assertEqual(
            homebrewPrefix(fromBinaryPath: "/opt/homebrew/opt/apfel/bin/apfel"),
            "/opt/homebrew")
    }

    test("Intel Homebrew Cellar path -> /usr/local/homebrew") {
        try assertEqual(
            homebrewPrefix(fromBinaryPath: "/usr/local/homebrew/Cellar/apfel/1.3.5/bin/apfel"),
            "/usr/local/homebrew")
    }

    test("Custom prefix Cellar path -> custom prefix") {
        try assertEqual(
            homebrewPrefix(fromBinaryPath: "/Users/me/homebrew/Cellar/apfel/1.6.1/bin/apfel"),
            "/Users/me/homebrew")
    }

    test("Non-Homebrew path -> nil") {
        try assertNil(homebrewPrefix(fromBinaryPath: "/usr/local/bin/apfel"))
    }

    test("Source build path -> nil") {
        try assertNil(homebrewPrefix(fromBinaryPath: "/Users/me/dev/apfel/.build/release/apfel"))
    }
}

private func makeTempPrefix() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("apfel-plus-install-method-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
