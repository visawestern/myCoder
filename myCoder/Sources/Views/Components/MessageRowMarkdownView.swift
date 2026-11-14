import SwiftUI

/// Модульная логика markdown-пузыря сообщения. Вынесена из
/// `MessageRowView` (была приватной функцией `markdownBubble`), чтобы её
/// можно было править и тестировать отдельно от вью, а саму вью —
/// переносить в другие места без привязки к конкретной строке чата.
enum MessageRowMarkdownLogic {
    /// Фон пузыря markdown-контента по роли сообщения.
    ///
    /// Вход: `isUser` — true для сообщений пользователя.
    /// Выход: цвет фона (brand с прозрачностью — user, surface — остальные).
    /// Зависимости: `Color.mimo.brand`, `Color.mimo.surface`.
    static func bubbleBackground(isUser: Bool) -> Color {
        isUser ? Color.mimo.brand.opacity(0.2) : Color.mimo.surface
    }

    /// Разрешение темы рендера: явный профиль побеждает системную схему.
    ///
    /// Вход: `explicit` — явно заданный профиль (nil = не задан);
    /// `systemIsLight` — текущая светлая/тёмная схема системы.
    /// Выход: true, если рендер должен использовать светлую палитру.
    /// Зависимости: нет (чистая функция).
    static func resolvedIsLight(explicit: Bool?, systemIsLight: Bool) -> Bool {
        explicit ?? systemIsLight
    }

    /// Разбиение текста ответа на сегменты (проза/код/картинки) — ровно
    /// то, что рендерит вью. Используется как fallback, когда готовые
    /// сегменты из кэша недоступны (нет сессии/номера пары).
    ///
    /// Вход: `text` — markdown-текст прозы сообщения.
    /// Выход: упорядоченный массив `MarkdownMediaSegment`.
    /// Зависимости: `MarkdownMediaSegmentLogic.segments`.
    static func segments(from text: String) -> [MarkdownMediaSegment] {
        MarkdownMediaSegmentLogic.segments(from: text)
    }
}

/// Один markdown-пузырь сообщения: проза (selectable), фенс-код
/// (спойлер) и инлайн-картинки. Принимает УЖЕ разобранные сегменты —
/// их готовит `MessageRowView` из `RenderedMessageStore`, поэтому парсинг
/// не повторяется на каждый body-eval.
///
/// Вход: `segments` — сегменты текста; `isUser` — роль для фона;
/// `projectRoot` — корень проекта для путей; `isLightInterface` —
/// явный профиль темы (nil = системный).
/// Выход: пузырь с фоном и скруглением, как в чате.
/// Зависимости: `MessageRowMarkdownLogic`, `SelectableMarkdownTextView`,
/// `CodeBlockSpoilerView`, `MarkdownImageMessageView`.
struct MessageRowMarkdownView: View {
    let segments: [MarkdownMediaSegment]
    var isUser: Bool = false
    var projectRoot: String? = nil
    var isLightInterface: Bool? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var resolvedIsLight: Bool {
        MessageRowMarkdownLogic.resolvedIsLight(
            explicit: isLightInterface,
            systemIsLight: colorScheme == .light
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let prose):
                    SelectableMarkdownTextView(
                        text: prose,
                        fontSize: 14,
                        projectRoot: projectRoot,
                        isLightInterface: resolvedIsLight
                    )
                case .code(let language, let code):
                    CodeBlockSpoilerView(language: language, code: code)
                case .image(let alt, let source):
                    MarkdownImageMessageView(
                        source: source,
                        alt: alt,
                        projectRoot: projectRoot
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MessageRowMarkdownLogic.bubbleBackground(isUser: isUser))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
