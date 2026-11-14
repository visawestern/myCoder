import Foundation

extension ProjectWebToolExecutor {
    /// Интернет-поиск `web_search`: запрос к HTML-выдаче DuckDuckGo без
    /// API-ключа. Чистая логика (сборка URL, разбор выдачи, рендер) живёт
    /// в `WebSearchLogic` и покрыта тестами; здесь только сетевой запрос
    /// (или инъекция из тестов через `webSearchFetch`).
    ///
    /// Вход: `query` — текст запроса; `session` — инъекция URLSession
    /// (в тестах подменяется).
    /// Выход: текст для модели — список результатов (заголовок, URL,
    /// снипет) или честная ошибка.
    /// Зависимости: `WebSearchLogic`, `URLSession`, `webSearchFetch`.
    func webSearch(query: String, session: URLSession = .shared) async -> String {
        guard let url = WebSearchLogic.searchURL(query: query) else {
            return "error: empty query"
        }
        do {
            let html: String
            if let fetch = webSearchFetch {
                html = try await fetch(url)
            } else {
                html = try await fetchSearchHTML(url: url, session: session)
            }
            let results = WebSearchLogic.parseResults(from: html)
            return WebSearchLogic.render(results)
        } catch let error as WebSearchError {
            switch error {
            case .responseTooLarge:
                return "error: search response too large (over \(WebSearchLogic.maxResponseBytes) bytes)"
            case .rateLimited:
                return "error: search rate limited (429), retry later"
            }
        } catch {
            return "error: search failed: \(error.localizedDescription)"
        }
    }

    /// Сетевой запрос HTML-выдачи поиска.
    ///
    /// - Parameters:
    ///   - url: URL запроса (собран `WebSearchLogic.searchURL`).
    ///   - session: URLSession для запроса.
    /// - Returns: HTML-строка выдачи.
    /// - Throws: `WebSearchError.responseTooLarge` при превышении лимита
    ///   размера, `WebSearchError.rateLimited` при 429, иначе ошибка
    ///   сети/HTTP/декодирования.
    private func fetchSearchHTML(url: URL, session: URLSession) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("myCoder/1.0 (tool web_search)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,text/plain,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429 {
            throw WebSearchError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= WebSearchLogic.maxResponseBytes else {
            throw WebSearchError.responseTooLarge
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }
}
