import Foundation

/// Ошибка планировщика `browser_fetch` (реализует Error для Result).
struct BrowserFetchError: Error, Equatable {
    let message: String
}

/// План выполнения `browser_fetch` — «продвинутый web_fetch» через REST API
/// движка AntiBrowser. Чистая структура: парсинг/валидация не трогают сеть.
struct BrowserFetchPlan {
    let url: String
    /// CSS-селектор: кликнуть ДО чтения (ссылки, кнопки «Войти»).
    let clickSelector: String?
    /// CSS-селектор: читать текст этого элемента (а не всей страницы).
    let readSelector: String?
    /// JS-выражение: полный доступ к DOM; результат сериализуется в ответ.
    let script: String?
    /// Вернуть скриншот страницы (PNG) как ATTACHED_IMAGE.
    let screenshot: Bool
    /// Верхняя граница символов текстового ответа.
    let limit: Int?
}

/// Парсинг и валидация аргументов `browser_fetch` (чистая функция).
enum BrowserFetchPlanner {
    static func parse(_ args: [String: String]) -> Result<BrowserFetchPlan, BrowserFetchError> {
        guard let url = args["url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else {
            return .failure(BrowserFetchError(message: "error: missing url (http/https only)"))
        }
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              parsed.host != nil else {
            return .failure(BrowserFetchError(message: "error: invalid URL '\(url)' (http/https only)"))
        }

        let script = args["script"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selector = args["selector"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let script, !script.isEmpty, let selector, !selector.isEmpty {
            return .failure(BrowserFetchError(
                message: "error: use either 'script' or 'selector', not both"))
        }
        let click = args["click"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let screenshot = isTruthy(args["screenshot"])
        // Строгий парсинг limit: только неотрицательные целые. Мусор
        // (1e5, 12.7, -5, abc, переполнение) → nil (дефолт), а не
        // молчаливое искажение.
        let limit: Int?
        if let raw = args["limit"] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = Int(trimmed), n >= 0 {
                limit = n
            } else {
                limit = nil
            }
        } else {
            limit = nil
        }

        return .success(BrowserFetchPlan(
            url: url,
            clickSelector: click?.isEmpty == false ? click : nil,
            readSelector: selector?.isEmpty == false ? selector : nil,
            script: script?.isEmpty == false ? script : nil,
            screenshot: screenshot,
            limit: limit
        ))
    }

    static func isTruthy(_ raw: String?) -> Bool {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else { return false }
        return ["1", "true", "yes", "on"].contains(raw)
    }
}

/// Формирование текстового ответа `browser_fetch` (чистая функция).
enum BrowserFetchRendering {
    /// Собирает финальную строку ответа: основной текст (обрезанный по limit),
    /// опциональный блок результата JS (включая null), опциональный маркер
    /// скриншота ATTACHED_IMAGE (тот же протокол, что у read_file — драйвер
    /// прикрепит картинку к следующему сообщению модели).
    static func render(text: String,
                       scriptResult: Any?,
                       includeScript: Bool,
                       screenshotPNG: Data?,
                       limit: Int?) -> String {
        var body = ProjectWebToolExecutor.truncateFetch(text, limit: limit)
        if includeScript {
            body += "\n\n--- JS result ---\n" + stringifyJSResult(scriptResult)
        }
        if let png = screenshotPNG, !png.isEmpty {
            let base64 = png.base64EncodedString()
            body += "\nATTACHED_IMAGE:image/png:\(base64)"
        }
        return body
    }

    /// Сериализация результата evaluateJS в строку: строки как есть,
    /// JSON-объекты компактно, всё остальное через description, nil → "null".
    static func stringifyJSResult(_ any: Any?) -> String {
        guard let any else { return "null" }
        if let s = any as? String { return s }
        if JSONSerialization.isValidJSONObject(any),
           let data = try? JSONSerialization.data(withJSONObject: any,
                                                  options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return String(describing: any)
    }
}
