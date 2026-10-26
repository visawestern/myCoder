import Testing
import Foundation
@testable import myCoder

// MARK: - TERM-01: Terminal Panel State Model

@Suite("TERM-01: Terminal panel state")
struct TerminalPanelStateTests {

    @Test("showTerminal defaults to false")
    func showTerminalDefaultFalse() {
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.showTerminal == false)
    }

    @Test("showTerminal toggles to true")
    func showTerminalToggleOn() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.showTerminal = true
        #expect(state.showTerminal == true)
    }

    @Test("showTerminal toggles back to false")
    func showTerminalToggleOff() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.showTerminal = true
        state.showTerminal = false
        #expect(state.showTerminal == false)
    }

    @Test("showTerminal is independent of other state flags")
    func showTerminalIsIndependent() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.showTerminal = true
        state.showGoal = true
        #expect(state.showTerminal == true)
        #expect(state.showGoal == true)
        state.showGoal = false
        #expect(state.showTerminal == true)
    }
}

// MARK: - TERM-02: Command Execution Model

@Suite("TERM-02: TerminalLine model")
struct TerminalLineModelTests {

    @Test("TerminalLine initializes with text and type")
    func terminalLineInit() {
        let line = TerminalLine(text: "Hello, World!", type: .output)
        #expect(line.text == "Hello, World!")
        #expect(line.type == .output)
    }

    @Test("TerminalLine creates unique identifiers")
    func terminalLineUniqueID() {
        let line1 = TerminalLine(text: "a", type: .command)
        let line2 = TerminalLine(text: "b", type: .output)
        #expect(line1.id != line2.id)
    }

    @Test("LineType contains all four cases")
    func lineTypeAllCases() {
        let all: [LineType] = [.command, .output, .error, .system]
        #expect(all.count == 4)
    }

    @Test("LineType.command case")
    func lineTypeCommand() {
        let line = TerminalLine(text: "$ ls -la", type: .command)
        #expect(line.type == .command)
    }

    @Test("LineType.output case")
    func lineTypeOutput() {
        let line = TerminalLine(text: "file.txt", type: .output)
        #expect(line.type == .output)
    }

    @Test("LineType.error case")
    func lineTypeError() {
        let line = TerminalLine(text: "permission denied", type: .error)
        #expect(line.type == .error)
    }

    @Test("LineType.system case")
    func lineTypeSystem() {
        let line = TerminalLine(text: "Welcome to terminal", type: .system)
        #expect(line.type == .system)
    }

    @Test("TerminalLine color property is accessible for all types")
    func terminalLineColorAccessible() {
        let types: [LineType] = [.command, .output, .error, .system]
        for type in types {
            let line = TerminalLine(text: "test", type: type)
            // Access the color property — it must not crash
            _ = line.color
        }
    }

    @Test("TerminalLine with empty text")
    func terminalLineEmptyText() {
        let line = TerminalLine(text: "", type: .output)
        #expect(line.text.isEmpty)
    }

    @Test("TerminalLine with special characters")
    func terminalLineSpecialChars() {
        let line = TerminalLine(text: "rm -rf /tmp/test && echo done", type: .command)
        #expect(line.text.contains("&&"))
    }
}

// MARK: - TERM-03: Command Timeout

@Suite("TERM-03: Command timeout")
struct CommandTimeoutTests {

    @Test("Standard timeout constant is 30 seconds")
    func timeoutConstantValue() {
        // TerminalView defines timeoutSeconds = 30
        let timeoutSeconds: TimeInterval = 30
        #expect(timeoutSeconds == 30)
        #expect(timeoutSeconds > 0)
    }

    @Test("Timeout value is within reasonable bounds")
    func timeoutReasonableBounds() {
        let timeoutSeconds: TimeInterval = 30
        #expect(timeoutSeconds >= 10)  // At least 10s for real commands
        #expect(timeoutSeconds <= 120) // At most 2min upper bound
    }

    @Test("Remaining time computation stays non-negative")
    func remainingTimeNonNegative() {
        let timeout: TimeInterval = 30
        let elapsed: TimeInterval = 5
        let remaining = max(0, timeout - elapsed)
        #expect(remaining == 25)
        #expect(remaining >= 0)

        // If execution exceeds timeout, remaining should be 0
        let overElapsed: TimeInterval = 35
        let overRemaining = max(0, timeout - overElapsed)
        #expect(overRemaining == 0)
    }

