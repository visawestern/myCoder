import Foundation

/// Решает, есть ли в коде уже встроенная нумерация строк (`42 | код`).
///
/// Зачем: `ContextMaterializer` встраивает РЕАЛЬНЫЕ номера строк файла, чтобы
/// модель и пользователь видели точные строки для цитат. Кодовый блок в чате
/// (`CodeBlockSpoilerView`) исторически рисовал свой gutter `1, 2, 3…`, из-за
/// чего появлялись два столбца номеров (C4, скриншот владельца 2026-11-09).
///
/// Логика намеренно строгая: блок считается нумерованным, только если КАЖДАЯ
/// непустая строка начинается с `N | ` и номера идут подряд. Иначе обычный
/// код с оператором `|` или diff не будет ошибочно принят за нумерацию.
enum CodeLineNumberingLogic {

    /// Встроенные номера строк, если они есть.
    ///
    /// Вход: `code` — содержимое кодового блока.
    /// Выход: массив номеров (по одной записи на непустую строку) или nil,
    /// если блок не является нумерованным.
    /// Зависимости: только Foundation (`NSRegularExpression`).
    static func embeddedLineNumbers(in code: String) -> [Int]? {
        let lines = code.components(separatedBy: "\n")
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)\s*\|\s?"#) else {
            return nil
        }

        var numbers: [Int] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let numberRange = Range(match.range(at: 1), in: line),
                  let number = Int(line[numberRange]) else {
                return nil
            }
            numbers.append(number)
        }

        // Одна строка — статистически неотличима от кода вида `1 | x`;
        // требуем минимум две строки и строгую последовательность +1.
        guard numbers.count >= 2 else { return nil }
        for index in 1..<numbers.count where numbers[index] != numbers[index - 1] + 1 {
            return nil
        }
        return numbers
    }

    /// Нужно ли рисовать собственный gutter кодового блока.
    ///
    /// Вход: `code` — содержимое блока; `showLineNumbers` — настройка
    /// «показывать номера строк».
    /// Выход: true, только если настройка включена и номера не встроены.
    /// Зависимости: `embeddedLineNumbers(in:)`.
    static func shouldShowGutter(code: String, showLineNumbers: Bool) -> Bool {
        guard showLineNumbers else { return false }
        return embeddedLineNumbers(in: code) == nil
    }
}
