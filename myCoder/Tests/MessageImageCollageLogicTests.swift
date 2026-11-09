import Testing
import Foundation
@testable import myCoder

/// C5 (жалоба владельца 2026-11-09, скриншот): «картинки >1 в сообщении идут
/// в столбик внизу — нужен коллаж: одна большая + остальные сбоку».
///
/// Здесь проверяется чистая раскладка, без SwiftUI:
///   - 1 картинка  → одна обычная;
///   - 2 картинки  → пара;
///   - 3+ картинок → большая + колонка миниатюр;
///   - больше 4    → на последней миниатюре счётчик скрытых (`+N`).
///
/// Отдельно проверяется, что `.image`-части больше не попадают в вертикальный
/// поток текста (их рисует коллаж), а legacy `attachedImages` не дублируются.
@Suite("Коллаж картинок в сообщении (C5)")
struct MessageImageCollageLogicTests {

    // MARK: - Раскладка

    @Test("Нет картинок — нет коллажа")
    func empty() {
        #expect(MessageImageCollageLogic.layout(imageCount: 0) == .empty)
        #expect(MessageImageCollageLogic.layout(imageCount: -1) == .empty)
    }

    @Test("Одна картинка — обычный одиночный рендер")
    func single() {
        #expect(MessageImageCollageLogic.layout(imageCount: 1) == .single)
    }

    @Test("Две картинки — пара одинакового размера")
    func pair() {
        #expect(MessageImageCollageLogic.layout(imageCount: 2) == .pair)
    }

    @Test("Три картинки — большая + две миниатюры")
    func three() {
        #expect(
            MessageImageCollageLogic.layout(imageCount: 3)
                == .featured(sideCount: 2, hiddenCount: 0)
        )
    }

    @Test("Четыре картинки — большая + три миниатюры без счётчика")
    func four() {
        #expect(
            MessageImageCollageLogic.layout(imageCount: 4)
                == .featured(sideCount: 3, hiddenCount: 0)
        )
    }

    @Test("Семь картинок — большая + три миниатюры, на последней +3")
    func seven() {
        #expect(
            MessageImageCollageLogic.layout(imageCount: 7)
                == .featured(sideCount: 3, hiddenCount: 3)
        )
    }

    @Test("Количество миниатюр ограничено и настраиваемо")
    func sideLimitIsConfigurable() {
        #expect(
            MessageImageCollageLogic.layout(imageCount: 10, maxSideImages: 2)
                == .featured(sideCount: 2, hiddenCount: 7)
        )
        #expect(
            MessageImageCollageLogic.layout(imageCount: 5, maxSideImages: 0)
                == .featured(sideCount: 0, hiddenCount: 4)
        )
    }

    // MARK: - Источник картинок

    private func userMessage(
        parts: [MessagePartContent],
        attachedImages: [ClipboardImage]? = nil
    ) -> Message {
        Message(
            role: .user,
            content: "look",
            parts: parts,
            isFinished: true,
            attachedImages: attachedImages
        )
    }

    @Test("Картинки берутся из .image-частей в исходном порядке")
    func imagesFromPartsInOrder() {
        let message = userMessage(parts: [
            .text("look"),
            .image(base64: "AAA", mimeType: "image/png"),
            .image(base64: "BBB", mimeType: "image/jpeg"),
        ])

        let images = MessageDisplayLogic.imagesForDisplay(message)
        #expect(images.count == 2)
        #expect(images.map(\.base64) == ["AAA", "BBB"])
        #expect(images.map(\.mimeType) == ["image/png", "image/jpeg"])
    }

    @Test("Legacy attachedImages не дублируются, когда есть .image-части")
    func legacyImagesNotDuplicated() {
        let message = userMessage(
            parts: [.image(base64: "AAA", mimeType: "image/png")],
            attachedImages: [ClipboardImage(base64: "LEGACY", mimeType: "image/png")]
        )
        let images = MessageDisplayLogic.imagesForDisplay(message)
        #expect(images.map(\.base64) == ["AAA"])
    }

    @Test("Без .image-частей используются legacy attachedImages")
    func legacyImagesFallback() {
        let message = userMessage(
            parts: [.text("look")],
            attachedImages: [
                ClipboardImage(base64: "LEGACY-1", mimeType: "image/png"),
                ClipboardImage(base64: "LEGACY-2", mimeType: "image/jpeg"),
            ]
        )
        let images = MessageDisplayLogic.imagesForDisplay(message)
        #expect(images.map(\.base64) == ["LEGACY-1", "LEGACY-2"])
    }

    @Test("Пустые картинки не попадают в коллаж")
    func emptyImagesSkipped() {
        let message = userMessage(parts: [
            .image(base64: "", mimeType: "image/png"),
            .image(base64: "BBB", mimeType: "image/png"),
        ])
        #expect(MessageDisplayLogic.imagesForDisplay(message).map(\.base64) == ["BBB"])
    }

    @Test(".image-части исключаются из вертикального потока текста")
    func imagePartsRemovedFromContentFlow() {
        let parts: [MessagePartContent] = [
            .text("look"),
            .image(base64: "AAA", mimeType: "image/png"),
            .text("and this"),
        ]
        let filtered = MessageDisplayLogic.withoutImageParts(parts)

        #expect(filtered.count == 2)
        #expect(filtered.contains { if case .text("look") = $0 { return true }; return false })
        #expect(filtered.contains { if case .text("and this") = $0 { return true }; return false })
        #expect(!filtered.contains { if case .image = $0 { return true }; return false })
    }
}
