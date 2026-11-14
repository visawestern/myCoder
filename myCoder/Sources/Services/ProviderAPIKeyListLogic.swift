import Foundation

/// Чистая логика списка API-ключей провайдера.
///
/// Пользователь редактирует ключи как ОБЫЧНЫЙ СПИСОК (одно поле на ключ,
/// кнопка «+» добавляет, корзина удаляет), а не как textarea «по одному на
/// строку». Первая строка списка — основной ключ провайдера
/// (`CustomProvider.apiKey`), остальные — пул (`ProviderAPIKeyPoolStore`).
///
/// Логика не знает ни о SwiftUI, ни о `UserDefaults`: она только собирает
/// список из основной пары (primary + pool) и разбирает его обратно, поэтому
/// её можно переносить и тестировать отдельно от интерфейса.
///
/// Входы: основной ключ, пул, список строк из UI.
/// Выходы: список строк для UI / пара (primary, pool) для сохранения.
/// Зависимости: только `Foundation`.
enum ProviderAPIKeyListLogic {

    /// Собрать список строк для UI.
    ///
    /// Убирает пробелы, пустые строки и дубликаты; если ключей нет, список
    /// содержит одну пустую строку — поле для ввода первого ключа.
    ///
    /// - Parameters:
    ///   - primary: основной ключ провайдера (может быть пустым/absent).
    ///   - pool: дополнительные ключи пула.
    /// - Returns: строки для полей ввода; первая строка — основной ключ.
    static func fullList(primary: String?, pool: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        let primaryTrimmed = (primary ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !primaryTrimmed.isEmpty {
            result.append(primaryTrimmed)
            seen.insert(primaryTrimmed)
        }

        for key in pool {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }

        if result.isEmpty {
            result = [""]
        }
        return result
    }

    /// Разобрать строки из UI обратно в пару «основной ключ + пул».
    ///
    /// Первая непустая строка становится основным ключом, остальные
    /// непустые и недублирующиеся — пулом. Пробелы обрезаются.
    ///
    /// - Parameter list: строки из полей ввода.
    /// - Returns: пара (primary, pool); обе части могут быть пустыми.
    static func split(list: [String]) -> (primary: String, pool: [String]) {
        let cleaned = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = cleaned.first else {
            return ("", [])
        }
        var seen: Set<String> = [first]
        var pool: [String] = []
        for key in cleaned.dropFirst() where seen.insert(key).inserted {
            pool.append(key)
        }
        return (first, pool)
    }

    /// Основной ключ провайдера из строк UI: первая непустая строка после
    /// трима. Единый источник истины — список пула; отдельного поля ключа
    /// нет (директива 2026-11-14: «API-ключ» и «пул ключей» — одно и то же).
    ///
    /// - Parameter list: строки из полей ввода (первая — основной ключ).
    /// - Returns: основной ключ или пустая строка.
    static func primary(from list: [String]) -> String {
        split(list: list).primary
    }
}
