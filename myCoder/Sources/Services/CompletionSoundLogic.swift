import AppKit
import Foundation

/// Контекст окончания хода для решения о звуке.
struct CompletionTurnContext: Equatable {
    /// Ход реально завершился ответом (не в процессе перегенерации).
    var completed: Bool
    /// Есть активная цель — работа продолжается, звук не нужен.
    var activeGoalRunning: Bool
    /// Ход закончился ошибкой.
    var endedWithError: Bool
    /// Ход остановлен пользователем.
    var stoppedByUser: Bool
    /// Модель ждёт ответа пользователя (вопрос/разрешение).
    var awaitingUserInput: Bool
}

enum CompletionSoundDecision: Equatable {
    case play
    case skip
}

/// Чистое решение: звук завершения играет только когда чат закончил работу
/// и нет активной цели / ошибки / остановки / ожидания пользователя
/// (запрос 2026-11-13).
enum CompletionSoundLogic {

    static func decide(_ context: CompletionTurnContext) -> CompletionSoundDecision {
        if !context.completed || context.awaitingUserInput || context.endedWithError
            || context.stoppedByUser || context.activeGoalRunning {
            return .skip
        }
        return .play
    }

    /// Есть ли активная (работающая) цель — чистое чтение хранилища.
    static func hasActiveGoal(homeDirectory: URL) -> Bool {
        GoalStore.load(homeDirectory: homeDirectory).contains { $0.state == .active }
    }
}

/// Проигрыватель звука завершения. `playIfNeeded` идемпотентен в пределах
/// `minInterval`: одно завершение хода может прийти из нескольких точек
/// (стриминг + статусное событие), но звук должен прозвучать один раз.
final class CompletionSoundPlayer {
    static let shared = CompletionSoundPlayer()

    private let lock = NSLock()
    private var lastPlayedAt: Date?
    /// Минимальный интервал между звуками, чтобы дубли одного хода не
    /// проигрывались дважды.
    private let minInterval: TimeInterval = 2

    func playIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let last = lastPlayedAt, now.timeIntervalSince(last) < minInterval {
            return
        }
        lastPlayedAt = now
        NSSound(named: "Glass")?.play()
    }

    /// Сброс дедупликации (для тестов и перезапуска сессии).
    func reset() {
        lock.lock()
        lastPlayedAt = nil
        lock.unlock()
    }
}
