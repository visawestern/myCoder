import Testing
import Foundation
@testable import myCoder

/// TDD для инструмента `browser_fetch` — «продвинутый web_fetch» через
/// API браузера: полный доступ к DOM (script), чтение по селектору,
/// клики по ссылкам, хромкаст/скриншоты.
@Suite("browser_fetch — планировщик и рендер (чистая логика)")
struct BrowserFetchToolTests {

    // MARK: - Планировщик: парсинг аргументов

    @Test func parseRequiresURL() {
        let result = BrowserFetchPlanner.parse([:])
        guard case .failure(let err) = result else {
            Issue.record("ожидали failure, получили success")
            return
        }
        #expect(err.message.contains("url"))
    }

    @Test func parseRejectsNonHTTP() {
        let result = BrowserFetchPlanner.parse(["url": "file:///etc/passwd"])
        guard case .failure(let err) = result else {
            Issue.record("ожидали failure для file://")
            return
        }
        #expect(err.message.contains("http"))
    }

    @Test func parseAcceptsValidPlan() {
        let result = BrowserFetchPlanner.parse([
            "url": "https://example.com/",
            "selector": "main",
            "click": "a[href*='signin']",
            "screenshot": "true",
            "limit": "1500",
        ])
        guard case .success(let plan) = result else {
            Issue.record("ожидали success, получили failure")
            return
        }
        #expect(plan.url == "https://example.com/")
        #expect(plan.readSelector == "main")
        #expect(plan.clickSelector == "a[href*='signin']")
        #expect(plan.screenshot == true)
        #expect(plan.limit == 1500)
        #expect(plan.script == nil)
    }

    @Test func parseDefaultsNoScreenshot() {
        let result = BrowserFetchPlanner.parse(["url": "https://example.com/"])
        guard case .success(let plan) = result else {
            Issue.record("ожидали success")
            return
        }
        #expect(plan.screenshot == false)
        #expect(plan.readSelector == nil)
        #expect(plan.clickSelector == nil)
        #expect(plan.limit == nil)
    }

    @Test func parseScriptAndSelectorConflict() {
        let result = BrowserFetchPlanner.parse([
            "url": "https://example.com/",
            "script": "document.title",
            "selector": "main",
        ])
        guard case .failure(let err) = result else {
            Issue.record("ожидали failure при одновременных script и selector")
            return
        }
        #expect(err.message.contains("script") || err.message.contains("selector"))
    }

    @Test func screenshotTruthyVariants() {
        for value in ["1", "true", "yes", "on"] {
            let result = BrowserFetchPlanner.parse([
                "url": "https://example.com/",
                "screenshot": value,
            ])
            guard case .success(let plan) = result else {
                Issue.record("screenshot=\(value) должен быть принят")
                continue
            }
            #expect(plan.screenshot == true, "screenshot=\(value) должен быть true")
        }
    }

    // MARK: - Рендер результата

    @Test func renderTextOnly() {
        let out = BrowserFetchRendering.render(
            text: "Главная страница",
            scriptResult: nil,
            includeScript: false,
            screenshotPNG: nil,
            limit: 8000
        )
        #expect(out.contains("Главная страница"))
        #expect(!out.contains("ATTACHED_IMAGE"))
    }

    @Test func renderTextTruncatedByLimit() {
        let long = String(repeating: "а", count: 5000)
        let out = BrowserFetchRendering.render(
            text: long,
            scriptResult: nil,
            includeScript: false,
            screenshotPNG: nil,
            limit: 1000
        )
        #expect(out.contains("[truncated"))
        #expect(out.count < 1200)
    }

