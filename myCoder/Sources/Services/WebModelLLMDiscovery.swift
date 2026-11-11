import Foundation

/// Универсальное обнаружение моделей внутренней моделью по DOM.
///
/// Запасной путь для случая, когда селекторы каталога перестали совпадать с
/// разметкой сайта: мост отдаёт компактный снимок видимого DOM через REST API
/// браузера, внутренняя модель (`mercury-3` через `InternalModelRunner`)
/// возвращает строгий JSON со списком названий, а разбор проходит ту же
/// проверку, что и обычное меню. Никаких выдуманных имён: при недоступной
/// модели, пустом DOM или ответе без моделей результат — nil.
enum WebModelLLMDiscovery {
    /// Предел снимка DOM в символах. Страница может быть огромной, а
    /// внутренней модели нужны только видимые подписи элементов управления.
    static let maxSnapshotCharacters = 80_000

    /// Предел числа моделей в одном ответе — защита от зацикленного разбора.
    static let maxModels = 50

    // MARK: - Снимок DOM

    /// JavaScript для компактного снимка страницы.
    ///
    /// Возвращает JSON-строку: адрес, заголовок, видимые элементы управления
    /// (роль, подпись, текст, test id, класс, disabled/expanded) и видимый
    /// текст страницы. Полный HTML не передаётся: он содержит разметку,
    /// скрипты и служебные данные, которые модели не нужны.
    static func extractionScript() -> String {
        """
        (() => {
          const visible = (el) => {
            const style = getComputedStyle(el);
            const rect = el.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden'
              && rect.width > 0 && rect.height > 0;
          };
          const clean = (text, limit) => (text || '').replace(/\\s+/g, ' ').trim().slice(0, limit);
          const selector = 'button,[role="button"],[role="option"],[role="menuitem"],a,'
            + 'select,option,[aria-haspopup],[class*="model"],[class*="picker"],'
            + '[class*="dropdown"],[class*="menu"]';
          const controls = Array.from(document.querySelectorAll(selector))
            .filter(visible)
            .slice(0, 500)
            .map((el) => ({
              tag: el.tagName.toLowerCase(),
              role: el.getAttribute('role') || '',
              label: clean(el.getAttribute('aria-label') || el.getAttribute('title') || '', 160),
              text: clean(el.innerText || el.textContent || '', 160),
              testId: clean(el.getAttribute('data-testid') || '', 120),
              className: clean(typeof el.className === 'string' ? el.className : '', 160),
              disabled: !!(el.disabled || el.getAttribute('aria-disabled') === 'true'),
              expanded: el.getAttribute('aria-expanded') || ''
            }))
            .filter((item) => item.label || item.text || item.testId);
          const bodyText = clean(document.body ? document.body.innerText : '', 20000);
          return JSON.stringify({
            url: location.href,
            title: document.title,
            controls,
            bodyText
          });
        })()
        """
    }

    // MARK: - Подсказка внутренней модели

    /// Сообщения для внутренней модели.
    ///
    /// Вход: идентификатор сайта и снимок DOM. Выход: системная инструкция с
    /// требованием строгого JSON и пользовательское сообщение со снимком.
    /// Модель обязана копировать названия как есть и не добавлять то, чего
    /// нет на странице.
    static func prompt(vendor: WebChatVendor, domSnapshot: String) -> [DirectChatMessage] {
        let system = """
        You extract the list of selectable AI chat model names from a web page DOM snapshot.
        Return ONLY a JSON object in this exact shape: {"models":["exact model name", ...]}.
        Rules:
        1. Copy model names exactly as they appear in the snapshot. Never translate, shorten, or invent names.
        2. Include only selectable AI chat models. Do not include the site name alone.
        3. Exclude headings ("Model", "Models", "All models"), effort or thinking labels
           ("Fast", "Auto", "Thinking", "Reasoning", "Effort"), plan or upgrade text,
           navigation, buttons, marketing prose, and chat titles.
        4. If the model menu is closed, include the model name(s) visible in the current
           model button or header.
        5. If no model names are visible, return {"models":[]}.
        """
        let user = "Vendor: \(vendor.displayName) (\(vendor.rawValue))\nDOM snapshot:\n\(domSnapshot)"
        return [DirectChatMessage(role: "system", content: system),
                DirectChatMessage(role: "user", content: user)]
    }

