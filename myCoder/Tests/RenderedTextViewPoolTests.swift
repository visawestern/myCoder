import AppKit
import SwiftUI
import Testing
@testable import myCoder

/// Пул готовых `PathClickTextView` с сохранённой TextKit-раскладкой:
/// при пересоздании строки view берётся из пула, а не создаётся заново.
/// Защита от повторного родительства: в пул/из пула не попадают view,
/// у которых есть superview/window.
@MainActor
@Suite("RenderedTextViewPool: пул текстовых view", .serialized)
struct RenderedTextViewPoolTests {

    init() {
        RenderedTextViewPool.shared.reset()
    }

    private func key(text: String = "hello") -> MarkdownAttributedStringBuilder.RenderKey {
        MarkdownAttributedStringBuilder.key(
            text: text,
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: .default,
            isLightInterface: true
        )
    }

    @Test("Пустой пул возвращает nil")
    func emptyPoolReturnsNil() {
        #expect(RenderedTextViewPool.shared.dequeue(key: key()) == nil)
    }

    @Test("Возвращённый view отдаётся снова (тот же экземпляр)")
    func enqueueThenDequeueReturnsSameView() {
        let view = PathClickTextView()
        let k = key()
        RenderedTextViewPool.shared.enqueue(view, key: k)
        let out = RenderedTextViewPool.shared.dequeue(key: k)
        #expect(out === view)
        #expect(RenderedTextViewPool.shared.returns == 1)
        #expect(RenderedTextViewPool.shared.dequeues == 1)
        #expect(RenderedTextViewPool.shared.discards == 0)
    }

    @Test("View с родителем не возвращается в пул и не выдаётся")
    func managedViewsAreSkipped() {
        let view = PathClickTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let container = NSView(frame: view.frame)
        container.addSubview(view)
        #expect(view.superview === container)

        let k = key()
        RenderedTextViewPool.shared.enqueue(view, key: k)
        #expect(RenderedTextViewPool.shared.discards >= 1)
        #expect(RenderedTextViewPool.shared.dequeue(key: k) == nil)
    }

    @Test("Ключи (профили рендера) независимы")
    func keysAreIndependent() {
        let k1 = key(text: "one")
        let k2 = key(text: "two")
        let view = PathClickTextView()
        RenderedTextViewPool.shared.enqueue(view, key: k1)
        #expect(RenderedTextViewPool.shared.dequeue(key: k2) == nil)
        #expect(RenderedTextViewPool.shared.dequeue(key: k1) === view)
    }

    @Test("Повторные возвраты накапливают несколько view одного ключа")
    func multipleReturnsStackUp() {
        let k = key()
        let v1 = PathClickTextView()
        let v2 = PathClickTextView()
        RenderedTextViewPool.shared.enqueue(v1, key: k)
        RenderedTextViewPool.shared.enqueue(v2, key: k)
        guard let first = RenderedTextViewPool.shared.dequeue(key: k),
              let second = RenderedTextViewPool.shared.dequeue(key: k) else {
            Issue.record("ожидались два view из пула")
            return
        }
        #expect(Set([ObjectIdentifier(first), ObjectIdentifier(second)])
            == Set([ObjectIdentifier(v1), ObjectIdentifier(v2)]))
        #expect(RenderedTextViewPool.shared.dequeue(key: k) == nil)
    }

    @Test("reset очищает пул и счётчики")
    func resetClearsEverything() {
        let k = key()
        RenderedTextViewPool.shared.enqueue(PathClickTextView(), key: k)
        RenderedTextViewPool.shared.reset()
        #expect(RenderedTextViewPool.shared.dequeue(key: k) == nil)
        #expect(RenderedTextViewPool.shared.returns == 0)
        #expect(RenderedTextViewPool.shared.dequeues == 0)
        #expect(RenderedTextViewPool.shared.discards == 0)
    }

    @Test("Лимит пула: сверх maxCachedViews вытесняется самый старый view")
    func evictionCapsPoolSize() {
        let limit = RenderedTextViewPool.maxCachedViews
        // Заполняем пул до лимита разными ключами.
        var firstView: PathClickTextView?
        for i in 0..<limit {
            let view = PathClickTextView()
            if i == 0 { firstView = view }
            RenderedTextViewPool.shared.enqueue(view, key: key(text: "k\(i)"))
        }
        // Ещё один возврат — должен вытеснить самый старый view.
        let extra = PathClickTextView()
        RenderedTextViewPool.shared.enqueue(extra, key: key(text: "extra"))

        // Самый старый ключ ("k0") больше не отдаёт свой view.
        #expect(RenderedTextViewPool.shared.dequeue(key: key(text: "k0")) == nil)
        // Новый view в пуле.
        #expect(RenderedTextViewPool.shared.dequeue(key: key(text: "extra")) === extra)
        // Оставшиеся ключи (кроме k0) живы.
        #expect(RenderedTextViewPool.shared.dequeue(key: key(text: "k1")) != nil)
    }
}
