import SwiftUI
import Testing
@testable import myCoder

/// TDD для визуального контракта карточки подтверждения: деструктивная
/// команда обязана выглядеть КРАСНОЙ (красный треугольник с восклицательным
/// знаком, красная рамка, красная кнопка «Всё равно выполнить») даже при
/// полном доступе. Обычный ограниченный тул остаётся янтарным.
@MainActor
@Suite("Approval card presentation — red for destructive commands")
struct ApprovalCardPresentationTests {

    @Test("Деструктивная карточка красная с восклицательным знаком")
    func destructiveCardIsRed() {
        let presentation = ApprovalCardPresentation(isDestructive: true)
        #expect(presentation.iconName == "exclamationmark.triangle.fill")
        #expect(presentation.accentColor == Color.mimo.danger)
        #expect(presentation.borderColor == Color.mimo.danger)
        #expect(presentation.allowBackgroundColor == Color.mimo.danger)
        #expect(presentation.titleKey == "locDestructiveCommandTitle")
        #expect(presentation.warningKey == "locDestructiveCommandWarning")
        #expect(presentation.allowTitleKey == "locDestructiveRunAnyway")
        #expect(presentation.borderWidth > 1)
    }

    @Test("Обычная карточка остаётся янтарной")
    func ordinaryCardStaysAmber() {
        let presentation = ApprovalCardPresentation(isDestructive: false)
        #expect(presentation.iconName == "exclamationmark.shield")
        #expect(presentation.accentColor == Color.mimo.warning)
        #expect(presentation.allowBackgroundColor == Color.mimo.success)
        #expect(presentation.titleKey == "myCoder wants to run a restricted tool")
        #expect(presentation.warningKey == nil)
        #expect(presentation.allowTitleKey == "Allow")
        #expect(presentation.borderWidth == 1)
    }

    @Test("Красный цвет опасности действительно красный")
    func dangerColorIsRed() {
        let components = Color.mimo.danger.cgColor?.components ?? []
        #expect(components.count >= 3)
        if components.count >= 3 {
            #expect(components[0] > components[1], "красный канал должен доминировать")
            #expect(components[0] > components[2], "красный канал должен доминировать")
            #expect(components[0] > 0.7)
        }
    }
}
