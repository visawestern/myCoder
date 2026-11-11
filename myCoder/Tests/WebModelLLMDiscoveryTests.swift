import Testing
import Foundation
@testable import myCoder

/// Универсальное обнаружение моделей внутренней моделью по DOM.
///
/// Когда селекторы каталога не сработали (сайт переделал разметку), мост
/// отдаёт внутренней модели компактный снимок DOM, а её строгий JSON-ответ
/// проходит ту же проверку названий, что и обычный разбор меню.
@MainActor
@Suite("WebModelLLMDiscovery — модели по DOM внутренней моделью")
struct WebModelLLMDiscoveryTests {

    private func dom(_ text: String = "Kimi K3") -> String {
        """
        {"url":"https://kimi.moonshot.cn/chat/x","title":"Kimi",
         "controls":[{"tag":"button","role":"","label":"","text":"\(text)","testId":"model-switcher",
                      "className":"current-model","disabled":false,"expanded":"false"}],
         "bodyText":"Kimi K3 Быстрый"}
        """
    }

    // MARK: - Разбор ответа

    @Test("Принимает JSON в кодовом блоке")
    func parsesFencedJSON() {
        let response = """
        ```json
        {"models": ["K3", "K3 Swarm"]}
        ```
        """
        #expect(WebModelLLMDiscovery.parse(response: response, vendor: .kimi) == ["K3", "K3 Swarm"])
    }

