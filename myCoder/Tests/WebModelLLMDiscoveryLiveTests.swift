import Testing
import Foundation
@testable import myCoder

/// Живая проверка обнаружения моделей внутренней моделью `mercury-3`.
/// Включается только явно:
/// `MYCODER_LIVE_TESTS=1 swift test --filter WebModelLLMDiscoveryLiveTests`.
///
/// В обычном прогоне не участвует: тест зависит от сети и ключа в настройках
/// приложения. Проверяется настоящий ответ модели на синтетический DOM —
/// строгий JSON и те же имена, что видны на странице.
@MainActor
@Suite("WebModelLLMDiscovery live: mercury-3 читает DOM",
       .enabled(if: ProcessInfo.processInfo.environment["MYCODER_LIVE_TESTS"] == "1"))
struct WebModelLLMDiscoveryLiveTests {

    /// Настройки приложения читаются из его домена: тестовый процесс живёт
    /// в другом домене UserDefaults.
    private func appDefaults() -> UserDefaults? {
        UserDefaults(suiteName: "com.mycoder.app")
    }

    /// Настоящий вызов внутренней модели с ключом из настроек приложения.
    private func mercuryCompletion(_ messages: [DirectChatMessage]) async throws -> String {
        guard let defaults = appDefaults(),
              let ref = InternalModelStore(defaults: defaults).models.first else {
            throw InternalModelRunner.NoModelError()
        }
        let providers = InternalModelResolver.customProviders(defaults: defaults)
        guard let provider = providers.first(where: { $0.id == ref.providerID }) else {
            throw InternalModelRunner.NoModelError()
        }
        let key = defaults.string(forKey: "api_key_\(provider.id)")
        let route = SpecPlannerRoute.openAICompatible(
            baseURL: provider.baseURL,
            apiKey: key,
            model: ref.modelID
        )
        return try await LiveSpecCompletionProvider(timeout: 90)
            .complete(SpecCompletionRequest(route: route, messages: messages))
    }

    /// Синтетический снимок: меню закрыто, но текущая модель и несколько
    /// пунктов видны в DOM. Служебных подписей хватает, чтобы проверить
    /// фильтрацию.
    private let syntheticDOM = """
    {"url":"https://kimi.moonshot.cn/chat/live-check","title":"Kimi",
     "controls":[
       {"tag":"button","role":"","label":"Model","text":"Kimi K3","testId":"model-switcher",
        "className":"current-model","disabled":false,"expanded":"false"},
       {"tag":"button","role":"option","label":"","text":"Kimi K3 Swarm","testId":"model-item",
        "className":"model-item","disabled":false,"expanded":""},
       {"tag":"button","role":"option","label":"","text":"Kimi K2.5","testId":"model-item",
        "className":"model-item","disabled":false,"expanded":""}
     ],
     "bodyText":"Kimi K3\\nKimi K3 Swarm\\nKimi K2.5\\nFast\\nThinking\\nUpgrade"}
    """

    /// Мост-двойник: отдаёт синтетический DOM и больше ничего.
    private final class DOMOnlyBridge: BrowserAutomationBridge {
        let snapshot: String
        init(snapshot: String) { self.snapshot = snapshot }

        func navigate(to url: String) async throws {}
        func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws {}
        func click(selector: String) async throws {}
        func clickByText(selector: String, text: String) async throws -> Bool { false }
        func readText(selector: String) async throws -> String { "" }
        func exists(selector: String) async throws -> Bool { false }
        func pageText() async throws -> String { "" }
        func currentURL() async throws -> String { "https://kimi.moonshot.cn/chat/live-check" }
        func cookies() async throws -> [BrowserCookie] { [] }
        func setCookies(_ cookies: [BrowserCookie]) async throws {}
        func screenshot(selector: String?) async throws -> Data { Data() }
        func wait(ms: Int) async { }
        func evaluateJS(_ script: String) async throws -> Any? { snapshot }
    }

    @Test("Настоящая модель возвращает строгий JSON с именами из DOM")
    func liveModelReadsSyntheticDOM() async throws {
        let answer = try await mercuryCompletion(
            WebModelLLMDiscovery.prompt(vendor: .kimi, domSnapshot: syntheticDOM)
        )
        let names = WebModelLLMDiscovery.parse(response: answer, vendor: .kimi)
        #expect(!names.isEmpty, "модель не вернула ни одного имени; ответ: \(answer.prefix(500))")
        #expect(names.contains("Kimi K3"), "в ответе нет Kimi K3: \(names)")
        #expect(names.contains("Kimi K3 Swarm"), "в ответе нет Kimi K3 Swarm: \(names)")
        #expect(!names.contains("Fast"), "служебная подпись Fast попала в модели: \(names)")
        #expect(!names.contains("Upgrade"), "служебная подпись Upgrade попала в модели: \(names)")
    }

    @Test("Обнаружение целиком: DOM → внутренняя модель → модели провайдера")
    func liveDiscoveryReturnsModels() async throws {
        let bridge = DOMOnlyBridge(snapshot: syntheticDOM)
        let models = await WebModelLLMDiscovery.discover(
            using: bridge,
            vendor: .kimi,
            complete: mercuryCompletion
        )
        let names = try #require(models, "обнаружение вернуло nil; ответ модели не разобран")
        #expect(!names.isEmpty)
        #expect(names.map(\.name).contains("Kimi K3"))
        #expect(names.allSatisfy { $0.isLiveDiscovered })
    }
}
