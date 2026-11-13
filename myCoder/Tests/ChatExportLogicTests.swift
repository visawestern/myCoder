import Foundation
import Testing
@testable import myCoder

/// The eight copy/save variants, their text/Markdown/JSON builders and the
/// standalone HTML book. All pure — no UI, no filesystem.
@Suite("Chat export — eight variants")
struct ChatExportLogicTests {

    private func chat() -> [Message] {
        [
            Message(role: .user, content: "Проверь сборку"),
            Message(
                role: .assistant,
                content: "",
                parts: [
                    .text("Запускаю тесты."),
                    .toolCall(
                        name: "run_command",
                        args: #"{"command":"swift test"}"#,
                        result: "All tests passed",
                        callID: "call-1"
                    ),
                    .text("Готово: 10 тестов зелёные.")
                ]
            )
        ]
    }

    // MARK: - Variant catalog

    @Test func exposesExactlyFourCopyAndFourSaveVariants() {
        #expect(ChatExportVariant.allCases.count == 8)
        #expect(ChatExportVariant.allCases.filter(\.isCopy).count == 4)
        #expect(ChatExportVariant.allCases.filter { !$0.isCopy }.count == 4)
        #expect(ChatExportVariant.allCases.filter(\.isCopy).allSatisfy { $0.fileExtension == nil })
        #expect(ChatExportVariant.saveText.fileExtension == "txt")
        #expect(ChatExportVariant.saveMarkdown.fileExtension == "md")
        #expect(ChatExportVariant.saveJSON.fileExtension == "json")
        #expect(ChatExportVariant.saveHTML.fileExtension == "html")
    }

    @Test func everyVariantHasADistinctMenuTitle() {
        let titles = ChatExportVariant.allCases.map(\.menuTitle)
        #expect(Set(titles).count == titles.count)
    }

    // MARK: - Plain text

    @Test func plainTextWithoutCallsMatchesTheHistoricalTranscript() {
        let messages = chat()
        let expected = ChatCopyLogic.transcript(from: messages)
        #expect(ChatExportLogic.content(
            for: .copyPlain, messages: messages, title: "T"
        ) == expected)
        #expect(!expected.contains("run_command"))
        #expect(!expected.contains("All tests passed"))
    }

    @Test func textWithCallsKeepsArgumentsButDropsResults() {
        let text = ChatExportLogic.plainText(
            messages: chat(), includeCalls: true, includeResults: false
        )
        #expect(text.contains("Tool call: run_command"))
        #expect(text.contains(#"{"command":"swift test"}"#))
        #expect(!text.contains("All tests passed"))
    }

    @Test func textWithResultsKeepsBoth() {
        let text = ChatExportLogic.plainText(
            messages: chat(), includeCalls: true, includeResults: true
        )
        #expect(text.contains("Tool call: run_command"))
        #expect(text.contains("All tests passed"))
        #expect(text.contains("Готово: 10 тестов зелёные."))
    }

    @Test func saveTextVariantUsesPlainTextWithoutCalls() {
        let text = ChatExportLogic.content(
            for: .saveText, messages: chat(), title: "T"
        )
        #expect(text == ChatExportLogic.plainText(
            messages: chat(), includeCalls: false, includeResults: false
        ))
    }

    // MARK: - Markdown

    @Test func markdownHasTitleRoleToolAndResultBlocks() {
        let markdown = ChatExportLogic.content(
            for: .saveMarkdown, messages: chat(), title: "Сборка",
            exportedAt: Date(timeIntervalSince1970: 0)
        ) ?? ""
        #expect(markdown.contains("# Сборка"))
        #expect(markdown.contains("## User"))
        #expect(markdown.contains("## Assistant"))
        #expect(markdown.contains("### Tool call: run_command"))
        #expect(markdown.contains("**Result**"))
        #expect(markdown.contains("All tests passed"))
    }

    // MARK: - JSON

    @Test func fullJSONKeepsEveryMessageFieldAndPart() throws {
        let raw = ChatExportLogic.content(
            for: .copyFullJSON, messages: chat(), title: "T",
            exportedAt: Date(timeIntervalSince1970: 0)
        ) ?? ""
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        #expect(root["title"] as? String == "T")
        let messages = try #require(root["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[1]["reasoning"] as? String == "")
        let parts = try #require(messages[1]["parts"] as? [[String: Any]])
        #expect(parts.contains { $0["type"] as? String == "tool_call" })
        #expect(parts.contains { $0["type"] as? String == "text" })
    }

    @Test func compactJSONContainsRoleTextAndToolResults() throws {
        let raw = ChatExportLogic.content(
            for: .saveJSON, messages: chat(), title: "T",
            exportedAt: Date(timeIntervalSince1970: 0)
        ) ?? ""
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        let messages = try #require(root["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        let assistant = messages[1]
        #expect(assistant["role"] as? String == "Assistant")
        #expect(assistant["reasoning"] == nil)
        let calls = try #require(assistant["toolCalls"] as? [[String: Any]])
        #expect(calls.first?["name"] as? String == "run_command")
        #expect(calls.first?["result"] as? String == "All tests passed")
    }

    @Test func emptyChatHasNoContentForAnyVariant() {
        for variant in ChatExportVariant.allCases {
            #expect(ChatExportLogic.content(
                for: variant, messages: [], title: "T"
            ) == nil)
        }
    }

    // MARK: - File names

    @Test func fileNameStripsPathSeparatorsAndUsesTheVariantExtension() {
        #expect(ChatExportLogic.fileName(
            title: "a/b:c*d?e", variant: .saveMarkdown
        ) == "a-b-c-d-e.md")
        #expect(ChatExportLogic.fileName(
            title: "   ", variant: .saveHTML
        ) == "chat.html")
        #expect(ChatExportLogic.fileName(
            title: "Chat", variant: .copyPlain
        ) == "Chat.txt")
    }
    @Test func longTitlesAreTruncated() {
        let name = ChatExportLogic.fileName(
            title: String(repeating: "x", count: 200), variant: .saveJSON
        )
        #expect(name.count == 85) // 80 chars + ".json"
    }
}
