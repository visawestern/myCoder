import Foundation

/// `BrowserAutomationBridge` implementation driving the AntiBrowser fork over
/// its loopback API: CDP (port 9222) for reads (DOM, screenshots, cookies,
/// navigation) and the local REST API (port 5390) for human-shaped actions.
///
/// Design (plan v1.2):
/// - REST is action-only. Mouse/keyboard go through `/act/*` which synthesizes
///   human input inside the browser process, so a site sees the same event
///   stream as from a person.
/// - Every read (DOM text, fingerprint, cookie, screenshot, navigation state)
///   goes over CDP, so there is a single source of truth.
/// - The token is read from the AntiBrowser profile Local State
///   (`antibrowser.agent_api.token`).
final class AntiBrowserAutomationBridge: BrowserAutomationBridge {
    private let cdpBase: String
    private let apiBase: String
    private let apiToken: String

    // CDP connection bookkeeping.
    private var ws: URLSessionWebSocketTask?
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var targetID: String?

    init(cdpPort: Int = 9222,
         apiPort: Int = 5390,
         profileDir: URL? = nil,
         cdpBase: String = "http://127.0.0.1:9222",
         apiBase: String = "http://127.0.0.1:5390") {
        self.cdpBase = profileDir == nil ? cdpBase : "http://127.0.0.1:\(cdpPort)"
        self.apiBase = profileDir == nil ? apiBase : "http://127.0.0.1:\(apiPort)"
        self.apiToken = Self.readToken(profileDir: profileDir)
    }

    // MARK: - Token / profile

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

    // MARK: - CDP plumbing

