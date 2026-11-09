import Foundation

/// Правила подгрузки старых сообщений без рывков.
///
/// Живой дефект 2026-11-09: при прокрутке вверх лента «докачивалась» и резко
/// прыгала. Причина — страница вставлялась НАД вьюпортом, а позиция
/// восстанавливалась отдельным `scrollTo` на следующем тике: сначала контент
/// уезжал вниз, потом возвращался. Мессенджеры вместо этого компенсируют
/// смещение ровно на высоту вставленного контента.
enum ChatPaginationLogic {

    /// За сколько точек до верха начинать подгрузку. Одна страница грузится
    /// заранее, чтобы к моменту, когда читатель дойдёт до верха, она уже
    /// была в памяти (иначе виден «пустой» кадр и рывок).
    static let prefetchDistance: CGFloat = 600

    /// Пора ли тянуть следующую страницу истории.
    static func shouldPrefetch(
        offsetY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat = prefetchDistance
    ) -> Bool {
        guard viewportHeight > 0 else { return false }
        // Ровно 0 — это самый верх нового чата/первый кадр после открытия:
        // там подгрузка не нужна, её делает кнопка/пользователь.
        return offsetY > 0 && offsetY <= threshold
    }

    /// Выбирает первую строку, пересекающую верх вьюпорта, для компенсации
    /// prepend. Вход: стабильные content-relative кадры и offset; выход: id
    /// ближайшей видимой строки. Без UI/БД, чтобы правило проверялось тестом.
    static func visibleAnchor(frames: [String: CGRect], offsetY: CGFloat) -> String? {
        frames.filter { $0.value.maxY > offsetY }
            .min { $0.value.minY < $1.value.minY }?.key
    }

    /// Новое смещение, при котором вьюпорт остаётся визуально на месте после
    /// вставки контента над ним. `anchorShift` — на сколько точек вниз
    /// сдвинулась опорная строка (равно высоте вставленного блока).
    static func preservedOffset(
        oldOffset: CGFloat,
        anchorShift: CGFloat,
        maxOffset: CGFloat
    ) -> CGFloat {
        let target = oldOffset + anchorShift
        return min(max(0, target), max(0, maxOffset))
    }
}
