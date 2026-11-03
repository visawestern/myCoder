import Foundation

/// Ленивый старт движка: мосты запрашивают его через этот протокол, чтобы
/// юнит-тесты могли подменить реальный EngineStatusCenter фейком.
protocol EngineBootstrapping {
    var isReady: Bool { get }
    func start() async
}

extension EngineStatusCenter: EngineBootstrapping {}

/// `BrowserAutomationBridge` implementation driving the AntiBrowser fork
/// **исключительно через его REST API** (порт 5390): действия — `/act/*`
/// (человеко-подобный ввод), страничные операции — `/tabs`, `/page/*`,
/// `/cookies/*`. Никакого CDP/WebSocket на клиенте нет.
///
/// Модель вкладок: каждый чат имеет свой ключ (`tab_key`); браузер создаёт
/// вкладку на ключ при первом обращении и переиспользует её при повторном.
final class AntiBrowserAutomationBridge: BrowserAutomationBridge {
    private let tabKey: String
    private var apiPort: Int
    private var profileDir: URL?
    private var apiToken: String
    /// Источник запуска движка (инъекция для тестов).
    var engineBootstrap: EngineBootstrapping? = EngineStatusCenter.shared

    init(tabKey: String,
         apiPort: Int = 5390,
         profileDir: URL? = nil) {
        self.tabKey = tabKey
        self.apiPort = apiPort
        self.profileDir = profileDir
        self.apiToken = Self.readToken(profileDir: profileDir)
    }

    /// Обновляет адрес/профиль после старта движка: мост мог быть создан
    /// раньше готовности (например, экран входа открыли при запуске), и
    /// тогда токен был пустым — все запросы получали 401.
    func configure(apiPort: Int, profileDir: URL) {
        self.apiPort = apiPort
        self.profileDir = profileDir
        self.apiToken = Self.readToken(profileDir: profileDir)
    }

    // MARK: - Ошибки

    private func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "AntiBrowserBridge", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - Токен

    private static func readToken(profileDir: URL?) -> String {
        guard let profileDir else { return "" }
        let statePath = profileDir.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: statePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ab = json["antibrowser"] as? [String: Any],
              let api = ab["agent_api"] as? [String: Any],
              let token = api["token"] as? String else {
            return ""
        }
        return token
    }

    // MARK: - REST

    private var apiBase: String {
        "http://127.0.0.1:\(apiPort)"
    }

    private func request(_ path: String,
                         body: [String: Any]?,
                         method: String = "POST") async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(apiBase)\(path)")!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiToken.isEmpty {
            request.setValue(apiToken, forHTTPHeaderField: "X-AntiBrowser-Token")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw error(10, "API без ответа: \(apiBase)\(path)")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard http.statusCode == 200, let json else {
            let detail = json?["error"] as? [String: Any]
            let message = detail?["message"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw error(11, "API \(http.statusCode): \(message)")
        }
        return json
    }

