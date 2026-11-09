import Foundation

/// Раскладка картинок одного сообщения (C5).
///
/// Зачем отдельный тип: сообщение может содержать 1, 2, 3 и больше картинок.
/// Раньше каждая `.image`-часть рисовалась отдельной большой картинкой в
/// вертикальном потоке, поэтому 7 вложений растягивали сообщение на семь
/// экранов (жалоба владельца 2026-11-09). Коллаж показывает одну большую
/// картинку и до трёх миниатюр сбоку, а остальные сворачивает в счётчик `+N`.
enum MessageImageCollageLayout: Equatable {
    /// Картинок нет — коллаж не рисуется.
    case empty
    /// Одна картинка — обычный одиночный предпросмотр.
    case single
    /// Две картинки — равная пара.
    case pair
    /// Три и больше — большая картинка + колонка миниатюр.
    /// `sideCount` — сколько миниатюр реально видно; `hiddenCount` — сколько
    /// свернуто в счётчик `+N` на последней миниатюре.
    case featured(sideCount: Int, hiddenCount: Int)
}

enum MessageImageCollageLogic {
    /// Максимум миниатюр в боковой колонке. Четыре видимых картинки (одна
    /// большая + три миниатюры) — предел, после которого коллаж начинает
    /// спорить с текстом сообщения по высоте.
    static let maxSideImages = 3

    /// Раскладка коллажа по количеству картинок.
    ///
    /// Вход: `imageCount` — число непустых картинок; `maxSideImages` —
    /// максимум миниатюр в колонке (по умолчанию `maxSideImages`).
    /// Выход: `MessageImageCollageLayout`.
    /// Зависимости: нет (чистая функция).
    static func layout(
        imageCount: Int,
        maxSideImages: Int = maxSideImages
    ) -> MessageImageCollageLayout {
        guard imageCount > 0 else { return .empty }
        if imageCount == 1 { return .single }
        if imageCount == 2 { return .pair }

        let limit = max(0, maxSideImages)
        let sideCount = min(imageCount - 1, limit)
        let hiddenCount = max(0, imageCount - 1 - sideCount)
        return .featured(sideCount: sideCount, hiddenCount: hiddenCount)
    }
}
