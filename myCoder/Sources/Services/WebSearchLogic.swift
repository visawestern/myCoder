import Foundation

/// Один результат интернет-поиска.
///
/// Входы: нет (структура создаётся парсером).
/// Выходы: заголовок, конечный URL и снипет.
/// Зависимости: нет.
struct WebSearchResult: Equatable {
    /// Заголовок выдачи.
    let title: String
    /// Конечный URL результата (декодированный, с https://).
    let url: String
    /// Краткое описание результата; может быть пустым.
    let snippet: String
}

/// Ошибки поискового запроса (чистые, для честных сообщений модели).
enum WebSearchError: Error, Equatable {
    /// Ответ поисковика превысил лимит размера.
    case responseTooLarge
    /// Поисковик ответил 429 (слишком много запросов).
    case rateLimited
}

/// Чистая логика интернет-поиска `web_search`.
///
/// Бэкенд — HTML-версия DuckDuckGo (https://html.duckduckgo.com/html/?q=…):
/// она не требует API-ключа и отдаёт обычную HTML-выдачу. Логика не ходит
/// в сеть: сборка URL, разбор HTML и рендер результата — чистые функции,
/// которые можно тестировать и переносить отдельно.
///
/// Входы: строка запроса и HTML-выдача.
/// Выходы: URL запроса / массив `WebSearchResult` / текст для модели.
/// Зависимости: только `Foundation`.
enum WebSearchLogic {

    /// Хост HTML-версии поиска.
    static let endpointHost = "html.duckduckgo.com"
    /// Путь эндпоинта выдачи.
    static let endpointPath = "/html/"
    /// Сколько результатов показывать модели по умолчанию.
    static let maxResults = 8
    /// Верхняя граница размера ответа поисковика (байты): защита от
    /// огромных страниц, раздувающих контекст.
    static let maxResponseBytes = 1_000_000

    /// Собрать URL поискового запроса.
    ///
    /// - Parameter query: текст запроса (может содержать пробелы,
    ///   кириллицу, `&`, `#`, `%` — всё кодируется).
    /// - Returns: URL `https://html.duckduckgo.com/html/?q=<encoded>`, или
    ///   `nil` для пустого/пробельного запроса.
    static func searchURL(query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = endpointHost
        components.path = endpointPath
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }

    /// Разобрать HTML-выдачу DuckDuckGo в структурированные результаты.
    ///
    /// Формат блока выдачи:
    /// ```
    /// <div class="result ...">
    ///   <h2 class="result__title">
    ///     <a class="result__a" href="//duckduckgo.com/l/?uddg=<enc>&rut=…">Title</a>
    ///   </h2>
    ///   <a class="result__snippet" href="…">Snippet</a>
    /// </div>
    /// ```
    /// Ссылка — л-ссылка с закодированным конечным URL в параметре `uddg`.
    ///
    /// - Parameter html: сырая HTML-выдача.
    /// - Returns: массив результатов в порядке выдачи; блоки без заголовка
    ///   отбрасываются, снипет может отсутствовать.
    static func parseResults(from html: String) -> [WebSearchResult] {
        let ns = html as NSString
        guard let regex = try? NSRegularExpression(pattern: #"<div class="result"#),
              ns.length > 0 else {
            return []
        }
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }

        var results: [WebSearchResult] = []
        let length = ns.length
        for index in matches.indices {
            let start = matches[index].range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : length
            let block = ns.substring(with: NSRange(location: start, length: end - start))
            if let result = parseBlock(block) {
                results.append(result)
            }
        }
        return results
    }

