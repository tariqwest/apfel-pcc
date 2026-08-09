// ChatHistoryTests - persistent chat-history opt-in decision logic (#259)

import Foundation
import ApfelCLI

func runChatHistoryTests() {
    test("history is off by default (env var absent -> nil)") {
        try assertNil(ChatHistory.filePath(env: [:]))
    }

    test("empty APFEL_HISTFILE is treated as absence (nil)") {
        try assertNil(ChatHistory.filePath(env: ["APFEL_HISTFILE": ""]))
    }

    test("whitespace-only APFEL_HISTFILE is treated as absence (nil)") {
        try assertNil(ChatHistory.filePath(env: ["APFEL_HISTFILE": "   "]))
    }

    test("APFEL_HISTFILE with an absolute path is returned verbatim") {
        try assertEqual(
            ChatHistory.filePath(env: ["APFEL_HISTFILE": "/tmp/apfel_hist"]),
            "/tmp/apfel_hist"
        )
    }

    test("APFEL_HISTFILE leading tilde is expanded to home") {
        let home = NSHomeDirectory()
        try assertEqual(
            ChatHistory.filePath(env: ["APFEL_HISTFILE": "~/.apfel_history"]),
            home + "/.apfel_history"
        )
    }

    test("surrounding whitespace is trimmed before use") {
        try assertEqual(
            ChatHistory.filePath(env: ["APFEL_HISTFILE": "  /tmp/h  "]),
            "/tmp/h"
        )
    }

    test("history bound matches the in-memory stifle limit") {
        try assertEqual(ChatHistory.maxEntries, 500)
    }
}
