import Foundation

/// Когда стриминговое обновление сообщения должно уйти в БД.
///
/// Раньше `MessageStore.update` вызывал `DatabaseBridge.saveMessage` на каждый
/// чанк ответа. Один такой вызов — это INSERT сообщения, DELETE всех его parts,
/// повторная вставка parts, обновление FTS и две строки в лог, синхронно на
/// главном потоке. При десятках чанков в секунду это и есть «прыгающий чат»:
/// вьюшка перестраивается, пока главный поток занят SQLite.
///
/// Промежуточные состояния теперь живут только в памяти; в БД уходит не более
/// одной записи за `interval`, плюс обязательный сброс финального состояния.
enum StreamingWritePolicy {
    /// Минимальный интервал между записями одного стримингового сообщения.
    static let interval: TimeInterval = 0.35

    static func shouldWriteNow(isStreaming: Bool,
                               isFinished: Bool,
                               now: TimeInterval,
                               lastWrite: TimeInterval?) -> Bool {
        // Финал и любые не-стриминговые правки должны быть в БД сразу.
        if !isStreaming || isFinished { return true }
        guard let lastWrite else { return true }
        return now - lastWrite >= interval
    }
}

/// Коалесцирует записи стриминговых сообщений: хранит последний снимок по id,
/// пишет по переднему фронту, а для «хвоста» (если чанки внезапно кончились)
/// планирует один отложенный сброс. Вся работа происходит на главном потоке.
final class StreamingMessageWriter {

    private struct Snapshot {
        let message: Message
        let sessionID: String
    }

    private let write: (Message, String) -> Void
    private let clock: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var pending: [String: Snapshot] = [:]
    private var lastWrite: [String: TimeInterval] = [:]
    private var timerScheduled = false

    init(write: @escaping (Message, String) -> Void,
         clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.write = write
        self.clock = clock
        self.schedule = schedule
    }

    /// Зарегистрировать новое состояние сообщения.
    func note(_ message: Message, sessionID: String) {
        guard !sessionID.isEmpty else { return }
        let now = clock()
        let immediate = StreamingWritePolicy.shouldWriteNow(
            isStreaming: message.isStreaming,
            isFinished: message.isFinished,
            now: now,
            lastWrite: lastWrite[message.id]
        )
        // Сначала всегда обновляем снимок, чтобы сброс унёс самый свежий текст.
        pending[message.id] = Snapshot(message: message, sessionID: sessionID)
        if immediate {
            flush(at: now)
        } else {
            scheduleTrailingFlush()
        }
    }

    /// Сообщение удалено/заменено — отложенная запись больше не нужна.
    func cancel(id: String) {
        pending.removeValue(forKey: id)
        lastWrite.removeValue(forKey: id)
    }

    /// Принудительно сбросить всё перед переключением чата, загрузкой истории
    /// или выходом из приложения.
    func flushAll() {
        flush(at: clock())
    }

    private func flush(at now: TimeInterval) {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        timerScheduled = false
        for (id, snapshot) in batch {
            write(snapshot.message, snapshot.sessionID)
            lastWrite[id] = now
        }
    }

    private func scheduleTrailingFlush() {
        guard !timerScheduled else { return }
        timerScheduled = true
        schedule(StreamingWritePolicy.interval) { [weak self] in
            self?.flushAll()
        }
    }
}
