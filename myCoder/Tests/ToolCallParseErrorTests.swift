import Testing
import Foundation
@testable import myCoder

/// A tool block the model got wrong must never vanish. Every broken block is
/// reported back to the model as a tool_result error so the agentic loop keeps
/// running and the model can re-emit a valid call.
@Suite("Tool call parse errors")
struct ToolCallParseErrorTests {

    private func block(_ body: String) -> String {
        "```tool\n\(body)\n```"
    }

    @Test("A broken block next to a valid one is reported, not dropped")
    func brokenBlockAmongValidCallsIsReported() {
        let text = [
            block(#"{"name": "list_dir", "args": {"path": "."}}"#),
            block(#"{"name": "read_file" "args": {"path": "a.swift"}}"#)
        ].joined(separator: "\n")

        let parsed = WebToolProtocolEmulator.parseToolCallsWithIssues(from: text)

        #expect(parsed.calls.count == 1)
        #expect(parsed.calls.first?.name == "list_dir")
        #expect(parsed.issues.count == 1)
        #expect(parsed.issues.first?.toolName == "read_file")
        #expect(parsed.issues.first?.reason.isEmpty == false)
    }

    @Test("Every broken block reports its own error")
    func everyBrokenBlockIsReported() {
        let text = [
            block(#"{"name": "grep" "args": {"pattern": "x"}}"#),
            block(#"{"name": "write_file" "args": {"path": "b.txt"}}"#)
        ].joined(separator: "\n")

        let parsed = WebToolProtocolEmulator.parseToolCallsWithIssues(from: text)

        #expect(parsed.calls.isEmpty)
        #expect(parsed.issues.map(\.toolName) == ["grep", "write_file"])
    }

    @Test("The reported reason names the actual JSON damage")
    func reasonDescribesTheDamage() {
        let text = block(#"{"name": "read_file", "args": {"path": "a.swift}"#)

        let parsed = WebToolProtocolEmulator.parseToolCallsWithIssues(from: text)

        #expect(parsed.calls.isEmpty)
        #expect(parsed.issues.count == 1)
        #expect(parsed.issues.first?.toolName == "read_file")
        #expect(parsed.issues.first?.reason.contains("not terminated") == true)
    }

    @Test("A body whose only damage is missing closing braces is repaired, not rejected")
    func repairedBodyIsStillExecuted() {
        let text = block(#"{"name": "read_file", "args": {"path": "a.swift""#)

        let parsed = WebToolProtocolEmulator.parseToolCallsWithIssues(from: text)

        #expect(parsed.issues.isEmpty)
        #expect(parsed.calls.first?.name == "read_file")
        #expect(parsed.calls.first?.arguments["path"] == "a.swift")
    }

    @Test("parseToolCalls keeps its contract: executable calls only")
    func legacyEntryPointReturnsCallsOnly() {
        let text = [
            block(#"{"name": "list_dir", "args": {"path": "."}}"#),
            block(#"{"name": "read_file" "args": {"path": "a.swift"}}"#)
        ].joined(separator: "\n")

        #expect(WebToolProtocolEmulator.parseToolCalls(from: text).map(\.name) == ["list_dir"])
    }

    @Test("A broken fenced block does not hide a valid unfenced call")
    func brokenFencedBlockDoesNotHideUnfencedCall() {
        let text = """
        ```tool
        {"name": "grep" "args": {"pattern": "x"}}
        ```
        {"name": "list_dir", "args": {"path": "."}}
        """

        let parsed = WebToolProtocolEmulator.parseToolCallsWithIssues(from: text)

        #expect(parsed.issues.count == 1)
        #expect(parsed.calls.map(\.name) == ["list_dir"])
    }

    @Test("Well-formed calls produce no issues")
    func cleanCallsHaveNoIssues() {
        let parsed = WebToolProtocolEmulator.parseToolCallsWithIssues(
            from: block(#"{"name": "list_dir", "args": {"path": "."}}"#)
        )

        #expect(parsed.issues.isEmpty)
        #expect(parsed.calls.count == 1)
    }
}