    /// Отформатировать результаты для модели.
    ///
    /// - Parameters:
    ///   - results: найденные результаты.
    ///   - limit: максимальное число результатов (по умолчанию `maxResults`).
    ///   - maxSnippetLength: максимальная длина снипета (символы); слишком
    ///     длинные снипеты обрезаются с многоточием, чтобы не раздувать
    ///     контекст.
    /// - Returns: текст вида «заголовок / URL / снипет», по блоку на
    ///   результат; при пустой выдаче — честное сообщение.
    static func render(_ results: [WebSearchResult],
                       limit: Int = maxResults,
                       maxSnippetLength: Int = 240) -> String {
        guard !results.isEmpty else {
            return "No results found. Try rephrasing the query."
        }
        let capped = Array(results.prefix(max(1, limit)))
        var lines: [String] = []
        for result in capped {
            lines.append(result.title)
            lines.append(result.url)
            if !result.snippet.isEmpty {
                lines.append(clampedSnippet(result.snippet, maxLength: maxSnippetLength))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Обрезать снипет до разумной длины с многоточием.
    ///
    /// Вход: текст снипета и максимальная длина.
    /// Выход: текст (без изменений, если уже короткий).
    /// Зависимости: нет.
    static func clampedSnippet(_ snippet: String, maxLength: Int) -> String {
        guard snippet.count > maxLength else { return snippet }
        return String(snippet.prefix(max(0, maxLength))) + "…"
    }

    // MARK: - Private

    /// Извлечь один результат из блока `<div class="result …">…</div>`.
    ///
    /// - Parameter block: фрагмент HTML одного результата.
    /// - Returns: `WebSearchResult` или `nil`, если заголовок не найден.
    private static func parseBlock(_ block: String) -> WebSearchResult? {
        guard let titleLink = firstLink(className: "result__a", in: block),
              !titleLink.text.isEmpty else {
            return nil
        }
        let url = resolvedURL(from: titleLink.href)
        let snippet = firstLink(className: "result__snippet", in: block)?.text ?? ""
        return WebSearchResult(title: titleLink.text, url: url, snippet: snippet)
    }

    /// Ссылка с указанным классом: `href` и текст.
    ///
    /// - Parameters:
    ///   - className: атрибут `class` искомой ссылки.
    ///   - html: фрагмент HTML.
    /// - Returns: пара (href, текст) или `nil`.
    private static func firstLink(className: String, in html: String) -> (href: String, text: String)? {
        let pattern = #"<a[^>]*class="[^"]*"# + NSRegularExpression.escapedPattern(for: className) + #""[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#
        let ns = html as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3 else {
            return nil
        }
        let href = ns.substring(with: match.range(at: 1))
        let rawText = ns.substring(with: match.range(at: 2))
        return (href, decodeEntities(stripTags(rawText)))
    }

    /// Превратить л-ссылку поисковика в конечный URL.
    ///
    /// Л-ссылка DuckDuckGo выглядит как
    /// `//duckduckgo.com/l/?uddg=<percent-encoded>&rut=…` — конечный URL
    /// лежит в параметре `uddg`. Если `uddg` нет, ссылка используется как
    /// есть (с добавлением `https:` для схемо-относительных `//`).
    ///
    /// - Parameter href: сырой `href` из выдачи.
    /// - Returns: абсолютный URL результата.
    private static func resolvedURL(from href: String) -> String {
        let value = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: "uddg=") {
            let tail = value[range.upperBound...]
            let encoded = String(tail.prefix(while: { $0 != "&" }))
            if let decoded = encoded.removingPercentEncoding, !decoded.isEmpty {
                return decoded
            }
        }
        if value.hasPrefix("//") {
            return "https:" + value
        }
        return value
    }

    /// Удалить HTML-теги из фрагмента.
    ///
    /// - Parameter html: фрагмент HTML.
    /// - Returns: текст без тегов, с нормализованными пробелами.
    private static func stripTags(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let words = stripped.split(whereSeparator: { $0.isWhitespace })
        return words.joined(separator: " ")
    }

    /// Декодировать HTML-сущности (`&amp;`, `&lt;`, `&gt;`, `&quot;`,
    /// `&#39;`, `&nbsp;`).
    ///
    /// - Parameter text: текст с сущностями.
    /// - Returns: текст с символами.
    private static func decodeEntities(_ text: String) -> String {
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–"),
        ]
        var result = text
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}
