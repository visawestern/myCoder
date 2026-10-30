import Foundation

/// Политика повторных попыток для ТРАНЗИЕНТНЫХ сбоев провайдеров.
///
/// Репорт 2026-10-30: «The provider returned an empty response…» — это
/// кратковременный сбой, а не ошибка конфигурации; повторные попытки
/// нужны. Политика общая для ВСЕХ провайдеров (direct OpenAI-совместимый,
/// ACP, OpenCode Serve, Mimo Serve) и покрывает:
/// - пустые ответы (emptyResponse) всех провайдеров;
/// - HTTP-статусы, которые подразумевают повтор: 408, 429, 500, 502,
///   503, 504.
///
/// Лимит: до 10 суммарных попыток; пауза растёт экспоненциально
/// (0.5с → 1с → 2с …) и обрезается на 60 секундах. Ошибки вне этого
/// класса (401/403/404, транспорт, parse) НЕ ретраятся — повтор их скроет.
enum RequestRetryPolicy {

    /// Суммарное число попыток (включая первую).
    static let defaultMaxAttempts = 10
    /// Верхний предел паузы между попытками.
    static let maxDelaySeconds: TimeInterval = 60
    /// HTTP-статусы, которые подразумевают повтор.
    static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]

    /// Является ли ошибка транзиентной (стоит ли её повторять).
    static func isRetryable(_ error: Error) -> Bool {
        if case DirectChatError.emptyResponse = error { return true }
        if case DirectChatError.http(let status, _) = error, retryableStatuses.contains(status) { return true }
        if case OpenCodeServeError.emptyResponse = error { return true }
        if case OpenCodeServeError.http(let status, _) = error, retryableStatuses.contains(status) { return true }
        if case ACPError.emptyResponse = error { return true }
        if case ACPError.httpError(let status, _) = error, retryableStatuses.contains(status) { return true }
        if case MimoServeError.emptyResponse = error { return true }
        if case MimoServeError.httpError(let status, _) = error, retryableStatuses.contains(status) { return true }
        return false
    }

    /// `attempt` — число УЖЕ выполненных попыток (0..). Повтор возможен,
    /// пока суммарно не исчерпаны `maxAttempts`.
    static func shouldRetry(_ error: Error,
                            attempt: Int,
                            maxAttempts: Int = defaultMaxAttempts) -> Bool {
        attempt + 1 < maxAttempts && isRetryable(error)
    }

    /// Экспоненциальная пауза, ограниченная 60 секундами.
    static func delayBeforeRetry(attempt: Int) -> TimeInterval {
        min(0.5 * pow(2.0, Double(max(0, attempt))), maxDelaySeconds)
    }

    /// Выполняет `operation`, ретрая только транзиентные сбои.
    /// `attempts` — суммарное число попыток (включая первую).
    static func withRetries<T>(attempts: Int = defaultMaxAttempts,
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
        // Недостижимо: цикл выходит только через return или итоговый throw.
        throw DirectChatError.transport("retries exhausted")
    }
}
