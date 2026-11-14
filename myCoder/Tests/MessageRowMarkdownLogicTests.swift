import Foundation
import Testing
import SwiftUI
@testable import myCoder

/// Модульная логика markdown-пузыря сообщения (`MessageRowMarkdownView`).
/// Покрывает решения, которые раньше были зашиты в `MessageRowView`:
/// выбор фона по роли и разрешение явной/системной темы рендера.
/// Числа для сравнения цветов берутся из токенов `MiMoColors`.
@Suite("Логика markdown-пузыря (MessageRowMarkdownLogic)")
struct MessageRowMarkdownLogicTests {

    // MARK: - Фон пузыря по роли

    @Test("Пользовательский пузырь использует brand-фон с прозрачностью")
    func userBubbleBackground() {
        let background = MessageRowMarkdownLogic.bubbleBackground(isUser: true)
        #expect(background == Color.mimo.brand.opacity(0.2))
    }

    @Test("Пузырь ассистента использует surface-фон")
    func assistantBubbleBackground() {
        let background = MessageRowMarkdownLogic.bubbleBackground(isUser: false)
        #expect(background == Color.mimo.surface)
    }

    // MARK: - Разрешение темы рендера

    @Test("Явный профиль темы побеждает системную схему")
    func explicitLightWinsOverSystem() {
        #expect(MessageRowMarkdownLogic.resolvedIsLight(
            explicit: true,
            systemIsLight: false
        ))
        #expect(!MessageRowMarkdownLogic.resolvedIsLight(
            explicit: false,
            systemIsLight: true
        ))
    }

    @Test("Без явного профиля используется системная схема")
    func systemSchemeFallback() {
        #expect(MessageRowMarkdownLogic.resolvedIsLight(
            explicit: nil,
            systemIsLight: true
        ))
        #expect(!MessageRowMarkdownLogic.resolvedIsLight(
            explicit: nil,
            systemIsLight: false
        ))
    }

    // MARK: - Разбиение сегментов вью (регрессионный щит)

    @Test("Сегменты вью совпадают с MarkdownMediaSegmentLogic")
    func segmentsMatchMediaLogic() {
        let text = "до ![x](i.png) после\n```swift\nlet a = 1\n```"
        #expect(MessageRowMarkdownLogic.segments(from: text)
            == MarkdownMediaSegmentLogic.segments(from: text))
    }

    @Test("Пустой текст не даёт сегментов вью")
    func emptyTextYieldsNoSegments() {
        #expect(MessageRowMarkdownLogic.segments(from: "").isEmpty)
    }

    @Test("Порядок сегментов сохраняется: проза-код-проза")
    func segmentOrderPreserved() {
        let segments = MessageRowMarkdownLogic.segments(
            from: "перед\n```txt\nтело\n```\nпосле"
        )
        #expect(segments.count == 3)
        guard case .prose = segments[0],
              case .code = segments[1],
              case .prose = segments[2] else {
            Issue.record("ожидался порядок проза → код → проза")
            return
        }
    }
}
