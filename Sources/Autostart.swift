// ============================================================================
// Autostart.swift - `apfel-plus --autostart` implementation.
// Renders the LaunchAgent plist (via ApfelCore.AutostartPlist), writes it
// under ~/Library/LaunchAgents/, and (re)loads it via launchctl.
// ============================================================================

import Foundation
import ApfelCore
import ApfelCLI

/// Build the argv list that the LaunchAgent should run. Mirrors the user's
/// `--autostart …` invocation: we drop the autostart mode itself and slot
/// `--serve` in front of every other flag the user passed, so the agent ends
/// up running the same `--serve` config they asked for.
func autostartServerArguments(from parsed: CLIArguments) -> [String] {
    var args: [String] = ["--serve"]
    args.append("--port"); args.append(String(parsed.serverPort))
    args.append("--host"); args.append(parsed.serverHost)
    if parsed.serverCORS {
        args.append("--cors")
    }
    if let token = parsed.serverToken, !token.isEmpty {
        args.append("--token"); args.append(token)
    }
    if parsed.serverTokenAuto && parsed.serverToken == nil {
        args.append("--token-auto")
    }
    if parsed.serverPublicHealth {
        args.append("--public-health")
    }
    if !parsed.serverOriginCheckEnabled {
        args.append("--no-origin-check")
    }
    if !parsed.serverAllowedOrigins.isEmpty {
        args.append("--allowed-origins")
        args.append(parsed.serverAllowedOrigins.joined(separator: ","))
    }
    if parsed.serverMaxConcurrent != 5 {
        args.append("--max-concurrent"); args.append(String(parsed.serverMaxConcurrent))
    }
    for path in parsed.mcpServerPaths {
        args.append("--mcp"); args.append(path)
    }
    if parsed.mcpTimeoutSeconds != 5 {
        args.append("--mcp-timeout"); args.append(String(parsed.mcpTimeoutSeconds))
    }
    if let mcpToken = parsed.mcpBearerToken, !mcpToken.isEmpty {
        args.append("--mcp-token"); args.append(mcpToken)
    }
    if parsed.permissive {
        args.append("--permissive")
    }
    if parsed.debug {
        args.append("--debug")
    }
    return args
}

