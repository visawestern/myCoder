import Foundation
import SwiftUI

/// Данные рендера ОДНОЙ строки чата (одно сообщение): разобранные один
/// раз сегменты markdown, сегменты контента и inline-пути картинок.
/// Раньше всё это пересчитывалось на каждый body-eval строки.
struct RenderedRowData: Sendable {
    /// Хэш контента строки: для инвалидации при изменении сообщения.
    let contentHash: Int
    /// Разбиение текстов на прозу/код/картинки — по каждому очищенному
    /// текстовому фрагменту (ключ — сам текст), чтобы пузыри сообщения
    /// сохраняли свою группировку.
    let segmentsByText: [String: [MarkdownMediaSegment]]
    /// Сегменты контента (tool-calls, reasoning, approvals, текст).
    let contentSegments: [MessageContentSegment]
    /// Инлайн-пути картинок из текста.
    let inlineImagePaths: [String]
}

/// Запись кэша пары (вопрос + ответ): строки этой пары. У вопроса и его
/// ответов общий номер пары, поэтому они разделяют одну запись, а
/// лимиты кэша работают ровно в парах, как их считает пользователь.
struct RenderedPairRecord: Sendable {
    var rows: [String: RenderedRowData] = [:]
}

/// RAM-кэш отрендеренных пар сообщений. Живёт только в памяти программы,
/// на диск не пишет, чистится при выходе. Лимиты — `RenderedMessageCacheLogic`:
/// 100 пар на чат, 500 глобально, LRU-вытеснение (самый старый чат
/// выгружается первым при глобальном переполнении).
///
/// Вход: `row(...)` — строка (чат, номер пары, messageID, хэш, билдер).
/// Выход: данные рендера; счётчики hits/misses/inserts/evictions.
/// Зависимости: `RenderedMessageCacheLogic`, `RenderedPairRecord`.
@MainActor
final class RenderedMessageStore {
    static let shared = RenderedMessageStore()

    struct Stats: Equatable {
        var hits = 0
        var misses = 0
        var inserts = 0
        var evictions = 0
    }

    private(set) var stats = Stats()
    private var state = RenderedCacheState()
    private var records: [RenderedMessageKey: RenderedPairRecord] = [:]

    /// Общее число пар в кэше (для диагностики и тестов).
    var totalPairs: Int { state.totalPairs }

    /// Достать/собрать данные рендера строки. Если строка уже в кэше с
    /// тем же `contentHash` — возвращается из памяти (build не вызывается);
    /// иначе данные строятся замыканием и сохраняются. Вставка пары
    /// триггерит эвикцию по лимитам 100/500.
    ///
    /// Вход: `sessionID`, `pairIndex`, `messageID`, `contentHash`,
    /// `build` — замыкание, собирающее данные (вызывается только при
    /// промахе).
    /// Выход: `RenderedRowData`.
    /// Зависимости: `RenderedMessageCacheLogic`.
    @discardableResult
    func row(
        sessionID: String,
        pairIndex: Int,
        messageID: String,
        contentHash: Int,
        build: () -> RenderedRowData
    ) -> RenderedRowData {
        let key = RenderedMessageKey(sessionID: sessionID, pairIndex: pairIndex)
        let (nextState, evicted) = RenderedMessageCacheLogic.insert(
            sessionID: sessionID,
            pairIndex: pairIndex,
            state: state
        )
        state = nextState

        // Вытесненные пары освобождаем из памяти.
        for victim in evicted {
            records.removeValue(forKey: victim)
            stats.evictions += 1
        }

        if records[key] == nil {
            records[key] = RenderedPairRecord()
            stats.inserts += 1
        }

        guard var record = records[key] else { return build() }
        if let existing = record.rows[messageID], existing.contentHash == contentHash {
            stats.hits += 1
            return existing
        }
        let built = build()
        record.rows[messageID] = built
        records[key] = record
        stats.misses += 1
        return built
    }

    /// Достать запись пары целиком (для диагностики и тестов). Считает
    /// попадание/промах и отмечает обращение к чату (LRU).
    ///
    /// Вход: `key`.
    /// Выход: запись или nil.
    /// Зависимости: `RenderedMessageCacheLogic`.
    func record(for key: RenderedMessageKey) -> RenderedPairRecord? {
        guard let value = records[key] else {
            stats.misses += 1
            return nil
        }
        stats.hits += 1
        state = RenderedMessageCacheLogic.recordAccess(
            sessionID: key.sessionID,
            state: state
        )
        return value
    }

    /// Удалить все записи чата (например, при удалении чата).
    ///
    /// Вход: `sessionID`.
    /// Выход: нет.
    /// Зависимости: `RenderedMessageCacheLogic`.
    func removeChat(sessionID: String) {
        let (nextState, removed) = RenderedMessageCacheLogic.removeChat(
            sessionID: sessionID,
            state: state
        )
        state = nextState
        for key in removed {
            records.removeValue(forKey: key)
        }
    }

    /// Полностью очистить кэш (тесты/выход).
    func reset() {
        state = RenderedCacheState()
        records = [:]
        stats = Stats()
    }
}
