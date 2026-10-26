import Testing
import Foundation
@testable import myCoder

@Suite("WebModelDiscovery — model detection with custom dropdown")
struct WebModelDiscoveryTests {

    /// Fake bridge that simulates Kimi's DOM behavior
    final class FakeKimiBridge: BrowserAutomationBridge {
        var clickedSelectors: [String] = []
        var clickedTexts: [(selector: String, text: String)] = []
        var dropdownOpen = false
        var expandedMoreModels = false

        func navigate(to url: String) async throws {}
        func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws {}
        func click(selector: String) async throws {
            clickedSelectors.append(selector)
            if selector.contains("current-model") {
                dropdownOpen = true
            }
        }
        func clickByText(selector: String, text: String) async throws -> Bool {
            clickedTexts.append((selector, text))
            if text == "Expand more models" && !expandedMoreModels {
                expandedMoreModels = true
                return true
            }
            // Simulate finding the model in dropdown
            return text == "K3" || text == "Быстрый" || text == "K3 Swarm" || text == "K3 Swarm Pro" || text == "K3 Vision"
        }
        func readText(selector: String) async throws -> String { "" }
        func exists(selector: String) async throws -> Bool {
            if selector.contains("current-model") { return true }
            if selector.contains("model-item") { return dropdownOpen }
            return false
        }
        func pageText() async throws -> String { "" }
        func currentURL() async throws -> String { "https://kimi.moonshot.cn/chat/abc123" }
        func cookies() async throws -> [BrowserCookie] { [] }
        func setCookies(_ cookies: [BrowserCookie]) async throws {}
        func screenshot(selector: String?) async throws -> Data { Data() }
        func wait(ms: Int) async {}
        func waitForSelector(selector: String, timeout: Int) async throws {
            if selector.contains("model-item") && dropdownOpen { return }
        }
        func readModelItems(modelItemSelector: String) async throws -> [String] {
            guard dropdownOpen else { return [] }
            if expandedMoreModels {
                return ["Быстрый", "K3", "K3 Swarm", "K3 Swarm Pro", "K3 Vision"]
            }
            return ["Быстрый", "K3", "K3 Swarm"]
        }
    }

    @Test func discoverReturnsModelsFromCustomDropdown() async {
        let bridge = FakeKimiBridge()
        let models = await WebModelDiscovery.discover(
            using: bridge,
            dropdownSelector: "div.current-model",
            vendor: .kimi
        )

        #expect(models?.count == 3)
        #expect(models?.contains { $0.name == "K3" } == true)
        #expect(models?.contains { $0.name == "Быстрый" } == true)
        #expect(models?.contains { $0.name == "K3 Swarm" } == true)
    }

    @Test func discoverAllModelsExpandsNestedMenu() async {
        let bridge = FakeKimiBridge()
        let models = await WebModelDiscovery.discoverAllModels(
            using: bridge,
            dropdownSelector: "div.current-model",
            vendor: .kimi
        )
        #expect(models?.count == 5)
        #expect(models?.contains { $0.name == "K3 Swarm Pro" } == true)
        #expect(models?.contains { $0.name == "K3 Vision" } == true)
        #expect(models?.contains { $0.name == "Быстрый" } == true)
    }

    @Test func discoverClicksModelButtonFirst() async {
        let bridge = FakeKimiBridge()
        _ = await WebModelDiscovery.discover(
            using: bridge,
            dropdownSelector: "div.current-model",
            vendor: .kimi
        )

        #expect(bridge.clickedSelectors.contains("div.current-model"))
    }

    @Test func discoverAllModelsTraversesTwoExpansionLevelsAndRejectsHeadings() async {
        let bridge = FakeNestedQwenBridge()
        let models = await WebModelDiscovery.discoverAllModels(
            using: bridge,
            dropdownSelector: "button.qwen-model",
            vendor: .qwen,
            maxExpansionDepth: 4
        )
        #expect(models?.map(\.name) == ["Qwen3.8-Max", "Qwen3-Coder", "Qwen3.5-Coder"])
        #expect(models?.contains { $0.name == "Model" } == false)
        #expect(bridge.expansionLevel == 2)
    }

    @Test func discoverReturnsNilWhenButtonNotFound() async {
        let bridge = FakeKimiBridge()
        // Simulate button not found even after fallback
        let models = await WebModelDiscovery.discover(
            using: bridge,
            dropdownSelector: "div.nonexistent",
            vendor: .kimi
        )

        #expect(models == nil)
    }
}

private final class FakeNestedQwenBridge: BrowserAutomationBridge {
    var dropdownOpen = false
    var expansionLevel = 0