/// Run the full install: render plist, write it under
/// `~/Library/LaunchAgents/`, bootstrap (or kickstart) the agent, verify it's
/// running.
func performAutostart(parsed: CLIArguments) throws {
    let home = NSHomeDirectory()
    let uid = getuid()

    // Resolve our own absolute path. Using CommandLine.arguments[0] keeps the
    // dependency on Bundle out of the picture; we resolve to a real path so
    // the plist survives a `swift package clean` if the user ran a dev build.
    let binaryPath = resolvedExecutablePath()

    // Warn loudly when the binary lives inside a build tree - that path will
    // disappear the next time someone runs `swift package clean` or rebuilds,
    // leaving launchd retrying a missing binary every 10 seconds forever.
    if binaryPath.contains("/.build/") {
        printStderr("\(styled("apfel-plus:", .yellow)) warning: installing autostart from a build-tree binary at \(binaryPath).")
        printStderr("  Install the binary to a stable path first (e.g. /usr/local/bin) and re-run --autostart.")
        printStderr("  Example: install -m 0755 \(binaryPath) /usr/local/bin/apfel-plus")
    }

    let label = AutostartPlist.defaultLabel
    let plistPath = AutostartPlist.defaultInstallPath(homeDirectory: home, label: label)
    let stdoutPath = AutostartPlist.defaultStdoutPath(homeDirectory: home)
    let stderrPath = AutostartPlist.defaultStderrPath(homeDirectory: home)

    let plist = AutostartPlist(
        label: label,
        binaryPath: binaryPath,
        arguments: autostartServerArguments(from: parsed),
        stdoutPath: stdoutPath,
        stderrPath: stderrPath,
        workingDirectory: home
    )

    let fm = FileManager.default
    try fm.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent,
                           withIntermediateDirectories: true, attributes: nil)
    try fm.createDirectory(atPath: (stdoutPath as NSString).deletingLastPathComponent,
                           withIntermediateDirectories: true, attributes: nil)

    // Write atomically so a parallel `launchctl bootstrap` never sees a half-
    // written plist. `0644` matches what `cp` would produce.
    let rendered = plist.render()
    try rendered.write(toFile: plistPath, atomically: true, encoding: .utf8)

    printStderr("\(styled("apfel-plus:", .green)) wrote \(plistPath)")

    let serviceTarget = "gui/\(uid)/\(label)"
    // If a previous version is loaded, bootout first - bootstrap on an
    // already-loaded label errors with "service already loaded". We don't
    // care if the bootout fails (it returns non-zero when the label isn't
    // loaded, which is the common first-install case).
    _ = runSilently("/bin/launchctl", ["bootout", serviceTarget])

    let bootstrapResult = runCapturing("/bin/launchctl",
        ["bootstrap", "gui/\(uid)", plistPath])
    if bootstrapResult.status != 0 {
        printError("launchctl bootstrap failed (exit \(bootstrapResult.status)): \(bootstrapResult.combinedOutput)")
        exit(exitRuntimeError)
    }

    // Wait briefly for the agent to come up. `launchctl print` is more
    // reliable than `launchctl list` for newer macOS releases.
    let stateOK = pollAgentRunning(label: label, uid: uid, timeoutSeconds: 5)

    printStderr("\(styled("apfel-plus:", .green)) bootstrap ok — \(serviceTarget)")
    printStderr("  RunAtLoad   : starts at login")
    printStderr("  KeepAlive   : respawns on abnormal exit (10s throttle)")
    printStderr("  stdout log  : \(stdoutPath)")
    printStderr("  stderr log  : \(stderrPath)")
    printStderr("")
    printStderr("Manage:")
    printStderr("  launchctl print     \(serviceTarget)")
    printStderr("  launchctl kickstart -k \(serviceTarget)   # restart")
    printStderr("  launchctl bootout   \(serviceTarget)   # stop and unload")

    if !stateOK {
        printStderr("")
        printStderr("\(styled("apfel-plus:", .yellow)) the agent was bootstrapped but is not yet reporting as running.")
        printStderr("  Inspect with: launchctl print \(serviceTarget)")
        printStderr("  Tail stderr:  tail -F \(stderrPath)")
    }
}

private func pollAgentRunning(label: String, uid: uid_t, timeoutSeconds: Int) -> Bool {
    let target = "gui/\(uid)/\(label)"
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
    while Date() < deadline {
        let result = runCapturing("/bin/launchctl", ["print", target])
        if result.status == 0,
           result.combinedOutput.contains("state = running"),
           result.combinedOutput.contains("pid = ") {
            return true
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
    return false
}

/// Return the resolved absolute path of the currently-running executable.
/// Uses `_NSGetExecutablePath` for an authoritative answer, then resolves
/// any `..` / symlinks via `URL.standardizedFileURL` so the plist gets a
/// path launchd can exec without surprises.
private func resolvedExecutablePath() -> String {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buf = [UInt8](repeating: 0, count: Int(size) + 1)
    let rc = buf.withUnsafeMutableBufferPointer { ptr -> Int32 in
        ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: ptr.count) { c in
            _NSGetExecutablePath(c, &size)
        }
    }
    let raw: String
    if rc == 0 {
        let nullTerm = buf.firstIndex(of: 0) ?? buf.endIndex
        raw = String(decoding: buf[..<nullTerm], as: UTF8.self)
    } else {
        // Last resort fallback - argv[0] without resolution. Should never hit
        // this on macOS, but degrade gracefully rather than crashing.
        raw = CommandLine.arguments.first ?? "/usr/local/bin/apfel-plus"
    }
    let url = URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL
    return url.path
}

private struct ProcessResult {
    let status: Int32
    let combinedOutput: String
}

private func runCapturing(_ path: String, _ args: [String]) -> ProcessResult {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do {
        try proc.run()
    } catch {
        return ProcessResult(status: -1, combinedOutput: "could not exec \(path): \(error)")
    }
    proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return ProcessResult(
        status: proc.terminationStatus,
        combinedOutput: String(data: data, encoding: .utf8) ?? ""
    )
}

@discardableResult
private func runSilently(_ path: String, _ args: [String]) -> Int32 {
    runCapturing(path, args).status
}