    @Test("Принимает голый массив без обёртки")
    func parsesPlainArray() {
        let response = #"["Qwen3.8-Max", "Qwen3-Coder"]"#
        #expect(WebModelLLMDiscovery.parse(response: response, vendor: .qwen)
                == ["Qwen3.8-Max", "Qwen3-Coder"])
    }

    @Test("Отбрасывает служебные подписи и повторы")
    func rejectsChromeAndDuplicates() {
        let response = """
        {"models": ["Model", "Fast", "Upgrade", "K3", "k3", "All models",
                    "This is a long sentence describing the page"]}
        """
        #expect(WebModelLLMDiscovery.parse(response: response, vendor: .kimi) == ["K3"])
    }

    @Test("Пустой ответ и обычный текст не дают моделей")
    func rejectsGarbage() {
        #expect(WebModelLLMDiscovery.parse(response: "Моделей не нашёл.", vendor: .kimi).isEmpty)
        #expect(WebModelLLMDiscovery.parse(response: #"{"models": []}"#, vendor: .kimi).isEmpty)
    }

    @Test("Подсказка требует строгий JSON и содержит снимок DOM")
    func promptIsStrictAndCarriesDOM() {
        let messages = WebModelLLMDiscovery.prompt(vendor: .kimi, domSnapshot: dom())
        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[0].content.contains("JSON"))
        #expect(messages[0].content.contains("models"))
        #expect(messages[0].content.contains("every distinct model name"))
        #expect(messages[1].content.contains("Kimi K3"))
    }

    // MARK: - Обнаружение

    @Test("Внутренняя модель возвращает живые модели из DOM")
    func discoverParsesInternalModelAnswer() async {
        let bridge = FakeDOMBridge(snapshot: dom())
        var sent: [DirectChatMessage] = []
        let models = await WebModelLLMDiscovery.discover(
            using: bridge,
            vendor: .kimi,
            complete: { messages in
                sent = messages
                return #"{"models":["K3","K3 Swarm"]}"#
            }
        )
        #expect(models?.map(\.name) == ["K3", "K3 Swarm"])
        #expect(models?.allSatisfy { $0.isLiveDiscovered } == true)
        #expect(sent.count == 2)
    }

    @Test("Недоступная внутренняя модель — честный nil, без выдуманных имён")
    func discoverFailsClosedWithoutModel() async {
        let bridge = FakeDOMBridge(snapshot: dom())
        let models = await WebModelLLMDiscovery.discover(
            using: bridge,
            vendor: .kimi,
            complete: { _ in throw InternalModelRunner.NoModelError() }
        )
        #expect(models == nil)
    }

    @Test("Пустой DOM не тратит вызов внутренней модели")
    func emptyDOMSkipsModel() async {
        let bridge = FakeDOMBridge(snapshot: nil)
        var called = false
        let models = await WebModelLLMDiscovery.discover(
            using: bridge,
            vendor: .kimi,
            complete: { _ in
                called = true
                return #"{"models":["K3"]}"#
            }
        )
        #expect(models == nil)
        #expect(called == false)
    }

    @Test("Ответ без моделей — nil, а не пустой успех")
    func emptyAnswerIsNil() async {
        let bridge = FakeDOMBridge(snapshot: dom())
        let models = await WebModelLLMDiscovery.discover(
            using: bridge,
            vendor: .kimi,
            complete: { _ in #"{"models":[]}"# }
        )
        #expect(models == nil)
    }

    // MARK: - Связка с обычным обнаружением

    @Test("Когда селекторы не сработали, discovery спрашивает внутреннюю модель")
    func discoveryFallsBackToInternalModel() async {
        let bridge = FakeDOMBridge(snapshot: dom())
        let models = await WebModelDiscovery.discover(
            using: bridge,
            dropdownSelector: "div.nonexistent-model-button",
            vendor: .kimi,
            internalComplete: { _ in #"{"models":["K3","K3 Swarm"]}"# }
        )
        #expect(models?.map(\.name) == ["K3", "K3 Swarm"])
    }

    @Test("Когда селекторы сработали, внутренняя модель не вызывается")
    func workingSelectorsDoNotCallInternalModel() async {
        let bridge = WorkingSelectorBridge()
        var called = false
        let models = await WebModelDiscovery.discover(
            using: bridge,
            dropdownSelector: "div.current-model",
            vendor: .kimi,
            internalComplete: { _ in
                called = true
                return #"{"models":["Wrong"]}"#
            }
        )
        #expect(models?.contains { $0.name == "K3" } == true)
        #expect(called == false)
    }
}

/// Мост-двойник: живой DOM отдаёт снимок, селекторы каталога не находят меню.
private final class FakeDOMBridge: BrowserAutomationBridge {
    let snapshot: String?

    init(snapshot: String?) { self.snapshot = snapshot }

    func navigate(to url: String) async throws {}
    func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws {}
    func click(selector: String) async throws {}
    func clickByText(selector: String, text: String) async throws -> Bool { false }
    func readText(selector: String) async throws -> String { "" }
    func exists(selector: String) async throws -> Bool { false }
    func pageText() async throws -> String { "" }
    func currentURL() async throws -> String { "https://kimi.moonshot.cn/chat/x" }
    func cookies() async throws -> [BrowserCookie] { [] }
    func setCookies(_ cookies: [BrowserCookie]) async throws {}
    func screenshot(selector: String?) async throws -> Data { Data() }
    func wait(ms: Int) async {}
    func evaluateJS(_ script: String) async throws -> Any? { snapshot }
}

/// Мост-двойник: обычные селекторы работают, поэтому DOM-запасной путь не нужен.
private final class WorkingSelectorBridge: BrowserAutomationBridge {
    private var open = false

    func navigate(to url: String) async throws {}
    func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws {}
    func click(selector: String) async throws { if selector.contains("current-model") { open = true } }
    func clickByText(selector: String, text: String) async throws -> Bool { false }
    func readText(selector: String) async throws -> String { "" }
    func exists(selector: String) async throws -> Bool {
        selector.contains("current-model") || (open && selector.contains("model-item"))
    }
    func pageText() async throws -> String { "" }
    func currentURL() async throws -> String { "https://kimi.moonshot.cn/chat/x" }
    func cookies() async throws -> [BrowserCookie] { [] }
    func setCookies(_ cookies: [BrowserCookie]) async throws {}
    func screenshot(selector: String?) async throws -> Data { Data() }
    func wait(ms: Int) async {}
    func waitForSelector(selector: String, timeout: Int) async throws {}
    func readModelItems(modelItemSelector: String) async throws -> [String] {
        guard open else { return [] }
        return ["K3", "K3 Swarm"]
    }
    func evaluateJS(_ script: String) async throws -> Any? {
        Issue.record("internal model fallback must not run when selectors work")
        return nil
    }
}
