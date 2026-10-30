import XCTest
@testable import myCoder

/// Пустой ответ провайдера — кратковременный сбой (модель «зависла» на
/// пустом выводе), а не ошибка конфигурации. Политика ретраев должна
/// разрешать повторные попытки ТОЛЬКО для пустого ответа (транзиент) и
/// только до лимита попыток; остальные ошибки (HTTP, транспорт) не
/// ретраятся. Репорт: «The provider returned an empty response…» —
/// интерпретация была верной, но повторной попытки не было.
final class EmptyResponseRetryPolicyTests: XCTestCase {

    func testEmptyResponsesAreRecognizedAsTransient() {
        XCTAssertTrue(EmptyResponseRetryPolicy.isTransientEmpty(DirectChatError.emptyResponse))
        XCTAssertTrue(EmptyResponseRetryPolicy.isTransientEmpty(OpenCodeServeError.emptyResponse))
        XCTAssertTrue(EmptyResponseRetryPolicy.isTransientEmpty(ACPError.emptyResponse))
        XCTAssertTrue(EmptyResponseRetryPolicy.isTransientEmpty(MimoServeError.emptyResponse))
    }

    func testOtherErrorsAreNotTransient() {
        XCTAssertFalse(EmptyResponseRetryPolicy.isTransientEmpty(DirectChatError.http(status: 500, body: "boom")))
        XCTAssertFalse(EmptyResponseRetryPolicy.isTransientEmpty(DirectChatError.transport("unreachable")))
        XCTAssertFalse(EmptyResponseRetryPolicy.isTransientEmpty(DirectChatError.decode))
    }

    func testShouldRetryUpToMaxAttempts() {
        XCTAssertTrue(EmptyResponseRetryPolicy.shouldRetry(DirectChatError.emptyResponse, attempt: 0))
        XCTAssertTrue(EmptyResponseRetryPolicy.shouldRetry(DirectChatError.emptyResponse, attempt: 1))
        XCTAssertFalse(EmptyResponseRetryPolicy.shouldRetry(DirectChatError.emptyResponse, attempt: 2))
        XCTAssertFalse(EmptyResponseRetryPolicy.shouldRetry(DirectChatError.emptyResponse, attempt: 3))
    }

    func testWithEmptyRetriesSucceedsAfterARetry() async throws {
        var calls = 0
        let result = try await EmptyResponseRetryPolicy.withEmptyRetries {
            calls += 1
            if calls == 1 { throw DirectChatError.emptyResponse }
            return "ok"
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result, "ok")
    }

    func testWithEmptyRetriesGivesUpAfterMaxAttempts() async {
        var calls = 0
        do {
            _ = try await EmptyResponseRetryPolicy.withEmptyRetries {
                calls += 1
                throw DirectChatError.emptyResponse
            }
            XCTFail("expected the error to surface after retries")
        } catch {
            guard case DirectChatError.emptyResponse = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(calls, EmptyResponseRetryPolicy.defaultMaxAttempts)
    }

    func testNonTransientErrorIsNotRetried() async {
        var calls = 0
        do {
            _ = try await EmptyResponseRetryPolicy.withEmptyRetries {
                calls += 1
                throw DirectChatError.http(status: 500, body: "boom")
            }
            XCTFail("expected the error to surface")
        } catch {
            guard case DirectChatError.http(let status, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(status, 500)
        }
        XCTAssertEqual(calls, 1)
    }
}
