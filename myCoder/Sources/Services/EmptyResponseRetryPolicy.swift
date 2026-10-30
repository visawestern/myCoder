import Foundation

/// Политика повторных попыток для ПУСТОГО ответа провайдера.
///
/// «The provider returned an empty response» — это транзиентный сбой
/// (модель вернула ноль токенов), а не ошибка конфигурации: ретрай
/// оправдан и нужен (репорт 2026-10-30). Прочие ошибки (HTTP, транспорт,
/// parse) НЕ ретраятся — они означают реальную проблему, и повторная
/// попытка скроет её.
enum EmptyResponseRetryPolicy {

    /// Сколько всего попыток (1 исходная + 2 ретрая) до показа ошибки.
    static let defaultMaxAttempts = 3

    /// Пустой ли это ответ (единственный класс ошибок, который ретраится).
    static func isTransientEmpty(_ error: Error) -> Bool {
        if case DirectChatError.emptyResponse = error { return true }
        if case OpenCodeServeError.emptyResponse = error { return true }
        if case ACPError.emptyResponse = error { return true }
        if case MimoServeError.emptyResponse = error { return true }
        return false
    }

    /// `attempt` — число УЖЕ выполненных попыток (0..). Возвращает true,
    /// если можно попробовать ещё раз (до суммарного `maxAttempts`).
    static func shouldRetry(_ error: Error, attempt: Int, maxAttempts: Int = defaultMaxAttempts) -> Bool {
        attempt + 1 < maxAttempts && isTransientEmpty(error)
    }

    /// Пауза перед повтором растёт, но остаётся короткой (0.5с, 1с, …).
    static func delayBeforeRetry(attempt: Int) -> TimeInterval {
        0.5 * TimeInterval(attempt + 1)
    }

    /// Выполняет `operation`, ретрая ТОЛЬКО пустые ответы. `attempts` —
    /// СУММАРНОЕ число попыток (включая первую). Любая другая ошибка
    /// пробрасывается сразу.
    static func withEmptyRetries<T>(attempts: Int = defaultMaxAttempts,
                                    operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while attempt < attempts {
            do {
                return try await operation()
            } catch {
                guard shouldRetry(error, attempt: attempt, maxAttempts: attempts) else {
                    throw error
                }
                attempt += 1
                let delay = delayBeforeRetry(attempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        // Unreachable: the loop exits only via return or the final throw.
        throw DirectChatError.emptyResponse
    }
}
