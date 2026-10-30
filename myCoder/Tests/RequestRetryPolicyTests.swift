import XCTest
@testable import myCoder

/// Повторные попытки для транзиентных сбоев ЛЮБЫХ провайдеров:
/// пустые ответы + HTTP 408/429/500/502/503/504; до 10 суммарных
/// попыток; экспоненциальная пауза с потолком 60 секунд. Репорт
/// 2026-10-30: «The provider returned an empty response…» — транзиент,
/// повтор нужен; 429/500/503 тоже подразумевают повтор.
final class RequestRetryPolicyTests: XCTestCase {

    func testEmptyResponsesAreRetryableForAllProviders() {
        XCTAssertTrue(RequestRetryPolicy.isRetryable(DirectChatError.emptyResponse))
        XCTAssertTrue(RequestRetryPolicy.isRetryable(OpenCodeServeError.emptyResponse))
        XCTAssertTrue(RequestRetryPolicy.isRetryable(ACPError.emptyResponse))
        XCTAssertTrue(RequestRetryPolicy.isRetryable(MimoServeError.emptyResponse))
    }

    func testRetryableHttpStatusesAreRetryableForAllProviders() {
        for status in [408, 429, 500, 502, 503, 504] {
            XCTAssertTrue(RequestRetryPolicy.isRetryable(DirectChatError.http(status: status, body: "")),
                         "DirectChat 500 should be retryable")
            XCTAssertTrue(RequestRetryPolicy.isRetryable(OpenCodeServeError.http(status: status, body: "")),
                         "OpenCodeServe \(status) should be retryable")
            XCTAssertTrue(RequestRetryPolicy.isRetryable(ACPError.httpError(statusCode: status, message: "")),
                         "ACP \(status) should be retryable")
            XCTAssertTrue(RequestRetryPolicy.isRetryable(MimoServeError.httpError(statusCode: status, message: "")),
                         "MimoServe \(status) should be retryable")
        }
    }

    func testNonRetryableErrorsAreNeverRetried() {
        XCTAssertFalse(RequestRetryPolicy.isRetryable(DirectChatError.http(status: 401, body: "unauthorized")))
        XCTAssertFalse(RequestRetryPolicy.isRetryable(DirectChatError.http(status: 404, body: "not found")))
        XCTAssertFalse(RequestRetryPolicy.isRetryable(OpenCodeServeError.http(status: 403, body: "")))
        XCTAssertFalse(RequestRetryPolicy.isRetryable(DirectChatError.transport("unreachable")))
        XCTAssertFalse(RequestRetryPolicy.isRetryable(DirectChatError.decode))
    }

    func testShouldRetryUpToTenAttempts() {
        for attempt in 0..<9 {
            XCTAssertTrue(RequestRetryPolicy.shouldRetry(DirectChatError.emptyResponse, attempt: attempt),
                         "attempt \(attempt) should be retryable within 10 total")
        }
        XCTAssertFalse(RequestRetryPolicy.shouldRetry(DirectChatError.emptyResponse, attempt: 9))
    }

    func testDelayGrowsExponentiallyAndIsCappedAtOneMinute() {
        XCTAssertEqual(RequestRetryPolicy.delayBeforeRetry(attempt: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(RequestRetryPolicy.delayBeforeRetry(attempt: 1), 1.0, accuracy: 0.001)
        XCTAssertEqual(RequestRetryPolicy.delayBeforeRetry(attempt: 2), 2.0, accuracy: 0.001)
        XCTAssertEqual(RequestRetryPolicy.delayBeforeRetry(attempt: 3), 4.0, accuracy: 0.001)
        XCTAssertEqual(RequestRetryPolicy.delayBeforeRetry(attempt: 7), 60.0, accuracy: 0.001)
        XCTAssertEqual(RequestRetryPolicy.delayBeforeRetry(attempt: 10), 60.0, accuracy: 0.001)
    }

    func testWithRetriesSucceedsAfterARetry() async throws {
        var calls = 0
        let result = try await RequestRetryPolicy.withRetries(attempts: 3) {
            calls += 1
            if calls == 1 { throw DirectChatError.emptyResponse }
            return "ok"
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result, "ok")
    }

    func testWithRetriesGivesUpAfterMaxAttempts() async {
        var calls = 0
        do {
            _ = try await RequestRetryPolicy.withRetries(attempts: 3) {
                calls += 1
                throw DirectChatError.emptyResponse
            }
            XCTFail("expected the error to surface after retries")
        } catch {
            guard case DirectChatError.emptyResponse = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(calls, 3)
    }

    func testHttp429IsRetriedThenSucceeds() async throws {
        var calls = 0
        let result = try await RequestRetryPolicy.withRetries(attempts: 3) {
            calls += 1
            if calls == 1 { throw DirectChatError.http(status: 429, body: "rate limited") }
            return "ok"
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result, "ok")
    }

    func testNonTransientErrorIsNotRetried() async {
        var calls = 0
        do {
            _ = try await RequestRetryPolicy.withRetries(attempts: 5) {
                calls += 1
                throw DirectChatError.http(status: 404, body: "not found")
            }
            XCTFail("expected the error to surface")
        } catch {
            guard case DirectChatError.http(let status, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(status, 404)
        }
        XCTAssertEqual(calls, 1)
    }
}
