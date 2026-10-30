import XCTest
@testable import myCoder

/// P режиме «План» запросы на безопасность/одобрения НЕ показываются
/// (директива 2026-10-30): мутирующие тулы отклоняются без вопроса, а
/// Read-only тулы выполняются как обычно.
final class PlanModeToolPolicyTests: XCTestCase {

    private func call(_ name: String) -> WebToolCall {
        WebToolCall(name: name, arguments: [:])
    }

    func testMutationsAreDeniedInPlanModeWithoutPrompt() {
        for name in ["write_file", "edit_file", "patch", "write", "edit", "rename_file"] {
            let decision = PlanModeToolPolicy.decision(for: call(name), isPlanMode: true)
            guard case .deny(let reason) = decision else {
                return XCTFail("\(name) должен отклоняться в plan-режиме")
            }
            XCTAssertTrue(reason.contains("read-only"), "отказ должен объяснять read-only режим")
            XCTAssertTrue(reason.contains("build mode"), "отказ должен указывать на build режим")
        }
    }

    func testReadOnlyToolsExecuteInPlanMode() {
        for name in ["read_file", "list_dir", "grep", "glob", "git_status", "todo_read", "code_search"] {
            XCTAssertEqual(
                PlanModeToolPolicy.decision(for: call(name), isPlanMode: true),
                .execute,
                "\(name) должен выполняться в plan-режиме"
            )
        }
    }

    func testPlanModeOffAlwaysExecutes() {
        for name in ["write_file", "edit_file", "read_file"] {
            XCTAssertEqual(
                PlanModeToolPolicy.decision(for: call(name), isPlanMode: false),
                .execute
            )
        }
    }
}
