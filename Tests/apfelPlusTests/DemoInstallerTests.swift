// ============================================================================
// DemoInstallerTests.swift - unit tests for the embedded-demo installer that
// backs `apfel demos <dir>` (#204). Pure: no model, no network.
// ============================================================================

import Foundation
import ApfelCore

func runDemoInstallerTests() {

    test("embeddedDemos includes every shipped demo script") {
        let names = Set(embeddedDemos.map { $0.name })
        for expected in ["cmd", "explain", "gitsum", "mac-narrator", "naming", "oneliner", "port", "wtd"] {
            try assertTrue(names.contains(expected), "embeddedDemos missing \(expected)")
        }
    }

    test("the demo scripts are marked executable, README is not") {
        let byName = Dictionary(uniqueKeysWithValues: embeddedDemos.map { ($0.name, $0) })
        try assertTrue(byName["cmd"]?.isExecutable == true, "cmd should be executable")
        try assertTrue(byName["README.md"]?.isExecutable == false, "README should not be executable")
    }

    test("every embedded demo decodes to non-empty bytes") {
        for demo in embeddedDemos {
            let data = try DemoInstaller.decoded(demo)
            try assertTrue(!data.isEmpty, "\(demo.name) decoded empty")
        }
    }

    test("install writes every demo into the target directory") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apfel-demos-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let installed = try DemoInstaller.install(into: dir)
        try assertEqual(installed.count, embeddedDemos.count)
        for demo in embeddedDemos {
            let path = dir.appendingPathComponent(demo.name).path
            try assertTrue(FileManager.default.fileExists(atPath: path), "\(demo.name) not written")
        }
    }

    test("install sets the executable bit on demo scripts") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apfel-demos-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try DemoInstaller.install(into: dir)
        let cmdPath = dir.appendingPathComponent("cmd").path
        try assertTrue(FileManager.default.isExecutableFile(atPath: cmdPath), "cmd not executable after install")
    }

    test("install writes content matching the embedded bytes") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apfel-demos-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try DemoInstaller.install(into: dir)
        let cmd = embeddedDemos.first { $0.name == "cmd" }!
        let onDisk = try Data(contentsOf: dir.appendingPathComponent("cmd"))
        try assertEqual(onDisk, try DemoInstaller.decoded(cmd))
    }

    test("install with overwrite=false leaves existing files untouched") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apfel-demos-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cmdPath = dir.appendingPathComponent("cmd")
        try "MINE".data(using: .utf8)!.write(to: cmdPath)

        let installed = try DemoInstaller.install(into: dir, overwrite: false)
        let onDisk = String(data: try Data(contentsOf: cmdPath), encoding: .utf8)
        try assertEqual(onDisk, "MINE", "overwrite=false should not clobber existing file")
        try assertTrue(!installed.contains { $0.name == "cmd" }, "cmd should be skipped, not reported installed")
    }
}
