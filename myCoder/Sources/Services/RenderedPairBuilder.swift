import Foundation
import SwiftUI

/// Чистая сборка данных рендера строки (`RenderedRowData`): разбор
/// markdown-сегментов по каждому текстовому фрагменту, сегменты
/// контента и inline-пути картинок — всё один раз, с последующим
/// кэшированием в `RenderedMessageStore`.
enum RenderedPairBuilder {
    /// Стабильный хэш контента строки: текст, reasoning, части (включая
    /// результаты тулов), карточки одобрения и стриминг-флаг. Меняется
    /// при изменении любого из них — этого достаточно для инвалидации.
    ///
    /// Вход: `message`.
    /// Выход: число-хэш.
    /// Зависимости: нет (чистая функция).
    static func contentHash(message: Message) -> Int {
        var hasher = Hasher()
        hasher.combine(message.content)
        hasher.combine(message.reasoning)
        hasher.combine(message.isStreaming)
        for part in message.parts {
            switch part {
            case .toolCall(let name, let args, let result, let callID):
                hasher.combine("tool")
                hasher.combine(name)
                hasher.combine(args)
                hasher.combine(result)
                hasher.combine(callID)
            default:
                hasher.combine(part.id)
            }
        }
        for approval in message.pendingApprovals {
            hasher.combine(approval.id)
            hasher.combine(approval.callID)
        }
        return hasher.finalize()
    }

    /// Собрать данные рендера строки.
    ///
    /// Вход: `message`; `projectRoot` — корень проекта для путей картинок.
    /// Выход: `RenderedRowData` (сегменты по текстам, сегменты контента,
    /// inline-пути).
    /// Зависимости: `MessageContentSanitizerLogic`, `MarkdownMediaSegmentLogic`,
    /// `MessageContentSegment`, `MessageRowPartsLogic`, `MessageDisplayLogic`,
    /// `ChatImagePathLogic`.
    static func buildRow(message: Message, projectRoot: String?) -> RenderedRowData {
        let partTexts = message.parts.compactMap { part -> String? in
            if case .text(let text) = part { return text }
            return nil
        }
        let displayTexts = MessageContentSanitizerLogic.displayTexts(
            partTexts: partTexts,
            fallback: message.content
        )

        var segmentsByText: [String: [MarkdownMediaSegment]] = [:]
        for text in displayTexts {
            guard let sanitized = MessageContentSanitizerLogic.sanitizedTextPart(text) else { continue }
            segmentsByText[sanitized] = MarkdownMediaSegmentLogic.segments(from: sanitized)
        }

        let contentSegments = MessageContentSegment.build(
            from: MessageRowPartsLogic.displayParts(
                parts: MessageDisplayLogic.withoutImageParts(
                    MessageDisplayLogic.chatDisplayParts(message.parts)
                ),
                content: message.content
            ),
            approvals: message.pendingApprovals,
            toolResultMeta: message.toolResultMeta
        )

        let joinedText = displayTexts.joined(separator: "\n\n")
        let inlineImagePaths = ChatImagePathLogic.extractImagePaths(
            from: joinedText,
            projectRoot: (projectRoot?.isEmpty == false) ? projectRoot : nil
        )

        return RenderedRowData(
            contentHash: contentHash(message: message),
            segmentsByText: segmentsByText,
            contentSegments: contentSegments,
            inlineImagePaths: inlineImagePaths
        )
    }
}
