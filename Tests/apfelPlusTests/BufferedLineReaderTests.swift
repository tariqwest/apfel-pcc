// ============================================================================
// BufferedLineReaderTests.swift — Unit tests for BufferedLineReader
// Uses real UNIX pipes to test the buffered read logic end-to-end.
// ============================================================================

import Foundation
import ApfelCore
#if canImport(Darwin)
import Darwin
#endif

func runBufferedLineReaderTests() {

    /// Helper: create a pipe pair and return (readFD, writeFD).
    func makePipe() -> (Int32, Int32) {
        var fds: [Int32] = [0, 0]
        pipe(&fds)
        return (fds[0], fds[1])
    }

    /// Helper: write a string to a file descriptor.
    func writeString(_ fd: Int32, _ string: String) {
        let data = Array(string.utf8)
        data.withUnsafeBufferPointer { buf in
            _ = Darwin.write(fd, buf.baseAddress, buf.count)
        }
    }

    // -- Basic single-line reads --

    test("reads a single line terminated by newline") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        writeString(writeFD, "hello world\n")

        let reader = BufferedLineReader(fileDescriptor: readFD)
        let line = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        try assertEqual(line, "hello world")
    }

    test("reads multiple lines sequentially") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        writeString(writeFD, "line one\nline two\nline three\n")

        let reader = BufferedLineReader(fileDescriptor: readFD)
        let first = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        let second = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        let third = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        try assertEqual(first, "line one")
        try assertEqual(second, "line two")
        try assertEqual(third, "line three")
    }

    test("handles leftover bytes from previous read correctly") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        // Write two lines in one write — the reader must stash the second line's bytes
        writeString(writeFD, "first\nsecond\n")

        let reader = BufferedLineReader(fileDescriptor: readFD)
        let first = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        try assertEqual(first, "first")

        // Second line should come from the leftover buffer without needing another read()
        let second = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        try assertEqual(second, "second")
    }

    test("reads JSON-RPC style messages") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        let msg = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}\n"
        writeString(writeFD, msg)

        let reader = BufferedLineReader(fileDescriptor: readFD)
        let line = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        try assertEqual(line, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}")
    }

    // -- Buffering behavior --

    test("handles data arriving in small chunks") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        let reader = BufferedLineReader(fileDescriptor: readFD)

        // Write partial data, then the rest with newline
        writeString(writeFD, "hel")
        writeString(writeFD, "lo\n")

        let line = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        try assertEqual(line, "hello")
    }

    test("custom buffer size works") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        // Use a tiny buffer to force multiple read() calls for a longer message
        let reader = BufferedLineReader(fileDescriptor: readFD, bufferSize: 4)
        writeString(writeFD, "abcdefghijklmnop\n")

        let line = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        try assertEqual(line, "abcdefghijklmnop")
    }

    test("handles large messages efficiently") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        let largePayload = String(repeating: "x", count: 8000)
        writeString(writeFD, largePayload + "\n")

        let reader = BufferedLineReader(fileDescriptor: readFD)
        let line = try reader.readLine(timeoutMilliseconds: 2000, operationDescription: "test")
        try assertEqual(line.count, 8000)
    }

    // -- Error handling --

    test("times out when no newline arrives") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        // Write data without a newline
        writeString(writeFD, "no newline here")

        let reader = BufferedLineReader(fileDescriptor: readFD)
        var didThrow = false
        do {
            let _ = try reader.readLine(timeoutMilliseconds: 100, operationDescription: "test")
        } catch {
            didThrow = true
            try assertTrue("\(error)".contains("timed out"), "Expected timeout error, got: \(error)")
        }
        try assertTrue(didThrow, "Expected timeout error")
    }

    test("throws on closed pipe (EOF)") {
        let (readFD, writeFD) = makePipe()
        close(writeFD) // Close write end immediately — reader sees EOF
        defer { close(readFD) }

        let reader = BufferedLineReader(fileDescriptor: readFD)
        var didThrow = false
        do {
            let _ = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        } catch {
            didThrow = true
            try assertTrue("\(error)".contains("closed unexpectedly"), "Expected closed error, got: \(error)")
        }
        try assertTrue(didThrow, "Expected closed pipe error")
    }

    test("throws on empty line (newline only)") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        writeString(writeFD, "\n")

        let reader = BufferedLineReader(fileDescriptor: readFD)
        var didThrow = false
        do {
            let _ = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "test")
        } catch {
            didThrow = true
            try assertTrue("\(error)".contains("Empty response"), "Expected empty response error, got: \(error)")
        }
        try assertTrue(didThrow, "Expected empty response error")
    }

    // -- Multi-message sequences (simulating MCP handshake) --

    test("handles init + tools/list sequence like real MCP handshake") {
        let (readFD, writeFD) = makePipe()
        defer { close(readFD); close(writeFD) }

        let initResponse = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"serverInfo\":{\"name\":\"test\",\"version\":\"1.0\"}}}"
        let toolsResponse = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"add\",\"description\":\"Add numbers\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"number\"},\"b\":{\"type\":\"number\"}},\"required\":[\"a\",\"b\"]}}]}}"

        // Write both responses at once — tests that leftover buffering works across messages
        writeString(writeFD, initResponse + "\n" + toolsResponse + "\n")

        let reader = BufferedLineReader(fileDescriptor: readFD)
        let first = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "initialize")
        let second = try reader.readLine(timeoutMilliseconds: 1000, operationDescription: "tools/list")

        try assertTrue(first.contains("protocolVersion"))
        try assertTrue(second.contains("\"name\":\"add\""))
    }
}
