import XCTest
@testable import myCoder

/// TDD: sub-agent task tool must NOT crash when bridge is nil.
/// Pre-fix: force-unwrap `bridge!` caused SIGILL.
/// Post-fix: returns an actionable error message instead.
final class SubAgentTaskToolTests: XCTestCase {

    func testExecuteTaskHandlesNilBridge() async {
        // Given: an executor with no bridge injected (the production nil case)
        let executor = ProjectWebToolExecutor(
            projectRoot: "/tmp/test-project",
            accessLevel: .fullAccess
        )
        // bridge remains nil — this is the real production state when
        // executeTask is called from a context that never injected a bridge.

        let call = WebToolCall(name: "task", arguments: [
            "description": "Summarize the project",
            "prompt": "Read the README and summarize."
        ])

        // When: the tool is executed
        let result = await executor.execute(call)

        // Then: it must NOT crash, and must surface a catchable error
        XCTAssertTrue(result.lowercased().contains("error") || result.lowercased().contains("bridge"),
                      "Expected an error message about missing bridge, got: \(result)")
        XCTAssertFalse(result.isEmpty, "Result must not be empty")
    }

    func testExecuteTaskHandlesMissingArgs() async {
        let executor = ProjectWebToolExecutor(
            projectRoot: "/tmp/test-project",
            accessLevel: .fullAccess
        )

        let noDesc = WebToolCall(name: "task", arguments: ["prompt": "hi"])
        let result1 = await executor.execute(noDesc)
        XCTAssertTrue(result1.contains("missing description") || result1.contains("missing description or prompt"),
                      "Expected missing description error, got: \(result1)")

        let noPrompt = WebToolCall(name: "task", arguments: ["description": "do it"])
        let result2 = await executor.execute(noPrompt)
        XCTAssertTrue(result2.contains("missing"),
                      "Expected missing prompt error, got: \(result2)")
    }
}
