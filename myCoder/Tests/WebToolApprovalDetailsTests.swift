import Testing
import Foundation
@testable import myCoder

@Suite("Tool approval — detailed request shown before a local model runs a tool")
struct WebToolApprovalDetailsTests {

    @Test("write_file request explains action, target, arguments and effect")
    func writeFileDetails() {
        let details = WebToolApprovalDetails(
            call: WebToolCall(
                name: "write_file",
                arguments: ["path": "Sources/A.swift", "content": "let a = 1\n"]
            ),
            projectRoot: "/tmp/project",
            modelContext: "I will create the entry point.\n```tool\n{\"name\":\"read_file\"}\n```"
        )

        #expect(details.tool == "write_file")
        #expect(details.action.contains("Create or overwrite"))
        #expect(details.location == "Sources/A.swift")
        #expect(details.projectRoot == "/tmp/project")
        #expect(details.parameters.map(\.name) == ["content", "path"])
        #expect(details.parameters.first?.value == "\"let a = 1\\n\" (10 chars)")
        #expect(details.impact == "Creates or replaces Sources/A.swift with 10 characters of content.")
        #expect(details.rationale == "I will create the entry point.")

        let message = details.formattedMessage
        #expect(message.contains("Tool: write_file"))
        #expect(message.contains("Action: Create or overwrite a file."))
        #expect(message.contains("Location: Sources/A.swift"))
        #expect(message.contains("Project: /tmp/project"))
        #expect(message.contains("Model context: I will create the entry point."))
        #expect(message.contains("Parameters:"))
        #expect(message.contains("  - content = \"let a = 1\\n\" (10 chars)"))
        #expect(message.contains("myCoder is paused until you choose Allow or Deny."))
    }

    @Test("run_command request exposes the exact command, working directory and machine risk")
    func runCommandDetails() {
        let details = WebToolApprovalDetails(
            call: WebToolCall(name: "run_command", arguments: ["command": "swift test"]),
            projectRoot: "/tmp/project"
        )

        #expect(details.action == "Run a shell command on this machine.")
        #expect(details.location == "Working directory: /tmp/project")
        #expect(details.parameters == [WebToolApprovalParameter(name: "command", value: "swift test")])
        #expect(details.impact.contains("your user permissions"))
        #expect(details.formattedMessage.contains("command = swift test"))
    }

    @Test("edit_file request reports old/new sizes and keeps every parameter")
    func editFileDetails() {
        let details = WebToolApprovalDetails(
            call: WebToolCall(
                name: "edit_file",
                arguments: ["path": "Sources/A.swift", "old": "foo", "new": "bar"]
            ),
            projectRoot: "/tmp/project"
        )

        #expect(details.action == "Replace an exact substring in an existing file.")
        #expect(details.impact == "Replaces 3 characters with 3 characters in Sources/A.swift.")
        #expect(details.parameters.map(\.name) == ["new", "old", "path"])
    }

    @Test("sensitive argument names are redacted in the dialog")
    func sensitiveArgumentsRedacted() {
        let details = WebToolApprovalDetails(
            call: WebToolCall(
                name: "run_command",
                arguments: ["command": "curl api", "token": "sk-live-secret", "api_key": "abc"]
            ),
            projectRoot: "/tmp/project"
        )

        let values = Dictionary(uniqueKeysWithValues: details.parameters.map { ($0.name, $0.value) })
        #expect(values["token"] == "<redacted>")
        #expect(values["api_key"] == "<redacted>")
        #expect(values["command"] == "curl api")
    }

    @Test("missing model context is omitted instead of rendering an empty why line")
    func missingRationaleOmitted() {
        let details = WebToolApprovalDetails(
            call: WebToolCall(name: "git_commit", arguments: ["message": "feat: x"]),
            projectRoot: "/tmp/project"
        )

        #expect(details.rationale == nil)
        #expect(!details.formattedMessage.contains("Model context:"))
        #expect(details.impact.contains("git commit"))
    }
}

@Suite("Tool approval — blocking mailbox")
struct WebToolApprovalBoxTests {

    @Test("the verdict is delivered only after the user resolves the pending request")
    func blocksUntilResolved() async {
        let box = WebToolApprovalBox()
        let request = WebToolApprovalRequest(id: "req-1", tool: "write_file", message: "write")
        box.post(request)

        let waiting = Task.detached {
            box.awaitAnswer(timeoutSeconds: 2)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        box.resolve(id: "req-1", approved: true)

        #expect(await waiting.value == true)
    }

    @Test("a stale or mismatched approval id cannot release the current request")
    func staleResolutionIgnored() async {
        let box = WebToolApprovalBox()
        box.post(WebToolApprovalRequest(id: "current", tool: "run_command", message: "run"))
        box.resolve(id: "old", approved: true)

        let waiting = Task.detached {
            box.awaitAnswer(timeoutSeconds: 2)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        box.resolve(id: "current", approved: false)

        #expect(await waiting.value == false)
    }
}
