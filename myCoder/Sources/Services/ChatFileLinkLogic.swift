import Foundation
import AppKit

/// Чистая логика кликабельных путей в тексте ответа.
///
/// Проблема, которую закрывает этот модуль: путь подчёркивался фиолетовым,
/// но клик «ничего не делал», а курсор не менялся на палец. Причины:
/// 1) у пути не было атрибута `.link`, поэтому `NSTextView` не считал его
///    ссылкой (нет курсора-пальца и нет кликабельной зоны);
/// 2) меню открывалось в координатах окна, а `NSMenu.popUp` при `in: nil`
///    ждёт координаты экрана — меню уезжало за пределы видимой области;
/// 3) попадание в границу слова возвращало соседний символ, а не путь.
///
/// Здесь только чистые функции: построение ссылки своей схемы, разбор
/// ссылки обратно в путь, поиск кликабельных диапазонов и пересчёт
/// координат. Никакого UI и сети, поэтому модуль переносим и тестируем.
///
/// Входы: абсолютный путь / attributed-строка / точка в окне.
/// Выходы: ссылка `mycoder-file://…`, диапазоны, экранные координаты.
/// Зависимости: `Foundation`, `AppKit` (только `NSPoint`).
enum ChatFileLinkLogic {

    /// Схема ссылок на файлы чата. Отличается от `https://` и `file://`,
    /// чтобы клик по пути не открывал файл стандартным поведением AppKit,
    /// а показывал наше меню «Открыть с помощью / Показать в Finder».
    static let scheme = "mycoder-file"

    /// Превратить абсолютный путь в ссылку `mycoder-file`.
    ///
    /// Относительные и пустые пути не принимаются: в текст ответа попадают
    /// только разрешённые (`ChatFileOpenLogic.resolveFilePath`) абсолютные
    /// пути, поэтому безопасно требовать их и здесь.
    ///
    /// - Parameter path: абсолютный путь файла или папки.
    /// - Returns: `URL` со схемой `mycoder-file` или `nil`.
    static func url(forPath path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/") else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.path = trimmed
        return components.url
    }

    /// Достать путь из ссылки `mycoder-file`.
    ///
    /// Делегаты AppKit отдают ссылку и как `URL`, и как `String`, поэтому
    /// функция принимает `Any?`. Чужие схемы (`https://`, `file://`, числа,
    /// строки-мусор) отвергаются — ни один не выдаётся за файл чата.
    /// Ссылки вида `mycoder-file://host/path` (непустой host) тоже
    /// отвергаются: путь чата всегда бесхозный (`mycoder-file:/path`).
    ///
    /// - Parameter link: значение атрибута `.link` (URL или String).
    /// - Returns: абсолютный путь или `nil`.
    static func path(fromLink link: Any?) -> String? {
        if let url = link as? URL {
            guard url.scheme?.lowercased() == scheme,
                  url.host == nil || (url.host ?? "").isEmpty else { return nil }
            let path = url.path
            return path.isEmpty ? nil : path
        }
        if let string = link as? String,
           let url = URLComponents(string: string),
           url.scheme?.lowercased() == scheme,
           url.host == nil || (url.host ?? "").isEmpty,
           !url.path.isEmpty {
            return url.path
        }
        return nil
    }

    /// Диапазоны кликабельных путей в attributed-строке.
    ///
    /// Ищет атрибут `.chatFilePath` (абсолютный путь) и возвращает его
    /// диапазоны. Пустой результат — путей в тексте нет.
    ///
    /// - Parameter attributed: attributed-строка сообщения.
    /// - Returns: массив `NSRange` в порядке следования.
    static func clickableRanges(in attributed: NSAttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        attributed.enumerateAttribute(.chatFilePath, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let path = value as? String, !path.isEmpty {
                ranges.append(range)
            }
        }
        return ranges
    }

    /// Путь под индексом символа, или `nil`.
    ///
    /// Индекс за пределами строки или отрицательный не считается попаданием.
    /// Возвращает путь строго для индекса ВНУТРИ диапазона: индекс на
    /// границе (сразу после пути) — это уже пробел/следующий символ.
    ///
    /// - Parameters:
    ///   - attributed: attributed-строка сообщения.
    ///   - index: индекс символа в строке.
    /// - Returns: абсолютный путь или `nil`.
    static func absolutePath(in attributed: NSAttributedString, at index: Int) -> String? {
        guard index >= 0, index < attributed.length else { return nil }
        return attributed.attribute(.chatFilePath, at: index, effectiveRange: nil) as? String
    }

    /// Перевести точку из координат окна в координаты экрана.
    ///
    /// `NSMenu.popUp(positioning:at:in:nil)` ждёт координаты ЭКРАНА. На
    /// macOS и окно, и экран считают Y снизу вверх, поэтому достаточно
    /// сложить точку окна с его началом координат на экране.
    ///
    /// - Parameters:
    ///   - windowOrigin: `window.frame.origin` (нижний левый угол окна).
    ///   - inWindow: точка в координатах окна (`convert(_, from: nil)`).
    /// - Returns: точка в глобальных координатах экрана.
    static func screenPoint(windowOrigin: NSPoint, inWindow: NSPoint) -> NSPoint {
        NSPoint(x: windowOrigin.x + inWindow.x,
                y: windowOrigin.y + inWindow.y)
    }
}