    /// POST с телом JSON → словарь.
    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        await ensureEngineStartedIfNeeded()
        return try await request(path, body: body)
    }

    /// Ленивый старт движка: первый реальный REST-запрос через мост сам
    /// поднимает браузер (веб-чат, вход в провайдер, спецпоиск). В
    /// юнит-тестах без профиля (profileDir == nil) ничего не запускаем.
    func ensureEngineStartedIfNeeded() async {
        guard profileDir != nil else { return }
        guard let engineBootstrap else { return }
        if apiToken.isEmpty || !engineBootstrap.isReady {
            await engineBootstrap.start()
            if let profileDir {
                apiToken = Self.readToken(profileDir: profileDir)
            }
        }
    }

    /// Убеждается, что вкладка чата существует (создаёт при необходимости).
    private func ensureTab(url: String? = nil) async throws {
        var body: [String: Any] = ["tab_key": tabKey]
        if let url {
            body["url"] = url
        }
        let result = try await post("/tabs", body)
        guard (result["ok"] as? Bool) == true else {
            throw error(2, "Не удалось подготовить вкладку браузера")
        }
    }

    /// POST /page/<ручка> с tab_key.
    private func page(_ name: String, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        var body: [String: Any] = ["tab_key": tabKey]
        for (k, v) in extra { body[k] = v }
        return try await post("/page/\(name)", body)
    }

    /// Значение `result` из /page/evaluate.
    private func evaluate(_ script: String) async throws -> Any? {
        let result = try await page("evaluate", ["script": script])
        if let errorValue = result["error"] {
            let text = (errorValue as? [String: Any])?["message"] as? String
                ?? "исключение"
            throw error(5, "JS: \(text)")
        }
        return result["result"]
    }

    /// Центр видимого элемента по селектору (viewport-координаты).
    private func rect(of selector: String) async throws -> (x: Double, y: Double) {
        let script = """
        (() => {
          const el = document.querySelector(\(WebJSString.encode(selector)));
          if (!el) return null;
          const r = el.getBoundingClientRect();
          if (r.width <= 0 || r.height <= 0) return null;
          return {x: r.left + r.width / 2, y: r.top + r.height / 2};
        })()
        """
        guard let value = try await evaluate(script) as? [String: Any],
              let x = value["x"] as? Double,
              let y = value["y"] as? Double else {
            throw error(12, "Элемент не найден: \(selector)")
        }
        return (x, y)
    }

    // MARK: - BrowserAutomationBridge

    func navigate(to url: String) async throws {
        try await ensureTab(url: url)
        let result = try await page("navigate", ["url": url])
        guard (result["ok"] as? Bool) == true else {
            throw error(13, "Навигация не удалась на \(url)")
        }
        // Ждём готовности документа (до 15 с).
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let state = try? await page("state"),
               (state["ready"] as? String) == "complete" {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw error(13, "Таймаут навигации на \(url)")
    }

    /// Ввод текста в СФОКУСИРОВАННЫЙ элемент страницы (каст: клавиатура).
    func typeTextGlobal(_ text: String) async throws {
        _ = try await post("/act/type", ["text": text])
    }

    /// Одно нажатие клавиши (каст: спецклавиши и Enter).
    func pressKey(_ key: String) async throws {
        _ = try await post("/act/key", ["key": key])
    }

    func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws {
        let point = try await rect(of: selector)
        _ = try await post("/act/click", ["x": point.x, "y": point.y])
        try await Task.sleep(nanoseconds: 200_000_000)

        var succeeded = false
        for attempt in 0..<3 {
            _ = try await post("/act/type", ["text": text])
            if (try? await verifyText(text, in: selector)) == true {
                succeeded = true
                break
            }
            if attempt < 2 {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        guard succeeded else {
            throw error(14, "Текст не дошёл до поля \(selector)")
        }

        if pressEnter {
            _ = try await post("/act/key", ["key": "Enter"])
        }
    }

    private func verifyText(_ text: String, in selector: String) async throws -> Bool {
        let script = """
        (() => {
          const el = document.querySelector(\(WebJSString.encode(selector)));
          if (!el) return false;
          const value = el.tagName === 'TEXTAREA' ? el.value : el.innerText;
          return (value || '').includes(\(WebJSString.encode(text)));
        })()
        """
        return (try await evaluate(script) as? Bool) ?? false
    }

    func click(selector: String) async throws {
        let script = """
        (() => {
          const el = document.querySelector(\(WebJSString.encode(selector)));
          if (!el) return {kind: 'missing'};
          const r = el.getBoundingClientRect();
          if (r.width <= 0 || r.height <= 0) return {kind: 'missing'};
          const disabled = el.disabled || el.getAttribute('aria-disabled') === 'true';
          if (disabled) return {kind: 'disabled'};
          return {kind: 'ok', x: r.left + r.width / 2, y: r.top + r.height / 2};
        })()
        """
        guard let value = try await evaluate(script) as? [String: Any] else {
            throw error(12, "Элемент не найден: \(selector)")
        }
        switch value["kind"] as? String {
        case "ok":
            guard let x = value["x"] as? Double, let y = value["y"] as? Double else {
                throw error(12, "Элемент не найден: \(selector)")
            }
            _ = try await post("/act/click", ["x": x, "y": y])
        case "disabled":
            throw error(16, "Кнопка присутствует, но отключена: \(selector)")
        default:
            throw error(12, "Элемент не найден: \(selector)")
        }
    }

    @discardableResult
    func clickByText(selector: String, text: String) async throws -> Bool {
        let script = """
        (() => {
          const els = [...document.querySelectorAll(\(WebJSString.encode(selector)))];
          const target = els.find(e => (e.innerText || '').trim() === \(WebJSString.encode(text)))
                       || els.find(e => (e.innerText || '').includes(\(WebJSString.encode(text))));
          if (!target) return null;
          const r = target.getBoundingClientRect();
          return {x: r.left + r.width / 2, y: r.top + r.height / 2};
        })()
        """
        guard let value = try await evaluate(script) as? [String: Any],
              let x = value["x"] as? Double,
              let y = value["y"] as? Double else {
            return false
        }
        _ = try await post("/act/click", ["x": x, "y": y])
        return true
    }

    @discardableResult
    func clickVisibleTextExact(selector: String, text: String) async throws -> Bool {
        let script = """
        (() => {
          const norm = s => (s || '').replace(/\\s+/g, ' ').trim();
          const want = norm(\(WebJSString.encode(text)));
          if (!want) return null;
          const els = [...document.querySelectorAll(\(WebJSString.encode(selector)))]
            .filter(e => e.getClientRects().length > 0);
          let best = null, bestLen = Infinity;
          for (const e of els) {
            const t = norm(e.innerText);
            if (!t) continue;
            if (t === want) { best = e; break; }
            if (t.startsWith(want) && t.length < bestLen) { best = e; bestLen = t.length; }
          }
          if (!best) return null;
          const r = best.getBoundingClientRect();
          return {x: r.left + r.width / 2, y: r.top + r.height / 2};
        })()
        """
        guard let value = try await evaluate(script) as? [String: Any],
              let x = value["x"] as? Double,
              let y = value["y"] as? Double else {
            return false
        }
        _ = try await post("/act/click", ["x": x, "y": y])
        return true
    }

    func readText(selector: String) async throws -> String {
        let script = """
        (() => { const el = document.querySelector(\(WebJSString.encode(selector))); return el ? el.innerText : ''; })()
        """
        return (try await evaluate(script) as? String) ?? ""
    }

    func responseFingerprint(selector: String) async throws -> String {
        let script = """
        (() => {
          const el = document.querySelector(\(WebJSString.encode(selector)));
          if (!el) return '';
          const nodes = [...el.querySelectorAll('*')].length;
          return (el.innerHTML || '').length + ':' + nodes;
        })()
        """
        return (try await evaluate(script) as? String) ?? ""
    }

    func exists(selector: String) async throws -> Bool {
        let script = """
        (() => { const el = document.querySelector(\(WebJSString.encode(selector))); return !!el && el.getClientRects().length > 0; })()
        """
        return (try await evaluate(script) as? Bool) ?? false
    }

    func pageText() async throws -> String {
        let result = try await page("text")
        return (result["text"] as? String) ?? ""
    }

    func currentURL() async throws -> String {
        let result = try await page("state")
        return (result["url"] as? String) ?? ""
    }

    func cookies() async throws -> [BrowserCookie] {
        let result = try await post("/cookies/get", ["tab_key": tabKey])
        guard let cookies = result["cookies"] as? [[String: Any]] else { return [] }
        return cookies.compactMap { c in
            guard let name = c["name"] as? String,
                  let value = c["value"] as? String else { return nil }
            return BrowserCookie(
                name: name,
                value: value,
                domain: c["domain"] as? String ?? "",
                path: c["path"] as? String ?? "/",
                expiresEpoch: c["expires"] as? Double,
                httpOnly: c["httpOnly"] as? Bool ?? false,
                secure: c["secure"] as? Bool ?? false)
        }
    }

    func setCookies(_ cookies: [BrowserCookie]) async throws {
        let list = cookies.map { c -> [String: Any] in
            var d: [String: Any] = [
                "name": c.name,
                "value": c.value,
                "domain": c.domain,
                "path": c.path,
                "httpOnly": c.httpOnly,
                "secure": c.secure,
            ]
            if let expires = c.expiresEpoch { d["expires"] = expires }
            return d
        }
        _ = try await post("/cookies/set", ["tab_key": tabKey, "cookies": list])
    }

    func setLocalStorage(_ values: [String: String]) async throws {
        _ = try await page("local-storage", ["values": values])
    }

    func screenshot(selector: String?) async throws -> Data {
        if let selector {
            let script = """
            (() => {
              const el = document.querySelector(\(WebJSString.encode(selector)));
              if (!el) return null;
              const r = el.getBoundingClientRect();
              if (r.width <= 0 || r.height <= 0) return null;
              return {x: r.left, y: r.top, width: r.width, height: r.height};
            })()
            """
            _ = try await evaluate(script)
            // Полноэкранный снимок; обрезка по селектору выполняется дальше
            // в SceencastController при необходимости. (Скриншоты по клипу
            // в браузере: см. /page/screenshot.)
        }
        return try await screenshotFrame().data
    }

    /// Скриншот + CSS-размер viewport. Картинка приходит в физических
    /// пикселях (Retina 2×), а /act/click принимает CSS-пиксели — касту нужен
    /// этот размер, иначе клики уходят мимо элементов.
    func screenshotFrame() async throws -> (data: Data, cssSize: CGSize?) {
        let result = try await page("screenshot")
        guard let base64 = result["data"] as? String,
              let data = Data(base64Encoded: base64) else {
            throw error(20, "Скриншот не удался")
        }
        var cssSize: CGSize?
        if let width = result["css_width"] as? Double,
           let height = result["css_height"] as? Double,
           width > 0, height > 0 {
            cssSize = CGSize(width: width, height: height)
        }
        return (data, cssSize)
    }

    func stopGeneration() async throws {
        let script = """
        (() => {
          const sels = ['[data-testid="stop-button"]',
                        'button[aria-label*="stop" i]',
                        'button[aria-label*="остановить" i]',
                        'button[class*="stop"]'];
          for (const s of sels) {
            const b = [...document.querySelectorAll(s)].find(el => el.getClientRects().length > 0);
            if (b) {
              const r = b.getBoundingClientRect();
              return {x: r.left + r.width / 2, y: r.top + r.height / 2};
            }
          }
          return null;
        })()
        """
        if let point = try await evaluate(script) as? [String: Any],
           let x = point["x"] as? Double,
           let y = point["y"] as? Double {
            _ = try await post("/act/click", ["x": x, "y": y])
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        _ = try await post("/act/key", ["key": "Escape"])
    }

    func wait(ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    func readModelItems(modelItemSelector: String) async throws -> [String] {
        let script = """
        (() => [...document.querySelectorAll(\(WebJSString.encode(modelItemSelector)))]
          .map(e => (e.innerText || '').trim()).filter(t => t.length > 0))()
        """
        return (try await evaluate(script) as? [String]) ?? []
    }

    func readModelCandidates(modelItemSelector: String) async throws -> [WebModelDOMItem] {
        let script = """
        (() => [...document.querySelectorAll(\(WebJSString.encode(modelItemSelector)))].map(e => {
          const r = e.getBoundingClientRect();
          return {
            label: (e.innerText || '').trim().split('\\n')[0],
            fullText: (e.innerText || '').trim(),
            identity: e.id || e.className || e.tagName,
            isVisible: r.width > 0 && r.height > 0,
            isSelectable: !e.disabled,
            isDisabled: !!e.disabled,
            isLeaf: e.children.length === 0,
            sourceSelector: \(WebJSString.encode(modelItemSelector)),
          };
        }))()
        """
        guard let items = try await evaluate(script) as? [[String: Any]] else { return [] }
        return items.compactMap { d in
            guard let label = d["label"] as? String else { return nil }
            return WebModelDOMItem(
                label: label,
                identity: d["identity"] as? String ?? "",
                isVisible: d["isVisible"] as? Bool ?? false,
                isSelectable: d["isSelectable"] as? Bool ?? true,
                isDisabled: d["isDisabled"] as? Bool ?? false,
                isLeaf: d["isLeaf"] as? Bool ?? true,
                sourceSelector: d["sourceSelector"] as? String ?? modelItemSelector,
                fullText: d["fullText"] as? String)
        }
    }

    func readVisibleModelCandidates() async throws -> [WebModelDOMItem] {
        let script = """
        (() => {
          const sels = ["[role='option']", "[role='menuitem']",
                        "[class*='model-item']", "[class*='model-option']"];
          const out = [];
          for (const s of sels) {
            for (const e of document.querySelectorAll(s)) {
              const r = e.getBoundingClientRect();
              if (r.width <= 0 || r.height <= 0) continue;
              const inSurface = !!e.closest('[data-state="open"],[role="dialog"],'
                + '[class*="popover"],[class*="picker"],[class*="menu"]');
              const inSidebar = !!e.closest('[class*="sidebar"],[id*="sidebar"]');
              if (inSidebar && !inSurface) continue;
              out.push({
                label: (e.innerText || '').trim().split('\\n')[0],
                fullText: (e.innerText || '').trim(),
                identity: e.id || e.className || e.tagName,
                isVisible: true,
                isSelectable: !e.disabled,
                isDisabled: !!e.disabled,
                isLeaf: e.children.length === 0,
                sourceSelector: s,
              });
            }
          }
          return out;
        })()
        """
        guard let items = try await evaluate(script) as? [[String: Any]] else { return [] }
        return items.compactMap { d in
            guard let label = d["label"] as? String else { return nil }
            return WebModelDOMItem(
                label: label,
                identity: d["identity"] as? String ?? "",
                isVisible: true,
                isSelectable: d["isSelectable"] as? Bool ?? true,
                isDisabled: d["isDisabled"] as? Bool ?? false,
                isLeaf: d["isLeaf"] as? Bool ?? true,
                sourceSelector: d["sourceSelector"] as? String ?? "",
                fullText: d["fullText"] as? String)
        }
    }

    func evaluateJS(_ script: String) async throws -> Any? {
        try await evaluate(script)
    }

    func attachImageToComposer(data: Data, mime: String) async throws -> Bool {
        let b64 = data.base64EncodedString()
        let script = """
        (async () => {
          const bytes = Uint8Array.from(atob(\(WebJSString.encode(b64))), c => c.charCodeAt(0));
          const file = new File([bytes], 'attachment.png', {type: \(WebJSString.encode(mime))});
          const dt = new DataTransfer();
          dt.items.add(file);
          const targets = [...document.querySelectorAll('div[contenteditable="true"], textarea')]
            .filter(el => el.getClientRects().length > 0);
          if (!targets.length) return false;
          const target = targets[0];
          target.focus();
          target.dispatchEvent(new ClipboardEvent('paste', {clipboardData: dt, bubbles: true, cancelable: true}));
          return true;
        })()
        """
        return (try await evaluate(script) as? Bool) ?? false
    }

    // MARK: - Управление кастом (дополнительно к протоколу)

    func clickAt(x: Double, y: Double) async throws {
        _ = try await post("/act/click", ["x": x, "y": y])
    }

    func scrollBy(dx: Double, dy: Double) async throws {
        _ = try await post("/act/scroll", ["dx": dx, "dy": dy])
    }

    func typeTextAt(_ text: String, x: Double, y: Double) async throws {
        _ = try await post("/act/click", ["x": x, "y": y])
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = try await post("/act/type", ["text": text])
    }
}