    /// Resolves the page target id (reusing the cached one if it still exists).
    private func ensureTarget() async throws -> String {
        if let targetID, try await targetStillAlive(targetID) {
            return targetID
        }
        let url = URL(string: "\(cdpBase)/json/list")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "AntiBrowserBridge", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "CDP /json/list недоступен"])
        }
        guard let page = array.first(where: { ($0["type"] as? String) == "page" }),
              let wsURL = page["webSocketDebuggerUrl"] as? String,
              let id = page["id"] as? String else {
            throw NSError(domain: "AntiBrowserBridge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Нет вкладки страницы"])
        }
        targetID = id
        try await connectWebSocket(wsURL)
        return id
    }

    private func targetStillAlive(_ id: String) async throws -> Bool {
        let url = URL(string: "\(cdpBase)/json/list")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        return array.contains { ($0["id"] as? String) == id }
    }

    private func connectWebSocket(_ urlString: String) async throws {
        if ws != nil {
            ws?.cancel()
            ws = nil
        }
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AntiBrowserBridge", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Неверный ws URL"])
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        ws = task
        // Start the receiver loop.
        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while let ws {
            do {
                let message = try await ws.receive()
                guard case .string(let text) = message,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? Int else {
                    continue
                }
                if let cont = pending.removeValue(forKey: id) {
                    cont.resume(returning: json)
                }
            } catch {
                pending.values.forEach { $0.resume(throwing: error) }
                pending.removeAll()
                return
            }
        }
    }

    /// Sends a CDP command and awaits its result.
    private func send(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        let target = try await ensureTarget()
        _ = target
        guard let ws else {
            throw NSError(domain: "AntiBrowserBridge", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "CDP не подключён"])
        }
        let id = nextId
        nextId += 1
        let payload: [String: Any] = ["id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await ws.send(.string(String(data: data, encoding: .utf8)!))
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
            pending[id] = cont
        }
    }

    /// Evaluates JS in the page and returns the `result.value` (or nil).
    private func evalPage(_ script: String) async throws -> Any? {
        let result = try await send("Runtime.evaluate", [
            "expression": script,
            "returnByValue": true,
            "awaitPromise": true,
        ])
        if let exception = result["exceptionDetails"] {
            let text = (exception as? [String: Any])?["text"] as? String ?? "исключение"
            throw NSError(domain: "AntiBrowserBridge", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        if let r = result["result"] as? [String: Any] {
            return r["value"]
        }
        return nil
    }

    // MARK: - REST actions

    /// POST body to the local agent API endpoint with the token.
    private func api(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(apiBase)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiToken.isEmpty {
            request.setValue(apiToken, forHTTPHeaderField: "X-AntiBrowser-Token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "AntiBrowserBridge", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "API без ответа"])
        }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "AntiBrowserBridge", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "API \(http.statusCode): \(text)"])
        }
        return json
    }

    /// Returns the viewport rect of the first element matching the selector.
    private func rect(of selector: String) async throws -> (x: Double, y: Double) {
        let script = """
        (() => {
          const el = document.querySelector(\(jsonString(selector)));
          if (!el) return null;
          const r = el.getBoundingClientRect();
          return {x: r.left + r.width / 2, y: r.top + r.height / 2};
        })()
        """
        guard let value = try await evalPage(script) as? [String: Any],
              let x = value["x"] as? Double,
              let y = value["y"] as? Double else {
            throw NSError(domain: "AntiBrowserBridge", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "Элемент не найден: \(selector)"])
        }
        return (x, y)
    }

    private func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: s)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - BrowserAutomationBridge

    func navigate(to url: String) async throws {
        _ = try await send("Page.navigate", ["url": url])
    }

    func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws {
        let point = try await rect(of: selector)
        _ = try await api("/act/click", body: ["x": point.x, "y": point.y])
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = try await api("/act/type", body: ["text": text])
        if pressEnter {
            _ = try await api("/act/key", body: ["key": "Enter"])
        }
    }

    func click(selector: String) async throws {
        let point = try await rect(of: selector)
        _ = try await api("/act/click", body: ["x": point.x, "y": point.y])
    }

    @discardableResult
    func clickByText(selector: String, text: String) async throws -> Bool {
        let script = """
        (() => {
          const els = [...document.querySelectorAll(\(jsonString(selector)))];
          const target = els.find(e => (e.innerText || '').trim() === \(jsonString(text)))
                       || els.find(e => (e.innerText || '').includes(\(jsonString(text))));
          if (!target) return null;
          const r = target.getBoundingClientRect();
          return {x: r.left + r.width / 2, y: r.top + r.height / 2};
        })()
        """
        guard let value = try await evalPage(script) as? [String: Any],
              let x = value["x"] as? Double,
              let y = value["y"] as? Double else {
            return false
        }
        _ = try await api("/act/click", body: ["x": x, "y": y])
        return true
    }

    func readText(selector: String) async throws -> String {
        let script = """
        (() => { const el = document.querySelector(\(jsonString(selector))); return el ? el.innerText : ''; })()
        """
        return (try await evalPage(script) as? String) ?? ""
    }

    func responseFingerprint(selector: String) async throws -> String {
        let script = """
        (() => {
          const el = document.querySelector(\(jsonString(selector)));
          if (!el) return '';
          const nodes = [...el.querySelectorAll('*')].length;
          return (el.innerHTML || '').length + ':' + nodes;
        })()
        """
        return (try await evalPage(script) as? String) ?? ""
    }

    func exists(selector: String) async throws -> Bool {
        let script = """
        (() => { const el = document.querySelector(\(jsonString(selector))); return !!el && el.getClientRects().length > 0; })()
        """
        return (try await evalPage(script) as? Bool) ?? false
    }

    func pageText() async throws -> String {
        let script = "document.body ? document.body.innerText : ''"
        return (try await evalPage(script) as? String) ?? ""
    }

    func currentURL() async throws -> String {
        let script = "location.href"
        return (try await evalPage(script) as? String) ?? ""
    }

    func cookies() async throws -> [BrowserCookie] {
        let result = try await send("Network.getCookies")
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
        _ = try await send("Network.setCookies", ["cookies": list])
    }

    func setLocalStorage(_ values: [String: String]) async throws {
        let script = values.map { "localStorage.setItem(\(jsonString($0.key)), \(jsonString($0.value)))" }.joined(separator: "; ")
        _ = try await evalPage(script)
    }

    func screenshot(selector: String?) async throws -> Data {
        // Full-page screenshot; region clipping is left to the caller.
        let result = try await send("Page.captureScreenshot", ["format": "png"])
        guard let base64 = result["data"] as? String,
              let data = Data(base64Encoded: base64) else {
            throw NSError(domain: "AntiBrowserBridge", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "Скриншот не удался"])
        }
        return data
    }

    func stopGeneration() async throws {
        _ = try await api("/act/key", body: ["key": "Escape"])
    }

    func wait(ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    func readModelItems(modelItemSelector: String) async throws -> [String] {
        let script = """
        (() => [...document.querySelectorAll(\(jsonString(modelItemSelector)))]
          .map(e => (e.innerText || '').trim()).filter(t => t.length > 0))()
        """
        return (try await evalPage(script) as? [String]) ?? []
    }

    func readModelCandidates(modelItemSelector: String) async throws -> [WebModelDOMItem] {
        let script = """
        (() => [...document.querySelectorAll(\(jsonString(modelItemSelector)))].map(e => {
          const r = e.getBoundingClientRect();
          return {
            label: (e.innerText || '').trim().split('\\n')[0],
            fullText: (e.innerText || '').trim(),
            identity: e.id || e.className || e.tagName,
            isVisible: r.width > 0 && r.height > 0,
            isSelectable: !e.disabled,
            isDisabled: !!e.disabled,
            isLeaf: e.children.length === 0,
            sourceSelector: \(jsonString(modelItemSelector)),
          };
        }))()
        """
        guard let items = try await evalPage(script) as? [[String: Any]] else { return [] }
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
        var result: [WebModelDOMItem] = []
        for selector in ["[role='option']", "[role='menuitem']", "[class*='model-item']", "[class*='model-option']"] {
            result.append(contentsOf: try await readModelCandidates(modelItemSelector: selector))
        }
        return result
    }

    func evaluateJS(_ script: String) async throws -> Any? {
        try await evalPage(script)
    }
}
