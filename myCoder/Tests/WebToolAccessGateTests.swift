import Foundation
import Testing
@testable import myCoder

@Suite("WEB-CHAT-11: web tool access gate")
struct WebToolAccessGateTests {
    @Test("ask-before-changes requires approval for every file mutation")
    func askBeforeChangesGatesFileMutations() {
        let calls = [
            WebToolCall(name: "write_file", arguments: ["path": "a.txt", "content": "x"]),
            WebToolCall(name: "edit_file", arguments: ["path": "a.txt", "old": "x", "new": "y"]),
            WebToolCall(name: "todo_write", arguments: ["todos": "[]"])
        ]
        for call in calls {
            #expect(WebToolAccessGate.permission(for: call, accessLevel: .askBeforeChanges) == .requireApproval)
        }
    }

    @Test("edit-automatically allows file mutations and read-only shell, guards mutating shell")
    func editAutomaticallyKeepsMutatingShellGuarded() {
        let write = WebToolCall(name: "write_file", arguments: ["path": "a.txt", "content": "x"])
        let readOnlyShell = WebToolCall(name: "run_command", arguments: ["command": "echo x"])
        let mutatingShell = WebToolCall(name: "run_command", arguments: ["command": "rm x.txt"])
        #expect(WebToolAccessGate.permission(for: write, accessLevel: .editAutomatically) == .allow)
        #expect(WebToolAccessGate.permission(for: readOnlyShell, accessLevel: .editAutomatically) == .allow)
        #expect(WebToolAccessGate.permission(for: mutatingShell, accessLevel: .editAutomatically) == .requireApproval)
    }

    @Test("full access allows file and shell mutations")
    func fullAccessAllowsMutations() {
        let write = WebToolCall(name: "write_file", arguments: ["path": "a.txt", "content": "x"])
        let command = WebToolCall(name: "run_command", arguments: ["command": "rm x.txt"])
        #expect(WebToolAccessGate.permission(for: write, accessLevel: .fullAccess) == .allow)
        #expect(WebToolAccessGate.permission(for: command, accessLevel: .fullAccess) == .allow)
    }

    // Live 2026-09-12 (last chat, session C9AB8206): the model paged a file
    // with `sed -n '115,330p' file` and was blocked into an approval dead-end.
    // Read-only sed print form must run at ANY access level.
    @Test("sed range print runs without approval, sed -i does not")
    func sedPrintReadOnlyInPlaceIsNot() {
        #expect(WebToolAccessGate.isReadOnlyCommand("sed -n '115,330p' TZ-Bezdna-v3.md"))
        #expect(WebToolAccessGate.permission(
            for: WebToolCall(name: "run_command", arguments: ["command": "sed -n '115,330p' TZ-Bezdna-v3.md"]),
            accessLevel: .askBeforeChanges) == .allow)
        #expect(!WebToolAccessGate.isReadOnlyCommand("sed -i 's/a/b/' file.txt"))
        #expect(!WebToolAccessGate.isReadOnlyCommand("sed --in-place 's/a/b/' file.txt"))
        #expect(WebToolAccessGate.permission(
            for: WebToolCall(name: "run_command", arguments: ["command": "sed -i 's/a/b/' file.txt"]),
            accessLevel: .askBeforeChanges) == .requireApproval)
        // Mutating sed inside a chain still trips the gate.
        #expect(!WebToolAccessGate.isReadOnlyCommand("sed -n '2p' a.txt && sed -i 's/x/y/' b.txt"))
    }
}
