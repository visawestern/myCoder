import Foundation
import Testing
@testable import myCoder

/// Чистая логика сборки данных рендера строки (`RenderedRowData`): один
/// раз разобранные сегменты, сегменты контента и inline-пути картинок +
/// стабильный хэш для инвалидации.
@Suite("RenderedPairBuilder: сборка данных рендера строки")
struct RenderedPairBuilderTests {

    @Test("build собирает сегменты, сегменты контента и inline-пути")
    func buildCollectsAllData() throws {
        // Реальный PNG-файл, чтобы inlineImagePaths мог его резолвить.
        let imageURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rendered-pair-test-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let message = Message(
            role: .assistant,
            content: "",
            parts: [
                .text("до ![x](img.png) после"),
                .toolCall(name: "read", args: "{}", result: "ok", callID: "c1"),
                .text("```swift\nlet a = 1\n```"),
                .text("смотри \(imageURL.path)"),
            ],
            reasoning: "думаю",
            isFinished: true
        )
        let row = RenderedPairBuilder.buildRow(message: message, projectRoot: nil)

        // Сегменты markdown ключуются по очищенному тексту.
        let firstText = "до ![x](img.png) после"
        let codeText = "```swift\nlet a = 1\n```"
        #expect(row.segmentsByText[firstText]?.contains(.image(alt: "x", source: "img.png")) == true)
        #expect(row.segmentsByText[firstText]?.contains(.prose("до")) == true)
        #expect(row.segmentsByText[codeText]?.contains { if case .code = $0 { return true }; return false } == true)

        // Сегменты контента: tool-calls + текст.
        let kinds = row.contentSegments.map { segment -> String in
            switch segment {
            case .toolCalls(let calls): return "tools(\(calls.count))"
            case .part(let part):
                if case .text = part { return "text" }
                return "part"
            case .reasoning(let blocks): return "reasoning(\(blocks.count))"
            case .approval: return "approval"
            }
        }
        #expect(kinds.contains("tools(1)"))
        #expect(kinds.contains("text"))

        // Inline-пути картинок: только существующие файлы.
        #expect(row.inlineImagePaths.contains(imageURL.path))
        #expect(!row.inlineImagePaths.contains("img.png"))
    }

    @Test("contentHash меняется при изменении текста")
    func hashChangesWithText() {
        let a = Message(role: .assistant, content: "первый вариант", isFinished: true)
        let b = Message(role: .assistant, content: "второй вариант", isFinished: true)
        #expect(RenderedPairBuilder.contentHash(message: a) != RenderedPairBuilder.contentHash(message: b))
    }

    @Test("contentHash меняется при изменении результата тула")
    func hashChangesWithToolResult() {
        let a = Message(
            role: .assistant, content: "",
            parts: [.toolCall(name: "read", args: "{}", result: "ok", callID: "c1")],
            isFinished: true
        )
        let b = Message(
            role: .assistant, content: "",
            parts: [.toolCall(name: "read", args: "{}", result: "изменён", callID: "c1")],
            isFinished: true
        )
        #expect(RenderedPairBuilder.contentHash(message: a) != RenderedPairBuilder.contentHash(message: b))
    }

    @Test("contentHash стабилен для эквивалентных сообщений")
    func hashStableForEqualMessages() {
        let a = Message(
            role: .user, content: "вопрос",
            parts: [.text("вопрос")],
            isFinished: true
        )
        let b = Message(
            role: .user, content: "вопрос",
            parts: [.text("вопрос")],
            isFinished: true
        )
        #expect(RenderedPairBuilder.contentHash(message: a) == RenderedPairBuilder.contentHash(message: b))
    }

    @Test("Хэш учитывает вызвания approvals (карточки одобрения)")
    func hashAccountsForApprovals() {
        let approval = PendingToolApproval(
            id: "ap1", callID: "c1", tool: "write",
            message: "allow?", createdAt: Date()
        )
        let a = Message(
            role: .assistant, content: "",
            parts: [.toolCall(name: "write", args: "{}", result: nil, callID: "c1")],
            isFinished: true
        )
        let b = Message(
            role: .assistant, content: "",
            parts: [.toolCall(name: "write", args: "{}", result: nil, callID: "c1")],
            isFinished: true,
            pendingApprovals: [approval]
        )
        #expect(RenderedPairBuilder.contentHash(message: a) != RenderedPairBuilder.contentHash(message: b))
    }
}
