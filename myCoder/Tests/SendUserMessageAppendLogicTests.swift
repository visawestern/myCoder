import Testing
import Foundation
@testable import myCoder

/// Force-send shows the user bubble before waiting for the interrupted turn.
/// The send path must then fill that bubble in instead of appending a second
/// copy (the DB had duplicate user messages on forced turns).
@Suite("Вставка user-сообщения при отправке")
struct SendUserMessageAppendLogicTests {

    @Test("Обычная отправка добавляет сообщение")
    func freshSendAppends() {
        #expect(SendUserMessageAppendLogic.action(hasRetryPlan: false, existingUserMessageID: nil) == .appendNew)
    }

    @Test("Принудительная отправка обновляет уже показанный пузырь")
    func forceSendUpdatesExistingBubble() {
        #expect(SendUserMessageAppendLogic.action(hasRetryPlan: false, existingUserMessageID: "m1") == .updateExisting)
    }

    @Test("Ретрай не дублирует сохранённый ход")
    func retrySkipsAppend() {
        #expect(SendUserMessageAppendLogic.action(hasRetryPlan: true, existingUserMessageID: nil) == .skip)
    }

    @MainActor
    @Test("Пузырь показывается до ожидания прерванного хода")
    func bubbleIsShownBeforeWaiting() async {
        var steps: [String] = []
        let bubbleID = await ForcedSendOrderingLogic.run(
            showUserMessage: {
                steps.append("show")
                return "bubble-1"
            },
            waitForPreviousTurn: { steps.append("wait") },
            send: { id in steps.append("send:\(id ?? "nil")") }
        )
        #expect(steps == ["show", "wait", "send:bubble-1"])
        #expect(bubbleID == "bubble-1")
    }
}