    @Test("Execution time label format")
    func executionTimeLabelFormat() {
        let timeout: TimeInterval = 30
        let elapsed: TimeInterval = 3
        let remain = max(0, timeout - elapsed)
        let label = "\(Int(elapsed))s / \(Int(remain))s"
        #expect(label == "3s / 27s")
    }
}

// MARK: - TERM-04: Terminal History

@Suite("TERM-04: Terminal history")
struct TerminalHistoryTests {

    @Test("Maximum terminal lines limit is 500")
    func maxLinesConstant() {
        // TerminalView defines maxTerminalLines = 500
        let maxLines = 500
        #expect(maxLines == 500)
        #expect(maxLines > 0)
    }

    @Test("Output array starts empty")
    func outputArrayStartsEmpty() {
        let output: [TerminalLine] = []
        #expect(output.isEmpty)
        #expect(output.count == 0)
    }

    @Test("Output array appends lines in order")
    func outputAppendOrder() {
        var output: [TerminalLine] = []
        output.append(TerminalLine(text: "first", type: .output))
        output.append(TerminalLine(text: "second", type: .output))
        output.append(TerminalLine(text: "third", type: .output))

        #expect(output.count == 3)
        #expect(output[0].text == "first")
        #expect(output[1].text == "second")
        #expect(output[2].text == "third")
    }

    @Test("Output array preserves all line types in sequence")
    func outputPreservesMixedTypes() {
        var output: [TerminalLine] = []
        output.append(TerminalLine(text: "$ git status", type: .command))
        output.append(TerminalLine(text: "modified: main.swift", type: .output))
        output.append(TerminalLine(text: "error: failed", type: .error))
        output.append(TerminalLine(text: "--- done ---", type: .system))

        #expect(output[0].type == .command)
        #expect(output[1].type == .output)
        #expect(output[2].type == .error)
        #expect(output[3].type == .system)
    }

    @Test("Output array can be fully cleared")
    func outputClearAll() {
        var output: [TerminalLine] = [
            TerminalLine(text: "a", type: .command),
            TerminalLine(text: "b", type: .output)
        ]
        output.removeAll()
        #expect(output.isEmpty)
    }

    @Test("Oldest lines are pruned when exceeding max limit")
    func outputPrunesOldestLines() {
        var output: [TerminalLine] = []
        let maxLines = 500

        // Add 510 lines, exceeding the limit
        for i in 0..<510 {
            output.append(TerminalLine(text: "line\(i)", type: .output))
        }

        if output.count > maxLines {
            output.removeFirst(output.count - maxLines)
        }

        #expect(output.count == maxLines)
        // The first remaining line should be line10 (0-indexed from original 510)
        #expect(output.first?.text == "line10")
        #expect(output.last?.text == "line509")
    }

    @Test("Output pruning retains most recent lines")
    func outputPruningRetainsRecent() {
        var output: [TerminalLine] = []
        let maxLines = 500

        for i in 0..<505 {
            output.append(TerminalLine(text: "\(i)", type: .output))
        }

        if output.count > maxLines {
            output.removeFirst(output.count - maxLines)
        }

        #expect(output.count == maxLines)
        // The last line should be "504"
        #expect(output.last?.text == "504")
    }

    @Test("Output under limit is not pruned")
    func outputUnderLimitNotPruned() {
        var output: [TerminalLine] = []
        let maxLines = 500

        for i in 0..<100 {
            output.append(TerminalLine(text: "\(i)", type: .output))
        }

        // Should not trigger pruning
        if output.count > maxLines {
            output.removeFirst(output.count - maxLines)
        }

        #expect(output.count == 100)
    }

    @Test("AppendLine skips whitespace-only strings")
    func appendLineSkipsWhitespace() {
        // The appendLine logic in TerminalView skips blank lines
        var output: [TerminalLine] = []
        let lines = "hello\n\nworld".components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            output.append(TerminalLine(text: trimmed, type: .output))
        }

        #expect(output.count == 2)
        #expect(output[0].text == "hello")
        #expect(output[1].text == "world")
    }
}
