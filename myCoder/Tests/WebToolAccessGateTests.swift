import Foundation
import Testing
@testable import myCoder

@MainActor
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

    // Инцидент 2026-11-14: `rsync --delete` удалил прод-базу, а
    // `migrate --force` создал пустую — на Full access, без вопроса.
    @Test("destructive commands require approval even at full access")
    func destructiveCommandsRequireApprovalAtFullAccess() {
        let commands = [
            "rsync -a --delete api/ prod:/srv/api/",
            "php artisan migrate --force",
            "rm -rf build",
            "git push --force origin main",
            "psql -c \"DROP DATABASE prod\"",
        ]
        for command in commands {
            let call = WebToolCall(name: "run_command", arguments: ["command": command])
            #expect(WebToolAccessGate.permission(
                for: call, accessLevel: .fullAccess, projectRoot: "/p") == .requireApproval,
                "должна требовать подтверждения: \(command)")
        }
    }

    @Test("ordinary commands stay silent at full access")
    func ordinaryCommandsStaySilentAtFullAccess() {
        for command in ["npm test", "swift build", "rm file.txt", "git push origin main", "git status"] {
            let call = WebToolCall(name: "run_command", arguments: ["command": command])
            #expect(WebToolAccessGate.permission(
                for: call, accessLevel: .fullAccess, projectRoot: "/p") == .allow,
                "не должна спрашивать: \(command)")
        }
    }

    @Test("xargs, env and awk cannot smuggle a mutation through the read-only shortcut")
    func wrappersCannotSmuggleMutations() {
        #expect(!WebToolAccessGate.isReadOnlyCommand("xargs rm -rf"))
        #expect(!WebToolAccessGate.isReadOnlyCommand("env rm -rf build"))
        #expect(!WebToolAccessGate.isReadOnlyCommand("env FOO=1 rm -rf build"))
        #expect(!WebToolAccessGate.isReadOnlyCommand("awk 'BEGIN{system(\"rm -rf /\")}'"))
        #expect(!WebToolAccessGate.isReadOnlyCommand("echo $(rm -rf /)"))
        #expect(!WebToolAccessGate.isReadOnlyCommand("echo `rm -rf /`"))
        #expect(!WebToolAccessGate.isReadOnlyCommand("bash -c 'rm -rf /'"))
        #expect(WebToolAccessGate.isReadOnlyCommand("xargs grep foo"))
        #expect(WebToolAccessGate.isReadOnlyCommand("env FOO=1 ls -la"))
    }

    @Test("destructive reason is exposed for the approval card")
    func destructiveReasonIsExposed() {
        let incident = WebToolCall(
            name: "run_command",
            arguments: ["command": "rsync -a --delete api/ prod:/srv/"]
        )
        #expect(WebToolAccessGate.destructiveReason(for: incident)?.lowercased().contains("rsync") == true)
        let ordinary = WebToolCall(name: "run_command", arguments: ["command": "ls"])
        #expect(WebToolAccessGate.destructiveReason(for: ordinary) == nil)
    }

    @Test("web approval request is red and names the exact command")
    func webApprovalRequestIsRedForDestructiveCommands() {
        let call = WebToolCall(
            name: "run_command",
            arguments: ["command": "rsync -a --delete api/ prod:/srv/api/"]
        )
        let request = WebChatApprovalRequestLogic.make(
            call: call, projectRoot: "/p", accessLevel: .fullAccess)
        #expect(request.isDestructive)
        #expect(request.message.contains("DESTRUCTIVE"))
        #expect(request.message.contains("rsync -a --delete"))
    }

    @Test("ordinary web approval request keeps the generic message")
    func webApprovalRequestStaysGeneric() {
        let call = WebToolCall(name: "write_file", arguments: ["path": "a.txt", "content": "x"])
        let request = WebChatApprovalRequestLogic.make(
            call: call, projectRoot: "/p", accessLevel: .askBeforeChanges)
        #expect(!request.isDestructive)
        #expect(!request.message.contains("DESTRUCTIVE"))
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
