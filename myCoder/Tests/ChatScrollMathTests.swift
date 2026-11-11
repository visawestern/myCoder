import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("ChatScrollMath — чистая математика прокрутки")
struct ChatScrollMathTests {

    @Test("maxOffset не бывает отрицательным")
    func maxOffsetNeverNegative() {
        #expect(ChatScrollMath.maxOffset(contentHeight: 100, viewportHeight: 200) == 0)
        #expect(ChatScrollMath.maxOffset(contentHeight: 200, viewportHeight: 200) == 0)
        #expect(ChatScrollMath.maxOffset(contentHeight: 300, viewportHeight: 200) == 100)
    }

    @Test("Следящая прокрутка держит последний текст в центре, если это возможно")
    func followedOffsetCentersLatestContent() {
        // Низ текста на 900, вьюпорт 600: центрируем конец, а не уходим
        // к старому нижнему краю всего документа на 1400.
        #expect(ChatScrollMath.followedOffset(
            latestContentBottom: 900,
            viewportHeight: 600,
            maxOffset: 1400
        ) == 600)
        // При непрерывном стриминге низ текста остаётся в центре; свободное
        // место ниже появляется из отдельного управляемого spacer-а.
        #expect(ChatScrollMath.followedOffset(
            latestContentBottom: 1800,
            viewportHeight: 600,
            maxOffset: 2000
        ) == 1500)
        // Пустое место после замены текста тулзой не должно оставаться внизу.
        #expect(ChatScrollMath.followedOffset(
            latestContentBottom: 500,
            viewportHeight: 600,
            maxOffset: 1400
        ) == 200)
        #expect(ChatScrollMath.followedOffset(
            latestContentBottom: 500,
            viewportHeight: 600,
            maxOffset: 0
        ) == 0)
    }

    @Test("Уменьшение высоты — повод пересчитать следящий offset")
    func contentShrinkRequiresReanchor() {
        #expect(ChatScrollMath.shouldReanchorFollowedContent(
            wasPinned: true, oldMaxOffset: 1400, newMaxOffset: 700
        ))
        #expect(ChatScrollMath.shouldReanchorFollowedContent(
            wasPinned: true, oldMaxOffset: 700, newMaxOffset: 1400
        ))
        #expect(!ChatScrollMath.shouldReanchorFollowedContent(
            wasPinned: false, oldMaxOffset: 1400, newMaxOffset: 700
        ))
        #expect(!ChatScrollMath.shouldReanchorFollowedContent(
            wasPinned: true, oldMaxOffset: 700, newMaxOffset: 700.5
        ))
    }

    @Test("targetOffset зажимается в диапазон 0…maxOffset")
    func targetOffsetClamps() {
        // Вниз от верха.
        #expect(ChatScrollMath.targetOffset(current: 0, delta: 50, maxOffset: 200) == 50)
        // Вверх от низа — не уходит за 0.
        #expect(ChatScrollMath.targetOffset(current: 50, delta: -500, maxOffset: 200) == 0)
        // Вниз за предел — зажимается к maxOffset.
        #expect(ChatScrollMath.targetOffset(current: 180, delta: 500, maxOffset: 200) == 200)
        // maxOffset = 0 — всегда 0.
        #expect(ChatScrollMath.targetOffset(current: 10, delta: -10, maxOffset: 0) == 0)
        #expect(ChatScrollMath.targetOffset(current: 10, delta: 10, maxOffset: 0) == 0)
    }

    @Test("isAtBottom / isAtTop с допуском")
    func edgeFlags() {
        #expect(ChatScrollMath.isAtBottom(offset: 199, maxOffset: 200))
        #expect(!ChatScrollMath.isAtBottom(offset: 180, maxOffset: 200))
        #expect(ChatScrollMath.isAtTop(offset: 0))
        #expect(ChatScrollMath.isAtTop(offset: 0.5))
        #expect(!ChatScrollMath.isAtTop(offset: 5))
    }
}
