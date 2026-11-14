import Foundation

/// Метаданные результата вызова инструмента, известные ещё до загрузки
/// самого текста. История чата грузится в «lite»-режиме: вместо текста
/// результата приходит только этот факт, поэтому спойлеры открываются
/// лениво (по требованию), а не тащат все выды тулов при открытии чата.
struct ToolResultMeta: Equatable {
    /// Идентификатор вызова (callID): ключ, по которому результат
    /// запрашивается из хранилища.
    let callID: String
    /// True, когда в хранилище существует непустой текст результата.
    let hasStoredResult: Bool
    /// Длина хранимого текста результата (символы), 0 — когда результата
    /// нет. Позволяет оценивать объём/токены без чтения текста.
    let length: Int
}

/// RAM-хранилище текстов результатов тулов. Живёт только в памяти
/// программы (никогда не пишет на диск), очищается при выходе.
/// Записи попадают сюда при ленивой подгрузке спойлеров и
/// переиспользуются при повторном открытии, переключении чатов и
/// ресайкле строк — база не опрашивается повторно.
///
/// Вход: `insert` — пара «callID → текст результата»; `get` — callID.
/// Выход: текст результата; счётчики попаданий/промахов/вставок.
/// Зависимости: нет (чистое хранилище, MainActor).
@MainActor
final class ToolResultStore {
    static let shared = ToolResultStore()

    private(set) var results: [String: String] = [:]
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var inserts = 0

    /// Достать результат по callID. Считает попадание/промах.
    func get(_ key: String) -> String? {
        if let value = results[key] {
            hits += 1
            return value
        }
        misses += 1
        return nil
    }

    /// Пакетно сохранить результаты (перезаписывает существующие ключи).
    func insert(_ values: [String: String]) {
        for (key, value) in values {
            results[key] = value
        }
        inserts += values.count
    }

    /// Полностью очистить хранилище (тесты/выход).
    func reset() {
        results = [:]
        hits = 0
        misses = 0
        inserts = 0
    }
}

/// Загрузчик результатов тулов для UI: сначала RAM (`ToolResultStore`),
/// затем одним пакетным запросом БД. Найденное сохраняется в store, чтобы
/// повторные открытия спойлеров и переключения чатов не лезли в базу.
///
/// Вход: `steps` — шаги вызовов инструментов.
/// Выход: словарь «ключ хранилища → текст результата» для всех шагов,
/// у которых результат существует.
/// Зависимости: `ToolCallRequestLogic`, `ToolResultHydrationLogic`,
/// `ToolResultStore`, `DatabaseManager.getToolResults`.
@MainActor
enum ToolResultLoader {
    static func load(for steps: [ToolCallInspectorStep]) -> [String: String] {
        let keys = ToolCallRequestLogic.keysToLoad(steps)
        guard !keys.isEmpty else { return [:] }
        let split = ToolResultHydrationLogic.splitKeys(keys, memory: ToolResultStore.shared.results)
        var available = split.fromMemory
        if !split.missing.isEmpty {
            let fromDB = (try? DatabaseManager.shared.getToolResults(callIDs: split.missing)) ?? [:]
            available.merge(fromDB) { _, new in new }
            ToolResultStore.shared.insert(fromDB)
        }
        return available
    }
}
