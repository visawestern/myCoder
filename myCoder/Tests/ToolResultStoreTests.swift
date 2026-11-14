import Foundation
import Testing
@testable import myCoder

/// RAM-хранилище результатов тулов: живёт только в памяти программы, не
/// пишет на диск и очищается при выходе. Покрывает попадания/промахи,
/// пакетную вставку и дозагрузку.
@MainActor
@Suite("RAM-хранилище результатов тулов (ToolResultStore)", .serialized)
struct ToolResultStoreTests {

    init() {
        ToolResultStore.shared.reset()
    }

    @Test("get возвращает сохранённый результат и считает попадание")
    func getReturnsStored() {
        ToolResultStore.shared.insert(["call-1": "{\"ok\":true}"])
        #expect(ToolResultStore.shared.get("call-1") == "{\"ok\":true}")
        #expect(ToolResultStore.shared.hits == 1)
    }

    @Test("get по отсутствующему ключу возвращает nil и считает промах")
    func getMissingCountsMiss() {
        #expect(ToolResultStore.shared.get("call-missing") == nil)
        #expect(ToolResultStore.shared.misses == 1)
    }

    @Test("insert пакетно перезаписывает и считает вставки")
    func insertBatchOverwrites() {
        ToolResultStore.shared.insert(["a": "1", "b": "2"])
        ToolResultStore.shared.insert(["b": "22", "c": "3"])
        #expect(ToolResultStore.shared.results == ["a": "1", "b": "22", "c": "3"])
        #expect(ToolResultStore.shared.inserts == 4)
    }

    @Test("reset очищает данные и счётчики")
    func resetClearsEverything() {
        ToolResultStore.shared.insert(["a": "1"])
        ToolResultStore.shared.get("a")
        ToolResultStore.shared.reset()
        #expect(ToolResultStore.shared.results.isEmpty)
        #expect(ToolResultStore.shared.hits == 0)
        #expect(ToolResultStore.shared.misses == 0)
        #expect(ToolResultStore.shared.inserts == 0)
    }

    @Test("повторная вставка того же ключа не растит память дублями")
    func idempotentInsert() {
        ToolResultStore.shared.insert(["k": "v"])
        ToolResultStore.shared.insert(["k": "v"])
        #expect(ToolResultStore.shared.results.count == 1)
    }
}
