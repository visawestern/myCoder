import Foundation

/// Один визуальный кусок ответа после выделения медиа: проза (selectable),
/// фенс-код (свой спойлер) или инлайн-картинка (свой вью с действиями).
enum MarkdownMediaSegment: Equatable {
    case prose(String)
    case code(language: String, code: String)
    case image(alt: String, source: String)
}

/// Разбивает markdown на прозу, блоки кода и инлайн-картинки в порядке
/// документа. Переиспользует существующее разбиение фенсов
/// (`MarkdownCodeSegmentLogic`) и затем вырезает `![alt](src)` из прозы —
/// чтобы markdown-синтаксис картинки не печатался текстом, а показывался
/// как изображение (запрос 2026-11-13).
enum MarkdownMediaSegmentLogic {

    static func segments(from text: String) -> [MarkdownMediaSegment] {
        var result: [MarkdownMediaSegment] = []
        for segment in MarkdownCodeSegmentLogic.segments(from: text) {
            switch segment {
            case .code(let language, let code):
                result.append(.code(language: language, code: code))
            case .prose(let prose):
                result.append(contentsOf: splitImages(in: prose))
            }
        }
        return result
    }

    /// Проза с вырезанными `![alt](src)` вхождениями. Хвостовая/ведущая
    /// пунктуация кусков обрезается: стыки идут в разные вью, и лишние
    /// пробелы ничего не соединяют.
    private static func splitImages(in prose: String) -> [MarkdownMediaSegment] {
        let pattern = #"!\[([^\]]*)\]\(([^()\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.prose(prose)]
        }
        let ns = prose as NSString
        var out: [MarkdownMediaSegment] = []
        var last = 0

        func flush(from: Int, to: Int) {
            guard to > from else { return }
            let chunk = ns.substring(with: NSRange(location: from, length: to - from))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { out.append(.prose(chunk)) }
        }

        for match in regex.matches(in: prose, options: [], range: NSRange(location: 0, length: ns.length)) {
            flush(from: last, to: match.range.location)
            let alt = match.numberOfRanges > 1 ? ns.substring(with: match.range(at: 1)) : ""
            let source = match.numberOfRanges > 2 ? ns.substring(with: match.range(at: 2)) : ""
            out.append(.image(alt: alt, source: source))
            last = match.range.location + match.range.length
        }
        flush(from: last, to: ns.length)
        return out.isEmpty ? [.prose(prose)] : out
    }

    /// Проза сообщения ровно в том виде, в каком её получает selectable
    /// markdown-рендерер (без картинок и фенсов). Преварм кеша должен
    /// использовать те же строки, что и вью.
    static func proseTexts(from text: String) -> [String] {
        segments(from: text).compactMap { segment in
            guard case .prose(let prose) = segment else { return nil }
            return prose
        }
    }

    static func proseTexts(from texts: [String]) -> [String] {
        texts.flatMap { proseTexts(from: $0) }
    }
}
