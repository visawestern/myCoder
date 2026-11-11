import Testing
import Foundation
@testable import myCoder

/// Стриминг раньше писал в БД на КАЖДЫЙ чанк: `saveMessage` делает INSERT
/// сообщения + DELETE всех parts + повторную вставку + обновление FTS, и всё
/// это на главном потоке. Десятки тяжёлых транзакций в секунду вызывали
/// «прыгающий чат». Промежуточные состояния должны жить в памяти, в БД
/// уходит не более одной записи за интервал плюс обязательный финал.
@MainActor
@Suite("Стриминг: троттлинг записи в БД")
struct StreamingMessageWriterTests {

    private final class Clock {
        var now: TimeInterval = 100
    }

    private final class Scheduler {
        var work: (() -> Void)?
        var scheduledCount = 0
        func fire() {
            let pending = work
            work = nil
            pending?()
        }
    }

    private final class Spy {
        struct Write: Equatable {
            let id: String
            let content: String
            let sessionID: String
        }
        var writes: [Write] = []
    }

    private func makeWriter(_ spy: Spy, _ clock: Clock, _ scheduler: Scheduler) -> StreamingMessageWriter {
        StreamingMessageWriter(
            write: { message, sessionID in
                spy.writes.append(Spy.Write(id: message.id, content: message.content, sessionID: sessionID))
            },
            clock: { clock.now },
            schedule: { _, work in
                scheduler.scheduledCount += 1
                scheduler.work = work
            }
        )
    }

    private func streaming(_ content: String) -> Message {
        Message(id: "live", role: .assistant, content: content, isStreaming: true)
    }

    @Test("Не-стриминговое изменение пишется сразу")
    func nonStreamingWritesImmediately() {
        let (spy, clock, scheduler) = (Spy(), Clock(), Scheduler())
        let writer = makeWriter(spy, clock, scheduler)
        writer.note(Message(id: "m", role: .user, content: "готово"), sessionID: "s1")
        #expect(spy.writes == [Spy.Write(id: "m", content: "готово", sessionID: "s1")])
        #expect(scheduler.scheduledCount == 0)
    }

    @Test("Сорок чанков за один интервал дают одну запись и один отложенный сброс")
    func chunksAreCoalesced() {
        let (spy, clock, scheduler) = (Spy(), Clock(), Scheduler())
        let writer = makeWriter(spy, clock, scheduler)
        for index in 0..<40 {
            writer.note(streaming("chunk\(index)"), sessionID: "s1")
        }
        #expect(spy.writes.count == 1)
        #expect(spy.writes.first?.content == "chunk0")
        // Один таймер на весь пачку, а не по таймеру на чанк.
        #expect(scheduler.scheduledCount == 1)

        scheduler.fire()
        #expect(spy.writes.count == 2)
        #expect(spy.writes.last?.content == "chunk39")
    }

    @Test("Финальный чанк сбрасывается сразу и не порождает лишнюю запись")
    func finishedChunkFlushesImmediately() {
        let (spy, clock, scheduler) = (Spy(), Clock(), Scheduler())
        let writer = makeWriter(spy, clock, scheduler)
        writer.note(streaming("a"), sessionID: "s1")
        writer.note(streaming("ab"), sessionID: "s1")
        writer.note(
            Message(id: "live", role: .assistant, content: "abc",
                    isStreaming: false, isFinished: true),
            sessionID: "s1"
        )
        #expect(spy.writes.last?.content == "abc")
        scheduler.fire()
        #expect(spy.writes.count == 2)
    }

    @Test("Интервал истёк — следующий чанк пишется немедленно")
    func intervalBoundaryAllowsWrite() {
        let (spy, clock, scheduler) = (Spy(), Clock(), Scheduler())
        let writer = makeWriter(spy, clock, scheduler)
        writer.note(streaming("a"), sessionID: "s1")
        writer.note(streaming("ab"), sessionID: "s1")
        #expect(spy.writes.count == 1)

        clock.now += StreamingWritePolicy.interval + 0.01
        writer.note(streaming("abc"), sessionID: "s1")
        #expect(spy.writes.count == 2)
        #expect(spy.writes.last?.content == "abc")
    }

    @Test("Отмена удаляет отложенную запись")
    func cancelDropsPendingWrite() {
        let (spy, clock, scheduler) = (Spy(), Clock(), Scheduler())
        let writer = makeWriter(spy, clock, scheduler)
        writer.note(streaming("a"), sessionID: "s1")
        writer.note(streaming("ab"), sessionID: "s1")
        writer.cancel(id: "live")
        scheduler.fire()
        #expect(spy.writes.count == 1)
    }

    @Test("Политика: финал всегда пишется, стриминг — только по интервалу")
    func policyDecisions() {
        let interval = StreamingWritePolicy.interval
        #expect(StreamingWritePolicy.shouldWriteNow(isStreaming: true, isFinished: false,
                                                    now: 10, lastWrite: nil))
        #expect(!StreamingWritePolicy.shouldWriteNow(isStreaming: true, isFinished: false,
                                                     now: 10.1, lastWrite: 10))
        // +0.001: Double(10) + 0.35 даёт 10.349999… и сравнение >= ловило
        // бы ошибку округления, а не поведение политики.
        #expect(StreamingWritePolicy.shouldWriteNow(isStreaming: true, isFinished: false,
                                                    now: 10 + interval + 0.001, lastWrite: 10))
        #expect(StreamingWritePolicy.shouldWriteNow(isStreaming: false, isFinished: true,
                                                    now: 10.01, lastWrite: 10))
        #expect(StreamingWritePolicy.shouldWriteNow(isStreaming: false, isFinished: false,
                                                    now: 10.01, lastWrite: 10))
    }

    @Test("MessageStore: 30 дельт не бьют по БД, финал сохраняет последний текст")
    func messageStoreCoalescesStreamingUpdates() {
        let (spy, clock, scheduler) = (Spy(), Clock(), Scheduler())
        let writer = StreamingMessageWriter(
            write: { message, sessionID in
                spy.writes.append(Spy.Write(id: message.id, content: message.content, sessionID: sessionID))
            },
            clock: { clock.now },
            schedule: { _, work in scheduler.work = work }
        )
        let store = MessageStore(streamingWriter: writer)
        store.currentSessionID = "s1"
        store.append(Message(id: "live", role: .assistant, content: "", isStreaming: true))

        for index in 0..<30 {
            store.update(id: "live") { message in
                message.content += "x\(index);"
            }
        }
        #expect(spy.writes.count == 1)

        store.setFinished(id: "live")
        #expect(spy.writes.last?.content == store.messages[0].content)
        #expect(spy.writes.count == 2)
        scheduler.fire()
        #expect(spy.writes.count == 2)
    }
}
