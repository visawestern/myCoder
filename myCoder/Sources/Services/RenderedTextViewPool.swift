import AppKit

/// Пул готовых `PathClickTextView` с уже выполненной TextKit-раскладкой.
/// Когда LazyVStack пересоздаёт строку, `SelectableMarkdownTextView` берёт
/// view из пула вместо создания нового `NSTextView` и повторной раскладки
/// глифов — это ключевая часть «отрендеренного сообщения» из плана.
///
/// Пул живёт только в памяти программы и очищается при выходе. Ключ —
/// полный профиль рендера (`MarkdownAttributedStringBuilder.RenderKey`):
/// текст, шрифт, цвета, настройки кода, projectRoot. View с другим
/// профилем не переиспользуются.
///
/// Лимит памяти: `maxCachedViews` view суммарно (как у кэша пар). При
/// превышении вытесняется самый старый view — так пул не может расти
/// бесконечно, даже если чатов/строк в сессии очень много.
///
/// Защита от повторного родительства: в пул принимаются и из пула
/// выдаются только view с `superview == nil && window == nil`. Занятые
/// view отбрасываются (счётчик `discards`), чтобы одна вью не оказалась
/// в двух местах иерархии.
@MainActor
final class RenderedTextViewPool {
    static let shared = RenderedTextViewPool()

    /// Верхняя граница числа view в пуле (FIFO-вытеснение).
    static let maxCachedViews = 512

    private var available: [MarkdownAttributedStringBuilder.RenderKey: [PathClickTextView]] = [:]
    /// Порядок ключей по первой вставке (старый → новый) для эвикции.
    private var keyOrder: [MarkdownAttributedStringBuilder.RenderKey] = []
    private var totalCached = 0

    /// Сколько view выдано из пула (повторных использований).
    private(set) var dequeues = 0
    /// Сколько view возвращено в пул.
    private(set) var returns = 0
    /// Сколько view отбраковано (ещё в иерархии или вне пула).
    private(set) var discards = 0

    /// Достать готовый view по профилю рендера. Возвращает nil, если
    /// подходящего свободного view нет (тогда вызывающий создаёт новый).
    ///
    /// Вход: `key` — профиль рендера.
    /// Выход: `PathClickTextView` или nil.
    /// Зависимости: `MarkdownAttributedStringBuilder.RenderKey`.
    func dequeue(key: MarkdownAttributedStringBuilder.RenderKey) -> PathClickTextView? {
        guard var views = available[key], !views.isEmpty else { return nil }
        while let candidate = views.popLast() {
            guard candidate.superview == nil, candidate.window == nil else {
                // View ещё в иерархии — не выдаём (защита от повторного
                // родительства) и не держим в пуле.
                discards += 1
                continue
            }
            available[key] = views
            totalCached -= 1
            dequeues += 1
            return candidate
        }
        available[key] = []
        return nil
    }

    /// Вернуть view в пул после отцепления от иерархии.
    ///
    /// Вход: `view`; `key` — профиль рендера.
    /// Выход: нет (view либо сохранён, либо отбракован).
    /// Зависимости: нет.
    func enqueue(_ view: PathClickTextView, key: MarkdownAttributedStringBuilder.RenderKey) {
        guard view.superview == nil, view.window == nil else {
            discards += 1
            return
        }
        if totalCached >= Self.maxCachedViews {
            evictOne()
        }
        if available[key] == nil {
            keyOrder.append(key)
        }
        available[key, default: []].append(view)
        totalCached += 1
        returns += 1
    }

    /// Полностью очистить пул (тесты/выход).
    func reset() {
        available = [:]
        keyOrder = []
        totalCached = 0
        dequeues = 0
        returns = 0
        discards = 0
    }

    // MARK: - Private

    /// Вытеснить один самый старый view (FIFO по добавлению).
    ///
    /// Убирает последний view первого непустого ключа в `keyOrder`;
    /// если ключ опустел — удаляет его из порядка. Вызывается только при
    /// переполнении пула.
    private func evictOne() {
        while let firstKey = keyOrder.first {
            if var views = available[firstKey], !views.isEmpty {
                views.removeLast()
                available[firstKey] = views
                totalCached -= 1
                if views.isEmpty {
                    available.removeValue(forKey: firstKey)
                    keyOrder.removeFirst()
                }
                return
            }
            available.removeValue(forKey: firstKey)
            keyOrder.removeFirst()
        }
    }
}
