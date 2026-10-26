import Testing
import Foundation
@testable import myCoder

@Suite("Session transcript export/share")
struct SessionTranscriptLogicTests {

    @Test func markdownHasHeaderAndTurns() {
        let messages = [
            Message(role: .user, content: "fix login", isFinished: true),
            Message(role: .assistant, content: "done", isFinished: true),
        ]
        let md = SessionTranscriptLogic.markdown(
            title: "Login bug",
            messages: messages,
            exportedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(md.hasPrefix("# Login bug"))
        #expect(md.contains("## User"))
        #expect(md.contains("fix login"))
        #expect(md.contains("## Assistant"))
        #expect(md.contains("done"))
        #expect(md.contains("Exported from myCoder"))
    }

    @Test func toolCallsSurviveExport() {
        let message = Message(
            role: .assistant,
            content: "",
            toolCalls: nil,
            isStreaming: false,
            parts: [.toolCall(name: "read_file", args: "{\"path\":\"a.swift\"}", result: "let a = 1", callID: "c1")],
            isFinished: true
        )
        let body = SessionTranscriptLogic.bodyText(for: message)
        #expect(body.contains("tool: read_file"))
        #expect(body.contains("a.swift"))
        #expect(body.contains("let a = 1"))
    }

    @Test func emptySessionKeepsHeaderOnly() {
        let md = SessionTranscriptLogic.markdown(title: "Empty", messages: [])
        #expect(md.contains("# Empty"))
        #expect(!md.contains("## User"))
    }

    @Test func fileNameIsFilesystemSafe() {
        #expect(SessionTranscriptLogic.fileName(title: "fix/login: bug") == "fix-login- bug.md")
        #expect(SessionTranscriptLogic.fileName(title: "   " ) == "chat-transcript.md")
        #expect(SessionTranscriptLogic.fileName(title: String(repeating: "x", count: 200)).count <= 63)
    }
}