    func navigate(to url: String) async throws {}
    func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws {}
    func click(selector: String) async throws {
        if selector.contains("qwen-model") { dropdownOpen = true }
    }
    func clickByText(selector: String, text: String) async throws -> Bool {
        if text == "Expand more models", expansionLevel < 2 {
            expansionLevel += 1
            return true
        }
        return text.hasPrefix("Qwen3")
    }
    func readText(selector: String) async throws -> String { "" }
    func responseFingerprint(selector: String) async throws -> String { "level-\(expansionLevel)" }
    func exists(selector: String) async throws -> Bool {
        selector.contains("qwen-model") || (dropdownOpen && selector.contains("model-item"))
    }
    func pageText() async throws -> String { "" }
    func currentURL() async throws -> String { "https://chat.qwen.ai/chat/test" }
    func cookies() async throws -> [BrowserCookie] { [] }
    func setCookies(_ cookies: [BrowserCookie]) async throws {}
    func screenshot(selector: String?) async throws -> Data { Data() }
    func wait(ms: Int) async {}
    func waitForSelector(selector: String, timeout: Int) async throws {}
    func readModelItems(modelItemSelector: String) async throws -> [String] {
        guard dropdownOpen else { return [] }
        switch expansionLevel {
        case 0: return ["Model", "Qwen3.8-Max", "Expand more models"]
        case 1: return ["Model", "Qwen3.8-Max", "Qwen3-Coder", "Expand more models"]
        default: return ["Model", "Qwen3.8-Max", "Qwen3-Coder", "Qwen3.5-Coder"]
        }
    }
}

@Suite("WebModelListParser — parse dropdown text")
struct WebModelListParserCustomTests {

    @Test func parseKimiStyleText() {
        let text = "Быстрый\nK3\nK3 Swarm"
        let models = WebModelListParser.parse(dropdownText: text, vendor: .kimi)
        #expect(models == ["Быстрый", "K3", "K3 Swarm"])
    }

    @Test func parseFiltersNoise() {
        let text = "✓ New\nGPT-4o\nUpgrade\no1-preview"
        let models = WebModelListParser.parse(dropdownText: text, vendor: .chatgpt)
        #expect(models.contains("GPT-4o"))
        #expect(models.contains("o1-preview"))
        #expect(!models.contains("New"))
        #expect(!models.contains("Upgrade"))
    }

    @Test func rejectsModelHeadingsAndEffortLabels() {
        let text = "Model\nModel Comparison\nAll models\nQwen3.8-Max\nQwen3.5-Coder\nDeep thinking\nFast"
        let models = WebModelListParser.parse(dropdownText: text, vendor: .qwen)
        #expect(models == ["Qwen3.8-Max", "Qwen3.5-Coder"])
        #expect(!WebModelListParser.isValidModelLabel("Model", vendor: .qwen))
        #expect(!WebModelListParser.isValidModelLabel("Model Comparison", vendor: .qwen))
        #expect(!WebModelListParser.isValidModelLabel("Fast", vendor: .qwen))
    }

    @Test func parseDeduplicates() {
        let text = "GPT-4o\nGPT-4o\ngpt-4o"
        let models = WebModelListParser.parse(dropdownText: text, vendor: .chatgpt)
        #expect(models.count == 1)
    }
}

@Suite("WebProviderCatalog — load and query selectors")
struct WebProviderCatalogTests {

    @Test func kimiHasCorrectSelectors() throws {
        let catalog = try WebProviderCatalog.loadBundled()
        let kimi = try #require(catalog.selectors(for: "kimi"))

        #expect(kimi.modelDropdown.hasPrefix(".current-model"))
        #expect(kimi.modelButton?.hasPrefix(".current-model") == true)
        #expect(kimi.effortDropdown?.contains("effort-item") == true)
        #expect(kimi.modelItem?.contains("model-item") == true)
        #expect(kimi.newChatTexts?.contains("Новый чат") == true)
    }

    @Test func qwenHasCorrectSelectors() throws {
        let catalog = try WebProviderCatalog.loadBundled()
        let qwen = try #require(catalog.selectors(for: "qwen"))

        #expect(qwen.modelDropdown.contains("ant-dropdown-trigger"))
        #expect(qwen.modelItem?.contains("wms-list__item") == true)
        #expect(qwen.newChatTexts?.contains("Начать") == true)
    }
}


@Suite("Round 107 — strict effort and malformed-candidate regressions")
struct Round107WebModelDiscoveryRegressionTests {
    @Test("arbitrary model/page text never becomes a medium effort")
    func arbitraryTextIsNotAnEffort() {
        let raw = "Qwen3.8-Max\nThe flagship model delivering state-of-the-art performance\nModel comparison"
        #expect(WebModelListParser.parseEffortLevels(dropdownText: raw, vendor: .qwen).isEmpty)
        #expect(WebModelListParser.normalizeEffort("Qwen3.8-Max", vendor: .qwen) == nil)
    }

    @Test("known Qwen effort labels remain discoverable")
    func knownEffortLabelsRemainDiscoverable() {
        let efforts = WebModelListParser.parseEffortLevels(
            dropdownText: "Fast\nAuto\nDeep thinking",
            vendor: .qwen
        )
        #expect(efforts == [.low, .medium, .high])
    }
}