    // MARK: - Разбор ответа

    /// Разбирает ответ внутренней модели в проверенные названия моделей.
    ///
    /// Вход: произвольный текст ответа и сайт. Выход: уникальные названия,
    /// прошедшие `WebModelListParser.normalize`; пустой массив, если JSON нет
    /// или все названия оказались служебными подписями. Поддерживаются
    /// объект `{"models":[...]}`, `{"model":"..."}` и голый массив строк, в
    /// том числе внутри кодового блока.
    static func parse(response: String, vendor: WebChatVendor) -> [String] {
        guard let payload = jsonPayload(in: response) else { return [] }
        let rawNames: [String]
        if let object = payload as? [String: Any] {
            if let models = object["models"] as? [String] {
                rawNames = models
            } else if let model = object["model"] as? String {
                rawNames = [model]
            } else {
                return []
            }
        } else if let array = payload as? [String] {
            rawNames = array
        } else if let array = payload as? [Any] {
            rawNames = array.compactMap { $0 as? String }
        } else {
            return []
        }

        var seen = Set<String>()
        var result: [String] = []
        for raw in rawNames {
            guard let name = WebModelListParser.normalize(raw, vendor: vendor) else { continue }
            guard seen.insert(name.lowercased()).inserted else { continue }
            result.append(name)
            if result.count == maxModels { break }
        }
        return result
    }

    /// Достаёт JSON из ответа: сначала пробует весь текст, затем первый
    /// объект или массив. Так ответ в кодовом блоке или с пояснением вокруг
    /// всё равно разбирается, а мусор без JSON — нет.
    private static func jsonPayload(in response: String) -> Any? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }
        for (open, close) in [("{", "}"), ("[", "]")] {
            guard let start = response.firstIndex(of: Character(open)),
                  let end = response.lastIndex(of: Character(close)),
                  start < end else { continue }
            let slice = String(response[start...end])
            if let data = slice.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return object
            }
        }
        return nil
    }

    // MARK: - Обнаружение

    /// Обнаружение моделей по DOM через внутреннюю модель.
    ///
    /// Вход: мост браузера, сайт и необязательный вызов модели (в тестах —
    /// подмена, в работе — `InternalModelRunner.complete`). Выход: живые
    /// модели или nil, если DOM пуст, модель недоступна или не нашла имён.
    /// Вызов модели не выполняется при пустом DOM — это зряшный расход.
    static func discover(using bridge: BrowserAutomationBridge,
                         vendor: WebChatVendor,
                         complete: (([DirectChatMessage]) async throws -> String)? = nil) async -> [WebProviderModel]? {
        guard let raw = try? await bridge.evaluateJS(extractionScript()),
              let snapshot = snapshotText(from: raw) else { return nil }
        let trimmed = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let bounded = String(trimmed.prefix(maxSnapshotCharacters))
        MyCoderAPIServer.appendLog(
            "[discover] \(vendor.rawValue): selectors failed, asking internal model over DOM (\(bounded.count) chars)"
        )

        let messages = prompt(vendor: vendor, domSnapshot: bounded)
        let answer: String
        do {
            if let complete {
                answer = try await complete(messages)
            } else {
                answer = try await InternalModelRunner.complete(messages: messages)
            }
        } catch {
            MyCoderAPIServer.appendLog(
                "[discover] \(vendor.rawValue): internal model unavailable — \(error.localizedDescription)"
            )
            return nil
        }

        let names = parse(response: answer, vendor: vendor)
        guard !names.isEmpty else {
            MyCoderAPIServer.appendLog(
                "[discover] \(vendor.rawValue): internal model found no usable model names"
            )
            return nil
        }
        MyCoderAPIServer.appendLog(
            "[discover] \(vendor.rawValue): internal model found \(names.count) model(s) \(names.prefix(6))"
        )
        return names.map {
            WebProviderModel(
                name: $0,
                discoveryStatus: .active,
                isLiveDiscovered: true,
                discoveryMessage: "Detected by the internal model from the page DOM."
            )
        }
    }

    /// Приводит результат `evaluateJS` к строке снимка. Реальный мост
    /// возвращает строку; тестовый или иной движок может вернуть словарь —
    /// тогда он сериализуется обратно в JSON.
    private static func snapshotText(from value: Any?) -> String? {
        if let string = value as? String { return string }
        if let object = value,
           JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }
}
