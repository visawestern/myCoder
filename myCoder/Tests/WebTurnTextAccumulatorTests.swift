import Testing
import Foundation
@testable import myCoder

/// WebTurnTextAccumulator: snapshot-streaming text accumulation for a web
/// turn (user directive 2026-09-11 — nothing the model produced may be
/// erased; earlier thinking and post-tool answers accumulate as blocks).
@Suite("WebTurnTextAccumulator — append-only turn text")
struct WebTurnTextAccumulatorTests {

    @Test("Growing snapshots extend, never duplicate")
    func growingSnapshotsExtend() {
        let acc = WebTurnTextAccumulator()
        #expect(acc.absorb("Думаю о задаче") == "Думаю о задаче")
        #expect(acc.absorb("Думаю о задаче. Сначала") == "Думаю о задаче. Сначала")
        #expect(acc.absorb("Думаю о задаче. Сначала сделаю листинг") == "Думаю о задаче. Сначала сделаю листинг")
        // No duplication of earlier prefixes.
        #expect(acc.absorb("Думаю о задаче. Сначала сделаю листинг").components(separatedBy: "Думаю").count == 2)
    }

    @Test("Shorter echo does not roll the text back")
    func shorterEchoKeepsLongest() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("полный текст размышления")
        // A transient vendor re-render showing a prefix must not truncate.
        #expect(acc.absorb("полный текст").contains("размышления"))
    }

    @Test("New message after tool round starts a fresh block")
    func toolRoundSplitsBlocks() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("Смотрю файл")
        acc.closeBlock()
        let merged = acc.absorb("В папке 4 элемента")
        #expect(merged.contains("---"))
        #expect(merged.contains("Смотрю файл"))
        #expect(merged.hasSuffix("В папке 4 элемента"))
    }

    @Test("Final answer keeps thinking and appends")
    func finalKeepsThinking() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("Мыслим: нужен листинг")
        let final = acc.absorbFinal("В папке 4 элемента: A, B, C, D.")
        #expect(final.contains("Мыслим: нужен листинг"))
        #expect(final.contains("В папке 4 элемента"))
        // The final block is not a duplicate of the thinking block.
        #expect(final.components(separatedBy: "Мыслим").count == 2)
    }

    @Test("Final extending the live snapshot merges without duplication")
    func finalExtendingSnapshotMerges() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("Ответ гот")
        let final = acc.absorbFinal("Ответ готов: 42.")
        #expect(final == "Ответ готов: 42.")
    }

    @Test("Empty snapshots change nothing")
    func emptySnapshotsIgnored() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("текст")
        #expect(acc.absorb("") == "текст")
        #expect(acc.absorb("   ") == "текст")
    }

    @Test("Re-rendered draft does not duplicate (live 2026-09-12: 56 blocks)")
    func rerenderedDraftAdopted() {
        // Kimi re-renders markdown mid-stream: the broken "**`" tail of the
        // first poll is gone in the second, so strict hasPrefix fails.
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("Файл получен целиком (6/6). Что я вижу:\n**`TZ-Bezdna")
        let merged = acc.absorb("Файл получен целиком (6/6). Что я вижу:\nTZ-Bezdna-v3.md — GDD версии 3.3 для «Бездны»")
        #expect(!merged.contains("---"), "one draft = one block, got: \(merged)")
        #expect(merged.hasSuffix("TZ-Bezdna-v3.md — GDD версии 3.3 для «Бездны»"))
        #expect(merged.components(separatedBy: "Файл получен").count == 2)
    }

    @Test("Snapshot containing the old text adopts it (new head)")
    func containingSnapshotAdopted() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("второй абзац")
        let merged = acc.absorb("Thinking…\nвторой абзац продолжает расти")
        #expect(!merged.contains("---"), "got: \(merged)")
        #expect(merged.hasPrefix("Thinking…"))
    }

    @Test("Distinct same-round notes stay in separate blocks")
    func distinctNotesSplit() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("Часть 2/7 получена (пустой результат). Жду дальше.")
        let merged = acc.absorb("Часть 3/7: read_file снова вернул начало файла.")
        #expect(merged.contains("---"), "different notes must split, got: \(merged)")
    }

    @Test("Final re-rendered draft merges instead of duplicating")
    func finalRerenderedDraftMerges() {
        let acc = WebTurnTextAccumulator()
        _ = acc.absorb("OK, now I can respond. Summary:`read_file ignores")
        let final = acc.absorbFinal("OK, now I can respond. Summary: read_file ignores offset.")
        #expect(!final.contains("---"), "got: \(final)")
        #expect(final.hasSuffix("ignores offset."))
    }
}
