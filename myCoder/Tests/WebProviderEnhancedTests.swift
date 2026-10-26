import Testing
import Foundation
@testable import myCoder

@Suite("WebProviderModel + FeatureMode structures")
struct WebProviderModelTests {

    @Test func modelIdentifiableByName() {
        let m = WebProviderModel(name: "K3", description: "Flagship", availableModes: ["auto", "think"], supportsImageGeneration: true, supportsDeepResearch: false, supportsWebDev: false)
        #expect(m.id == "K3")
    }

    @Test func modelEquatable() {
        let a = WebProviderModel(name: "K3", description: "Flagship")
        let b = WebProviderModel(name: "K3", description: "Flagship")
        #expect(a == b)
    }

    @Test func featureModeIdentifiable() {
        let mode = FeatureMode(name: "Deep Research", icon: "magnifyingglass", isEnabled: true)
        #expect(mode.id == "Deep Research")
    }

    @Test func featureModeWithDisabledState() {
        let mode = FeatureMode(name: "Create Video", icon: "video", isEnabled: false)
        #expect(mode.isEnabled == false)
    }
}

@Suite("WebProviderConfig enhanced model management")
struct WebProviderConfigModelTests {

    private func makeConfig() -> WebProviderConfig {
        WebProviderConfig(vendor: .kimi, displayName: "Kimi", selectedModel: "K3", acknowledgedToS: true)
    }

    @Test func allModelsCombinesDiscoveredAndManual() {
        var config = makeConfig()
        config.discoveredModels = [
            WebProviderModel(name: "K3"),
            WebProviderModel(name: "Instant")
        ]
        config.manuallyAddedModels = ["custom-model"]

        #expect(config.allModels.contains("K3"))
        #expect(config.allModels.contains("Instant"))
        #expect(config.allModels.contains("custom-model"))
    }

    @Test func addCustomModelAppendsToManual() {
        var config = makeConfig()
        config.discoveredModels = [WebProviderModel(name: "K3")]

        config.addCustomModel("my-custom-model")

        #expect(config.manuallyAddedModels.contains("my-custom-model"))
        #expect(!config.discoveredModels.contains { $0.name == "my-custom-model" })
    }

    @Test func addCustomModelDedupsAgainstDiscovered() {
        var config = makeConfig()
        config.discoveredModels = [WebProviderModel(name: "K3")]

        config.addCustomModel("K3")

        #expect(config.manuallyAddedModels.isEmpty)
    }

    @Test func removeCustomModelOnlyRemovesManual() {
        var config = makeConfig()
        config.discoveredModels = [WebProviderModel(name: "K3")]
        config.manuallyAddedModels = ["custom"]

        config.removeCustomModel("custom")

        #expect(config.manuallyAddedModels.isEmpty)
        #expect(config.discoveredModels.contains { $0.name == "K3" })
    }

    @Test func discoveredModelsNotOverwrittenByAdd() {
        var config = makeConfig()
        config.discoveredModels = [WebProviderModel(name: "K3"), WebProviderModel(name: "Instant")]

        config.addCustomModel("new-model")

        #expect(config.discoveredModels.count == 2)
    }
}

@Suite("WebEffort fromLabel mapping")
struct WebEffortFromLabelTests {

    @Test func fromLabelEnglish() {
        #expect(WebEffort.fromLabel("High") == .high)
        #expect(WebEffort.fromLabel("Medium") == .medium)
        #expect(WebEffort.fromLabel("Low") == .low)
    }

    @Test func fromLabelRussian() {
        #expect(WebEffort.fromLabel("Высокий") == .high)
        #expect(WebEffort.fromLabel("Средний") == .medium)
        #expect(WebEffort.fromLabel("Низкий") == .low)
    }

    @Test func fromLabelAutoFast() {
        #expect(WebEffort.fromLabel("Auto") == .medium)
        #expect(WebEffort.fromLabel("Fast") == .low)
        #expect(WebEffort.fromLabel("Thinking") == .high)
    }

    @Test func fromLabelChinese() {
        #expect(WebEffort.fromLabel("深度思考") == .high)
        #expect(WebEffort.fromLabel("快速") == .low)
    }

    @Test func fromLabelUnknown() {
        #expect(WebEffort.fromLabel("unknown") == nil)
        #expect(WebEffort.fromLabel("") == nil)
    }

    @Test func effortDisplayNameUsesLocalization() {
        #expect(WebEffort.high.displayName != "high")
    }
}

@Suite("WebChatError descriptions")
struct WebChatErrorTests {

    @Test func modelNotFoundDescription() {
        let err = WebChatError.modelNotFound("GPT-5")
        #expect(err.errorDescription?.contains("GPT-5") == true)
    }

    @Test func modeNotFoundDescription() {
        let err = WebChatError.modeNotFound("Deep Research")
        #expect(err.errorDescription?.contains("Deep Research") == true)
    }

    @Test func noModelSelectorDescription() {
        let err = WebChatError.noModelSelector
        #expect(err.errorDescription != nil)
    }
}

@Suite("WebProviderCatalog selectors with new fields")
struct WebProviderCatalogEnhancedTests {

    @Test func qwenModelButtonExists() throws {
        let catalog = try WebProviderCatalog.loadBundled()
        let qwen = try #require(catalog.selectors(for: "qwen"))

        #expect(qwen.modelButton != nil)
        #expect(qwen.modelButton?.contains("ant-dropdown-trigger") == true)
    }

    @Test func kimiModelButtonExists() throws {
        let catalog = try WebProviderCatalog.loadBundled()
        let kimi = try #require(catalog.selectors(for: "kimi"))

        #expect(kimi.modelButton?.hasPrefix(".current-model") == true)
        #expect(kimi.effortDropdown?.contains("effort-item") == true)
    }

    @Test func newChatTextsForVendors() throws {
        let catalog = try WebProviderCatalog.loadBundled()
        let kimi = try #require(catalog.selectors(for: "kimi"))
        let qwen = try #require(catalog.selectors(for: "qwen"))

        #expect(kimi.newChatTexts?.contains("Новый чат") == true)
        #expect(qwen.newChatTexts?.contains("Начать") == true)
    }
}
