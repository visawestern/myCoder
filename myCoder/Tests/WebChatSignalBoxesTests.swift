import Testing
import Foundation
@testable import myCoder

/// Сигналы веб-чата и стабильностные боксы: retry/approval/completion
/// сигналы (первый записывается, take() сбрасывает), подтверждения
/// лимита и счётчик рестартов.
@MainActor
@Suite("Сигналы и боксы веб-чата")
struct WebChatSignalBoxesTests {

    @Test("WebChatRetrySignal: первый повод запоминается, take() сбрасывает")
    func retrySignalRecordsFirstAndTakes() {
        let signal = WebChatRetrySignal()
        #expect(signal.take() == nil)
        signal.record("пустой ответ")
        signal.record("другая причина")
        #expect(signal.take() == "пустой ответ")
        #expect(signal.take() == nil, "после take сигнал сброшен")
    }

    @Test("WebChatApprovalSignal: как retry, только для одобрений")
    func approvalSignalRecordsFirstAndTakes() {
        let signal = WebChatApprovalSignal()
        signal.record("нужно одобрение")
        signal.record("второе")
        #expect(signal.take() == "нужно одобрение")
        #expect(signal.take() == nil)
    }

    @Test("WebChatCompletionSignal: завершение записывается только для финального ответа/ошибки")
    func completionSignalRecordsOnlyFinalOrError() {
        let signal = WebChatCompletionSignal()
        signal.recordIfCompleted(.streaming("промежуточное"))
        #expect(!signal.take(), "streaming не завершение")

        signal.recordIfCompleted(.final("ответ"))
        #expect(signal.take())
        #expect(!signal.take(), "сброс после take")

        signal.recordIfCompleted(.error("ошибка"))
        #expect(signal.take(), "ошибка честно завершает ход")
    }

    @Test("WebSendCompletionLogic: пустой финальный текст не завершение")
    func completionLogicRequiresVisibleFinalText() {
        #expect(WebSendCompletionLogic.recordsCompletion(for: .final("ok")))
        #expect(!WebSendCompletionLogic.recordsCompletion(for: .final("   ")))
        #expect(WebSendCompletionLogic.recordsCompletion(for: .error("boom")))
        #expect(!WebSendCompletionLogic.recordsCompletion(for: .streaming("...")))
    }

    @Test("LimitStabilityBox: последовательные подтверждения накапливаются")
    func limitStabilityAccumulates() {
        let box = LimitStabilityBox()
        #expect(box.consecutive == 0)
        box.consecutive += 1
        box.consecutive += 1
        #expect(box.consecutive == 2)
        #expect(LimitStabilityBox.requiredConfirmations == 3)
    }

    @Test("RestartCountBox: счётчик растёт")
    func restartCountBoxIncrements() {
        let box = RestartCountBox()
        box.count += 1
        box.count += 1
        #expect(box.count == 2)
    }
}
