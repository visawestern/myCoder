import Testing
import Foundation
@testable import myCoder

/// Обычный поиск в интернете через `web_search`: без API-ключа, без
/// привязки к конкретной модели. Здесь проверяется чистая логика: сборка
/// URL поискового запроса, разбор HTML-выдачи и рендер результата для
/// модели.
@Suite("web_search: поиск в интернете (чистая логика)")
struct WebSearchLogicTests {

    // MARK: - URL запроса

    @Test("Сборка URL использует HTML-версию поиска без API-ключа")
    func searchURLUsesHtmlEndpoint() {
        let url = WebSearchLogic.searchURL(query: "swift")
        #expect(url != nil)
        #expect(url?.host == "html.duckduckgo.com")
        #expect(url?.path == "/html")
        #expect(url?.query?.contains("q=swift") == true)
    }

    @Test("Запрос корректно кодируется: пробелы, кириллица, & и #")
    func searchURLEncodesQuery() {
        let url = WebSearchLogic.searchURL(query: "API ключ & тест #1")
        let query = url?.query ?? ""
        #expect(!query.contains(" "))
        #expect(!query.contains("&")) // «&» внутри запроса должен быть закодирован
        #expect(!query.contains("#"))
        #expect(query.contains("%20") || query.contains("+"))
        #expect(query.contains("%26")) // закодированный &
        // Декодирование возвращает исходный запрос.
        let decoded = query
            .replacingOccurrences(of: "q=", with: "")
            .removingPercentEncoding
        #expect(decoded == "API ключ & тест #1")
    }

    @Test("Пустой запрос не даёт URL")
    func blankQueryHasNoURL() {
        #expect(WebSearchLogic.searchURL(query: "") == nil)
        #expect(WebSearchLogic.searchURL(query: "   ") == nil)
        #expect(WebSearchLogic.searchURL(query: "\n") == nil)
    }

    // MARK: - Разбор HTML-выдачи

    /// Фикстура в формате DuckDuckGo HTML: два результата, у второго снипет
    /// содержит HTML-сущность `&amp;`, ссылки — л-ссылки с закодированным
    /// `uddg`.
    private let fixtureHTML = """
    <div class="result results_links results_links_deep web-result ">
      <div class="links_main links_deep result__body">
        <h2 class="result__title">
          <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.swift.org%2F&amp;rut=x">Official site</a>
        </h2>
        <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.swift.org%2F&amp;rut=x">Swift (programming language)</a>
      </div>
    </div>
    <div class="result results_links results_links_deep web-result ">
      <div class="links_main links_deep result__body">
        <h2 class="result__title">
          <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FSwift_%28programming_language%29&amp;rut=y">Swift (wiki)</a>
        </h2>
        <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FSwift_%28programming_language%29&amp;rut=y">A general-purpose &amp; multi-paradigm language</a>
      </div>
    </div>
    """

    @Test("Разбор извлекает заголовок, конечный URL и снипет")
    func parseExtractsTitleURLAndSnippet() {
        let results = WebSearchLogic.parseResults(from: fixtureHTML)
        #expect(results.count == 2)
        #expect(results[0].title == "Official site")
        #expect(results[0].url == "https://www.swift.org/")
        #expect(results[0].snippet == "Swift (programming language)")
        #expect(results[1].title == "Swift (wiki)")
        #expect(results[1].url == "https://en.wikipedia.org/wiki/Swift_(programming_language)")
        #expect(results[1].snippet == "A general-purpose & multi-paradigm language")
    }

    @Test("Разбор игнорирует HTML без результатных блоков")
    func parseIgnoresGarbage() {
        #expect(WebSearchLogic.parseResults(from: "").isEmpty)
        #expect(WebSearchLogic.parseResults(from: "<html><body><p>нет результатов</p></body></html>").isEmpty)
        #expect(WebSearchLogic.parseResults(from: "    ").isEmpty)
    }

