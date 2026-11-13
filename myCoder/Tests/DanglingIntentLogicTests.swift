import Foundation
import Testing
@testable import myCoder

/// Dangling intent: the model announces work in prose but emits no tool call,
/// so the turn would end with nothing executed. The detector must catch real
/// announcements and stay silent for results, questions, negations, offers,
/// past tense and code samples.
@Suite("Dangling intent — announced action without a tool call")
struct DanglingIntentLogicTests {

    // MARK: - Real announcements (live DB evidence)

    @Test func catchesTheExactLiveRussianMessage() {
        let live = """
        Файл уже содержит полный автономный аквариум на чистом WebGL. Он требований «реалистичные и проработанные рыбки, травка, камушки» соответствует лишь частично: рыбки — эллипсоид с примитивными плавниками, травка — плоские полосы, камни — серые. План:

        1. Проверю статическую корректность JS.
        2. Улучшу генерацию рыб: тело с головой/хвостом, глаза, жаберные щели, спинной/грудные/брюшные плавники, плавательный пузырь, двухцветные полосы.
        3. Добавлю колыхание водорослей а анимации (изгиб во времени).
        4. Улучшу камни: реалистичнее грани и цвет.
        5. Проверю ограничение траекторий рыб границами, освещение, качество.
        6. Выдам standalone-файл.

        Проверю счётчики ресурсов в JS.
        """
        #expect(DanglingIntentLogic.announcesAction(live))
    }

    @Test func catchesShortRussianFuture() {
        #expect(DanglingIntentLogic.announcesAction("Проверю счётчики ресурсов в JS."))
        #expect(DanglingIntentLogic.announcesAction("Сейчас проверяю счётчики."))
        #expect(DanglingIntentLogic.announcesAction("Продолжу проверку файла."))
        #expect(DanglingIntentLogic.announcesAction("Запущу тесты и исправлю ошибки."))
    }

    @Test func catchesEnglishFutureAndContinuous() {
        #expect(DanglingIntentLogic.announcesAction("Let me check the resource counters in the JS."))
        #expect(DanglingIntentLogic.announcesAction("I'll run the tests now."))
        #expect(DanglingIntentLogic.announcesAction("I am going to update the shader."))
        #expect(DanglingIntentLogic.announcesAction("I'm checking the counters now."))
        #expect(DanglingIntentLogic.announcesAction("Next, I'll fix the parser."))
    }

    // MARK: - Not announcements

    @Test func ignoresPastTenseResults() {
        #expect(!DanglingIntentLogic.announcesAction("Проверил счётчики ресурсов — всё в порядке."))
        #expect(!DanglingIntentLogic.announcesAction("Запустил тесты, все зелёные."))
        #expect(!DanglingIntentLogic.announcesAction("I checked the counters; everything is fine."))
        #expect(!DanglingIntentLogic.announcesAction("All tests passed."))
        #expect(!DanglingIntentLogic.announcesAction("Готово: 10 тестов зелёные."))
    }

    @Test func ignoresQuestions() {
        #expect(!DanglingIntentLogic.announcesAction("Should I check the counters?"))
        #expect(!DanglingIntentLogic.announcesAction("Проверить счётчики ресурсов?"))
        #expect(!DanglingIntentLogic.announcesAction("Проверю счётчики?"))
        #expect(!DanglingIntentLogic.announcesAction("What should I do next?"))
    }

    @Test func ignoresNegationsAndOffers() {
        #expect(!DanglingIntentLogic.announcesAction("Не буду проверять счётчики."))
        #expect(!DanglingIntentLogic.announcesAction("Я не проверю счётчики."))
        #expect(!DanglingIntentLogic.announcesAction("I won't run the tests."))
        #expect(!DanglingIntentLogic.announcesAction("I will not check the counters."))
        #expect(!DanglingIntentLogic.announcesAction("Могу проверить счётчики, если нужно."))
        #expect(!DanglingIntentLogic.announcesAction("I could check the counters if you want."))
    }

    @Test func ignoresInstructionsAddressedToTheUser() {
        #expect(!DanglingIntentLogic.announcesAction("1. Откройте файл.\n2. Запустите тесты."))
        #expect(!DanglingIntentLogic.announcesAction("Open the file and run the tests."))
    }

    @Test func ignoresSpeechActsAndEmptyText() {
        #expect(!DanglingIntentLogic.announcesAction(""))
        #expect(!DanglingIntentLogic.announcesAction("   \n  "))
        #expect(!DanglingIntentLogic.announcesAction("Now I'll explain the changes."))
        #expect(!DanglingIntentLogic.announcesAction("Объясню изменения в коде."))
        #expect(!DanglingIntentLogic.announcesAction("The answer is 42."))
    }

    @Test func ignoresFutureTenseInsideCodeSamples() {
        let response = """
        Here is the helper:

        ```swift
        // Проверю счётчики ресурсов в JS.
        let check = true
        ```

        It compiles.
        """
        #expect(!DanglingIntentLogic.announcesAction(response))
    }

    @Test func aQuestionAfterAStatementDoesNotTurnTheWholeAnswerIntoAnAnnouncement() {
        #expect(!DanglingIntentLogic.announcesAction("Проверю счётчики?"))
        #expect(DanglingIntentLogic.announcesAction("Проверю счётчики. Что дальше?"))
    }

    // MARK: - Nudge text

    @Test func nudgeIsOneActionableInstruction() {
        let nudge = DanglingIntentLogic.nudgeMessage
        #expect(nudge.contains("tool"))
        #expect(nudge.contains("executed"))
        #expect(nudge.count < 500)
    }
}
