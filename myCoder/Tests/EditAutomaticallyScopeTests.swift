import Testing
import Foundation
@testable import myCoder

/// "Edit automatically" is the middle permission level: every file edit inside
/// the project folder runs without a prompt, exactly like Full access, and the
/// WHOLE todo/task list is editable too. The moment a path leaves the project
/// folder the user is asked — the level never silently touches the rest of the
/// machine.
@Suite("Edit automatically — project-wide edits, whole TODO list, ask outside")
struct EditAutomaticallyScopeTests {

    private let projectRoot = "/tmp/mycoder-scope/project"

    private func call(_ name: String, _ arguments: [String: String]) -> WebToolCall {
        WebToolCall(name: name, arguments: arguments)
    }

    private func write(_ path: String) -> WebToolCall {
        call("write_file", ["path": path, "content": "x"])
    }

    private func edit(_ path: String) -> WebToolCall {
        call("edit_file", ["path": path, "old": "a", "new": "b"])
    }

    // MARK: - All edits, like full access, inside the project

    @Test("Every edit spelling is auto-allowed inside the project folder")
    func allEditAliasesAllowedInsideProject() {
        let aliases = [
            "write_file", "write", "create", "create_file",
            "edit_file", "edit", "replace", "apply_patch", "str_replace",
        ]
        for alias in aliases {
            let permission = WebToolAccessGate.permission(
                for: call(alias, ["path": "Sources/App.swift", "content": "x",
                                  "old": "a", "new": "b"]),
                accessLevel: .editAutomatically,
                projectRoot: projectRoot
            )
            #expect(permission == .allow, "alias \(alias) must be allowed inside the project")
        }
    }

    @Test("Nested and relative paths inside the project are allowed")
    func insidePathsAllowed() {
        for path in ["README.md", "Sources/App/AppState.swift", "./docs/plan.md"] {
            #expect(WebToolAccessGate.permission(
                for: write(path),
                accessLevel: .editAutomatically,
                projectRoot: projectRoot
            ) == .allow)
        }
    }

    // MARK: - Ask when leaving the project folder

    @Test("An absolute path outside the project asks at Edit automatically")
    func absoluteOutsideAsks() {
        let outside = "/tmp/mycoder-scope/other/notes.md"
        #expect(WebToolAccessGate.permission(
            for: write(outside),
            accessLevel: .editAutomatically,
            projectRoot: projectRoot
        ) == .requireApproval)
        #expect(WebToolAccessGate.permission(
            for: edit(outside),
            accessLevel: .editAutomatically,
            projectRoot: projectRoot
        ) == .requireApproval)
    }

    @Test("A relative traversal outside the project asks at Edit automatically")
    func traversalOutsideAsks() {
        #expect(WebToolAccessGate.permission(
            for: write("../other/notes.md"),
            accessLevel: .editAutomatically,
            projectRoot: projectRoot
        ) == .requireApproval)
        #expect(WebToolAccessGate.permission(
            for: write("Sources/../../other/notes.md"),
            accessLevel: .editAutomatically,
            projectRoot: projectRoot
        ) == .requireApproval)
    }

    @Test("A read outside the project also asks below Full access")
    func outsideReadAsks() {
        let outside = "/tmp/mycoder-scope/other/notes.md"
        #expect(WebToolAccessGate.permission(
            for: call("read_file", ["path": outside]),
            accessLevel: .editAutomatically,
            projectRoot: projectRoot
        ) == .requireApproval)
        #expect(WebToolAccessGate.permission(
            for: call("list_dir", ["path": "/tmp/mycoder-scope/other"]),
            accessLevel: .askBeforeChanges,
            projectRoot: projectRoot
        ) == .requireApproval)
    }

    @Test("Full access keeps allowing paths outside the project")
    func fullAccessStaysUnrestricted() {
        let outside = "/tmp/mycoder-scope/other/notes.md"
        #expect(WebToolAccessGate.permission(
            for: write(outside),
            accessLevel: .fullAccess,
            projectRoot: projectRoot
        ) == .allow)
        #expect(WebToolAccessGate.permission(
            for: call("read_file", ["path": outside]),
            accessLevel: .fullAccess,
            projectRoot: projectRoot
        ) == .allow)
    }

    @Test("Ask before changes still asks for edits inside the project")
    func askBeforeChangesStillAsks() {
        #expect(WebToolAccessGate.permission(
            for: write("README.md"),
            accessLevel: .askBeforeChanges,
            projectRoot: projectRoot
        ) == .requireApproval)
    }

    // MARK: - The whole TODO list

    @Test("The whole todo/task list is editable at Edit automatically")
    func wholeTodoListAllowed() {
        let calls = [
            call("todo_read", [:]),
            call("todo_write", ["todos": "[]"]),
            call("task_create", ["content": "new task"]),
            call("task_list", [:]),
            call("task_update", ["id": "1", "status": "done"]),
            call("todo_add", ["content": "alias"]),
            call("todo_update", ["id": "1", "status": "done"]),
            call("todos", [:]),
            call("tasklist", [:]),
        ]
        for todoCall in calls {
            #expect(WebToolAccessGate.permission(
                for: todoCall,
                accessLevel: .editAutomatically,
                projectRoot: projectRoot
            ) == .allow, "\(todoCall.name) must be allowed")
        }
    }

    @Test("Ask before changes still gates todo mutations, not reads")
    func askBeforeChangesTodoGate() {
        #expect(WebToolAccessGate.permission(
            for: call("todo_write", ["todos": "[]"]),
            accessLevel: .askBeforeChanges,
            projectRoot: projectRoot
        ) == .requireApproval)
        #expect(WebToolAccessGate.permission(
            for: call("task_create", ["content": "x"]),
            accessLevel: .askBeforeChanges,
            projectRoot: projectRoot
        ) == .requireApproval)
        #expect(WebToolAccessGate.permission(
            for: call("todo_read", [:]),
            accessLevel: .askBeforeChanges,
            projectRoot: projectRoot
        ) == .allow)
        #expect(WebToolAccessGate.permission(
            for: call("task_list", [:]),
            accessLevel: .askBeforeChanges,
            projectRoot: projectRoot
        ) == .allow)
    }

    // MARK: - Permission patch sent to the local agent

    @Test("Edit automatically sends edit=allow plus an explicit outside-project ask")
    func permissionPatchCarriesBoundary() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .editAutomatically)
        #expect(patch["edit"] as? String == "allow")
        #expect(patch["external_directory"] as? String == "ask")
        #expect(patch["bash"] == nil)
        #expect(AccessLevelPermissionLogic.accessLevel(
            from: patch.compactMapValues { $0 as? String }
        ) == .editAutomatically)
    }

    @Test("Full access still sends the unrestricted patch")
    func fullAccessPatchUnrestricted() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .fullAccess)
        #expect(patch["external_directory"] as? String == "allow")
        #expect(AccessLevelPermissionLogic.accessLevel(
            from: patch.compactMapValues { $0 as? String }
        ) == .fullAccess)
    }
}