    @Test func renderAppendsScreenshotMarker() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let out = BrowserFetchRendering.render(
            text: "текст страницы",
            scriptResult: nil,
            includeScript: false,
            screenshotPNG: png,
            limit: nil
        )
        #expect(out.hasPrefix("текст страницы"))
        #expect(out.contains("ATTACHED_IMAGE:image/png:"))
        let marker = out.components(separatedBy: "ATTACHED_IMAGE:image/png:")[1]
        #expect(Data(base64Encoded: marker) == png)
    }

    @Test func renderSerializesScriptResult() {
        let out = BrowserFetchRendering.render(
            text: "ТЕКСТ:",
            scriptResult: ["title": "Kimi", "links": 3],
            includeScript: true,
            screenshotPNG: nil,
            limit: nil
        )
        #expect(out.contains("Kimi"))
        #expect(out.contains("3"))
    }

    @Test func renderScriptNullStringifies() {
        let out = BrowserFetchRendering.render(
            text: "ТЕКСТ:",
            scriptResult: nil,
            includeScript: true,
            screenshotPNG: nil,
            limit: nil
        )
        #expect(out.contains("null"))
    }

    // MARK: - Регистрация инструмента в эмуляторе

    @Test func browserFetchRegisteredWithSchemaAndDescription() {
        #expect(WebEmulatedTool.browserFetch.rawValue == "browser_fetch")
        #expect(!WebEmulatedTool.browserFetch.argumentSchema.isEmpty)
        #expect(!WebEmulatedTool.browserFetch.description.isEmpty)
        #expect(!WebEmulatedTool.browserFetch.isCore,
                "browser_fetch не должен входить в минимальный профиль")
    }

    @Test func browserFetchAliasesResolve() {
        let cases: [(String, String)] = [
            ("BrowserFetch", "browser_fetch"),
            ("browser_fetch", "browser_fetch"),
            ("browse", "browser_fetch"),
            ("browser", "browser_fetch"),
            ("open_url", "browser_fetch"),
            ("browser_open", "browser_fetch"),
            ("web_browse", "browser_fetch"),
            ("dom_fetch", "browser_fetch"),
            ("visit", "browser_fetch"),
        ]
        for (alias, canonical) in cases {
            #expect(WebToolProtocolEmulator.canonicalToolName(alias) == canonical,
                    "\(alias) должен резолвиться в \(canonical)")
        }
    }

    @Test func browserFetchArgumentNormalization() {
        let normalized = WebToolProtocolEmulator.normalizedArguments(
            for: .browserFetch,
            from: [
                "target_url": "https://example.com/",
                "css_selector": "main",
                "js": "document.title",
                "target": "a",
                "shot": "1",
                "max_chars": "2000",
            ]
        )
        #expect(normalized["url"] == "https://example.com/")
        #expect(normalized["selector"] == "main")
        #expect(normalized["script"] == "document.title")
        #expect(normalized["click"] == "a")
        #expect(normalized["screenshot"] == "1")
        #expect(normalized["limit"] == "2000")
    }

    @Test func browserFetchIsReadOnlyForGate() {
        #expect(WebToolAccessGate.permission(for:
            WebToolCall(name: "browser_fetch", arguments: ["url": "https://example.com/"]),
            accessLevel: .askBeforeChanges) == .allow)
    }

    // MARK: - Тесты «идиот-юзера»: мусорные/враждебные входы

    @Test func hostileURLsAreRejected() {
        let bad: [String] = [
            "javascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "file:///etc/passwd",
            "ftp://example.com/file",
            "http://",
            "https://",
            "   ",
            "not a url",
            "",
        ]
        for url in bad {
            let result = BrowserFetchPlanner.parse(["url": url])
            guard case .failure = result else {
                Issue.record("ожидали failure для url '\(url)'")
                continue
            }
        }
    }

    @Test func hostileLimitValuesDoNotCrash() {
        for raw in ["-5", "abc", "999999999999999999999", "1e5", "0", "12.7"] {
            let result = BrowserFetchPlanner.parse(["url": "https://example.com/", "limit": raw])
            guard case .success(let plan) = result else {
                Issue.record("limit '\(raw)' не должен ломать парсинг")
                continue
            }
            // limit либо nil, либо неотрицательное число
            if let limit = plan.limit {
                #expect(limit >= 0, "limit=\(limit) из '\(raw)'")
            }
        }
    }

    @Test func hostileScreenshotValuesAreFalseUnlessTruthy() {
        for raw in ["maybe", "0", "false", "no", "off", "", "да"] {
            let result = BrowserFetchPlanner.parse(["url": "https://example.com/", "screenshot": raw])
            guard case .success(let plan) = result else {
                Issue.record("screenshot '\(raw)' не должен ломать парсинг")
                continue
            }
            #expect(plan.screenshot == false, "screenshot='\(raw)' должен быть false")
        }
    }

    @Test func truthyScreenshotToleratesCaseAndWhitespace() {
        // 'trUe ' is the SAME value as 'true': the parser trims and lowercases
        // before comparing, so hostile casing is accepted, not rejected.
        for raw in ["1", "true", "yes", "on", "trUe ", " TRUE"] {
            let result = BrowserFetchPlanner.parse(["url": "https://example.com/", "screenshot": raw])
            guard case .success(let plan) = result else {
                Issue.record("screenshot '\(raw)' не должен ломать парсинг")
                continue
            }
            #expect(plan.screenshot == true, "screenshot='\(raw)' должен быть true")
        }
    }

    @Test func hostileClickSelectorIsJustData() {
        // Селектор — это строка для движка; е вредит локальной системе и
        // не интерпретируется вне браузера. Должен пройти валидацию как
        // обычная строка.
        let result = BrowserFetchPlanner.parse([
            "url": "https://example.com/",
            "click": "'; DROP TABLE users; --",
        ])
        guard case .success(let plan) = result else {
            Issue.record("клик-строка не должна ломать парсинг")
            return
        }
        #expect(plan.clickSelector == "'; DROP TABLE users; --")
    }

    @Test func veryLongURLIsLimitedByParsing() {
        let long = "https://example.com/" + String(repeating: "a", count: 100000)
        let result = BrowserFetchPlanner.parse(["url": long])
        guard case .success(let plan) = result else {
            Issue.record("длинный url не должен ломать парсинг")
            return
        }
        #expect(plan.url == long)
    }

    @Test func mixedHostileArgsStillYieldPlan() {
        let result = BrowserFetchPlanner.parse([
            "url": "https://example.com/",
            "selector": "input[name='q']; <img src=x onerror=alert(1)>",
            "script": "document.body.innerText",
            "screenshot": "1",
            "limit": "1e9",
        ])
        guard case .failure(let err) = result else {
            Issue.record("script+selector одновременно должны конфликтовать")
            return
        }
        #expect(err.message.contains("script"))
    }
}

