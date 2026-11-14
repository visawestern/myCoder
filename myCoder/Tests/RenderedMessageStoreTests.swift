import Foundation
import Testing
@testable import myCoder

/// RAM-кэш отрендеренных пар сообщений (вопрос + ответ). Хранит только
/// в памяти программы, чистится при выходе. Жизненный цикл записей
/// управляется `RenderedMessageCacheLogic`: 100 пар/чат, 500 глобально,
/// LRU-вытеснение.
@MainActor
@Suite("RenderedMessageStore: RAM-кэш отрендеренных пар", .serialized)
struct RenderedMessageStoreTests {

    init() {
        RenderedMessageStore.shared.reset()
    }

    /// Стаб данных строки с осмысленным contentHash.
    private func stubRow(contentHash: Int) -> RenderedRowData {
        RenderedRowData(
            contentHash: contentHash,
            segmentsByText: [:],
            contentSegments: [],
            inlineImagePaths: []
        )
    }

    private func row(
        _ sessionID: String,
        _ pairIndex: Int,
        _ messageID: String,
        _ hash: Int
    ) -> RenderedRowData {
        RenderedMessageStore.shared.row(
            sessionID: sessionID,
            pairIndex: pairIndex,
            messageID: messageID,
            contentHash: hash
        ) { stubRow(contentHash: hash) }
    }

    @Test("row возвращает данные; повторный запрос с тем же хэшем не строит заново")
    func rowIsIdempotentPerHash() {
        var buildCount = 0
        let first = RenderedMessageStore.shared.row(
            sessionID: "s1", pairIndex: 0,
            messageID: "m1", contentHash: 7
        ) {
            buildCount += 1
            return stubRow(contentHash: 7)
        }
        let second = RenderedMessageStore.shared.row(
            sessionID: "s1", pairIndex: 0,
            messageID: "m1", contentHash: 7
        ) {
            buildCount += 1
            return stubRow(contentHash: 7)
        }
        #expect(first.contentHash == 7)
        #expect(second.contentHash == 7)
        #expect(buildCount == 1)
        #expect(RenderedMessageStore.shared.stats.hits == 1)
        #expect(RenderedMessageStore.shared.stats.inserts == 1)
        #expect(RenderedMessageStore.shared.totalPairs == 1)
    }

    @Test("Новый хэш по тому же ключу перезаписывает строку")
    func changedHashOverwritesRow() {
        let first = RenderedMessageStore.shared.row(
            sessionID: "s1", pairIndex: 0,
            messageID: "m1", contentHash: 1
        ) { stubRow(contentHash: 1) }
        let updated = RenderedMessageStore.shared.row(
            sessionID: "s1", pairIndex: 0,
            messageID: "m1", contentHash: 2
        ) { stubRow(contentHash: 2) }
        #expect(first.contentHash == 1)
        #expect(updated.contentHash == 2)
        #expect(RenderedMessageStore.shared.totalPairs == 1)
    }

    @Test("Строки одной пары разделяют одну запись, но хранят свои данные")
    func rowsOfSamePairShareRecord() {
        let user = row("s1", 0, "u1", 11)
        let assistant = row("s1", 0, "a1", 22)
        #expect(user.contentHash == 11)
        #expect(assistant.contentHash == 22)
        #expect(RenderedMessageStore.shared.totalPairs == 1)
        #expect(RenderedMessageStore.shared.stats.inserts == 1)
    }

    @Test("Свыше 100 пар чата старейшие пары выгружаются из памяти")
    func perChatEvictionRemovesOldestRecords() {
        for i in 0..<105 {
            _ = row("c", i, "u\(i)", i)
        }
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "c", pairIndex: 0)
        ) == nil)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "c", pairIndex: 4)
        ) == nil)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "c", pairIndex: 5)
        ) != nil)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "c", pairIndex: 104)
        ) != nil)
        #expect(RenderedMessageStore.shared.stats.evictions == 5)
        #expect(RenderedMessageStore.shared.totalPairs == 100)
    }

    @Test("Свыше 500 пар глобально выгружается самый старый чат")
    func globalEvictionRemovesOldestChatFirst() {
        // Шесть чатов по 90 = 540: чат A теряет 40 старейших пар.
        for chat in ["A", "B", "C", "D", "E", "F"] {
            for i in 0..<90 {
                _ = row(chat, i, "m\(i)", i)
            }
        }
        #expect(RenderedMessageStore.shared.totalPairs == 500)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "A", pairIndex: 0)
        ) == nil)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "A", pairIndex: 39)
        ) == nil)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "A", pairIndex: 40)
        ) != nil)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "F", pairIndex: 89)
        ) != nil)
        #expect(RenderedMessageStore.shared.stats.evictions == 40)
    }

    @Test("removeChat чистит все записи чата")
    func removeChatClearsRecords() {
        for i in 0..<10 {
            _ = row("gone", i, "m\(i)", i)
        }
        RenderedMessageStore.shared.removeChat(sessionID: "gone")
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "gone", pairIndex: 3)
        ) == nil)
        #expect(RenderedMessageStore.shared.totalPairs == 0)
    }

    @Test("record считает попадания и промахи")
    func recordCountsHitsAndMisses() {
        _ = row("s1", 0, "m1", 1)
        // Первый build — промах, попадание по существующей паре,
        // второй промах — по отсутствующей паре.
        _ = RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "s1", pairIndex: 0)
        )
        _ = RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "s1", pairIndex: 99)
        )
        #expect(RenderedMessageStore.shared.stats.hits == 1)
        #expect(RenderedMessageStore.shared.stats.misses == 2)
    }

    @Test("reset полностью очищает кэш и счётчики")
    func resetClearsEverything() {
        _ = row("s1", 0, "m1", 1)
        RenderedMessageStore.shared.reset()
        #expect(RenderedMessageStore.shared.totalPairs == 0)
        #expect(RenderedMessageStore.shared.record(
            for: RenderedMessageKey(sessionID: "s1", pairIndex: 0)
        ) == nil)
        #expect(RenderedMessageStore.shared.stats.inserts == 0)
        #expect(RenderedMessageStore.shared.stats.evictions == 0)
    }
}