    @Test("Заголовок без снипета не теряет ссылку")
    func parseAllowsMissingSnippet() {
        let html = """
        <div class="result">
          <h2 class="result__title">
            <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2F&amp;rut=z">Example</a>
          </h2>
        </div>
        """
        let results = WebSearchLogic.parseResults(from: html)
        #expect(results.count == 1)
        #expect(results[0].title == "Example")
        #expect(results[0].url == "https://example.com/")
        #expect(results[0].snippet.isEmpty)
    }

    // MARK: - Рендер результата

    @Test("Рендер показывает заголовок, URL и снипет каждого результата")
    func renderFormatsResults() {
        let results = [
            WebSearchResult(title: "A", url: "https://a.example", snippet: "описание A"),
            WebSearchResult(title: "B", url: "https://b.example", snippet: "")
        ]
        let text = WebSearchLogic.render(results)
        #expect(text.contains("A"))
        #expect(text.contains("https://a.example"))
        #expect(text.contains("описание A"))
        #expect(text.contains("B"))
        #expect(text.contains("https://b.example"))
    }

    @Test("Рендер обрезает список до разумного количества")
    func renderCapsCount() {
        var many: [WebSearchResult] = []
        for i in 0..<30 {
            many.append(WebSearchResult(title: "R\(i)", url: "https://r\(i).example", snippet: ""))
        }
        let text = WebSearchLogic.render(many, limit: 5)
        let lines = text.components(separatedBy: "\n").filter { $0.hasPrefix("R") }
        #expect(lines.count == 5)
        #expect(text.contains("R0"))
        #expect(!text.contains("R29"))
    }

    @Test("Длинные снипеты обрезаются с многоточием")
    func renderTruncatesLongSnippets() {
        let longSnippet = String(repeating: "a", count: 300)
        let results = [WebSearchResult(title: "A", url: "https://a.example", snippet: longSnippet)]
        let text = WebSearchLogic.render(results)
        #expect(!text.contains(longSnippet))
        #expect(text.contains(String(repeating: "a", count: 240) + "…"))
    }

    @Test("Короткий снипет не трогается")
    func renderKeepsShortSnippet() {
        let results = [WebSearchResult(title: "A", url: "https://a.example", snippet: "короткий")]
        let text = WebSearchLogic.render(results)
        #expect(text.contains("короткий"))
    }

    @Test("Пустой результат рендерится честно, без выдуманных ссылок")
    func renderEmptyIsHonest() {
        let text = WebSearchLogic.render([])
        #expect(!text.isEmpty)
        #expect(text.contains("no results") || text.contains("нет результатов") || text.contains("No results"))
    }

    // MARK: - Executor (инъекция fetch-функции)

    @Test("Executor возвращает отформатированные результаты поиска")
    func executorReturnsResults() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("websearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var executor = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        // Мок/фейк ТОЛЬКО внутри тестов: подменяет сетевой ответ на
        // фикстуру выдачи, чтобы прогнать весь путь executor'а без сети.
        executor.webSearchFetch = { _ in fixtureHTML }
        let result = await executor.webSearch(query: "swift")
        #expect(result.contains("Official site"), "результат: \(result)")
        #expect(result.contains("https://www.swift.org/"), "результат: \(result)")
        #expect(result.contains("Swift (programming language)"), "результат: \(result)")
    }

    @Test("Executor честно сообщает об ошибке поиска")
    func executorReportsFailureHonestly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("websearch-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var executor = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        executor.webSearchFetch = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let result = await executor.webSearch(query: "swift")
        #expect(result.contains("error"), "результат: \(result)")
    }

    @Test("Executor честно сообщает о слишком большом ответе")
    func executorReportsOversizedResponse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("websearch-large-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var executor = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        executor.webSearchFetch = { _ in
            throw WebSearchError.responseTooLarge
        }
        let result = await executor.webSearch(query: "swift")
        #expect(result.contains("too large"), "результат: \(result)")
    }

    @Test("Executor честно сообщает о rate limit (429)")
    func executorReportsRateLimit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("websearch-429-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var executor = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        executor.webSearchFetch = { _ in
            throw WebSearchError.rateLimited
        }
        let result = await executor.webSearch(query: "swift")
        #expect(result.contains("429"), "результат: \(result)")
    }
}
