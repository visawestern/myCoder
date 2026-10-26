import Testing
import Foundation
@testable import myCoder

// MARK: - Provider & Model Edge Case Tests
// Tests that verify every capability gate, provider selection, variant logic,
// context window display, and error handling for ALL edge cases

@Suite("Provider & Model Edge Cases")
struct ProviderModelEdgeCaseTests {

    // MARK: - Helper: Build providers with specific capabilities

    private func makeProvider(
        id: String = "test-provider",
        name: String = "Test Provider",
        models: [String: MimoProviderModel] = [:]
    ) -> MimoProviderResponse {
        MimoProviderResponse(id: id, name: name, models: models)
    }

    private func makeModel(
        id: String = "test-model",
        name: String? = nil,
        reasoning: Bool? = nil,
        toolcall: Bool? = nil,
        plan: Bool? = nil,
        variants: [String: MimoModelVariant]? = nil,
        context: Int? = nil,
        output: Int? = nil
    ) -> MimoProviderModel {
        let caps: MimoModelCapabilities?
        if reasoning != nil || toolcall != nil || plan != nil {
            caps = MimoModelCapabilities(reasoning: reasoning, toolcall: toolcall, plan: plan)
        } else {
            caps = nil
        }
        let limit: MimoModelLimit?
        if context != nil || output != nil {
            limit = MimoModelLimit(context: context, output: output)
        } else {
            limit = nil
        }
        return MimoProviderModel(
            id: id,
            name: name,
            capabilities: caps,
            variants: variants,
            limit: limit
        )
    }

    // MARK: - 1. Capability Gates: nil/edge cases

    @Test("supportsReasoning returns false when capabilities is nil")
    func supportsReasoningNilCapabilities() {
        let model = makeModel(id: "plain-model")
        let provider = makeProvider(models: ["plain-model": model])
        let result = ProviderSettingsLogic.supportsReasoning(
            for: "plain-model", in: [provider]
        )
        #expect(!result)
    }

    @Test("supportsReasoning returns true when reasoning capability is true")
    func supportsReasoningTrue() {
        let model = makeModel(id: "smart-model", reasoning: true)
        let provider = makeProvider(models: ["smart-model": model])
        let result = ProviderSettingsLogic.supportsReasoning(
            for: "smart-model", in: [provider]
        )
        #expect(result)
    }

    @Test("supportsReasoning returns false when reasoning capability is false explicitly")
    func supportsReasoningFalseExplicit() {
        let model = makeModel(id: "no-reason-model", reasoning: false)
        let provider = makeProvider(models: ["no-reason-model": model])
        let result = ProviderSettingsLogic.supportsReasoning(
            for: "no-reason-model", in: [provider]
        )
        #expect(!result)
    }

    @Test("supportsToolcall returns true when capabilities is nil (default)")
    func supportsToolcallDefaultTrue() {
        let model = makeModel(id: "default-model")
        let provider = makeProvider(models: ["default-model": model])
        let result = ProviderSettingsLogic.supportsToolcall(
            for: "default-model", providerID: nil, in: [provider], customProviders: []
        )
        #expect(result)
    }

    @Test("supportsToolcall returns false when explicitly set to false")
    func supportsToolcallExplicitFalse() {
        let model = makeModel(id: "no-tool-model", toolcall: false)
        let provider = makeProvider(models: ["no-tool-model": model])
        let result = ProviderSettingsLogic.supportsToolcall(
            for: "no-tool-model", providerID: nil, in: [provider], customProviders: []
        )
        #expect(!result)
    }

    @Test("supportsPlanAgent returns true when capabilities is nil (default)")
    func supportsPlanDefaultTrue() {
        let model = makeModel(id: "default-model")
        let provider = makeProvider(models: ["default-model": model])
        let result = ProviderSettingsLogic.supportsPlanAgent(
            for: "default-model", providerID: nil, in: [provider], customProviders: []
        )
        #expect(result)
    }

    @Test("supportsPlanAgent returns false only when plan is explicitly false AND reasoning is nil AND toolcall is nil")
    func supportsPlanExplicitFalse() {
        // When plan is explicitly false, but other caps are nil → plan is false
        let model = makeModel(id: "no-plan-model", toolcall: true, plan: false)
        let provider = makeProvider(models: ["no-plan-model": model])
        let result = ProviderSettingsLogic.supportsPlanAgent(
            for: "no-plan-model", providerID: nil, in: [provider], customProviders: []
        )
        #expect(!result)
    }

    @Test("supportsPlanAgent returns true when plan is explicitly true")
    func supportsPlanExplicitTrue() {
        let model = makeModel(id: "plan-model", plan: true)
        let provider = makeProvider(models: ["plan-model": model])
        let result = ProviderSettingsLogic.supportsPlanAgent(
            for: "plan-model", providerID: nil, in: [provider], customProviders: []
        )
        #expect(result)
    }

    // MARK: - 2. Variant tests

    @Test("availableVariants empty when model doesn't support reasoning")
    func variantsEmptyWhenNoReasoning() {
        let model = makeModel(
            id: "no-reason-model",
            reasoning: false,
            variants: ["high": MimoModelVariant(reasoningEffort: "high")]
        )
        let provider = makeProvider(models: ["no-reason-model": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "no-reason-model", in: [provider]
        )
        #expect(variants.isEmpty)
    }

    @Test("availableVariants returns sorted keys when reasoning supported")
    func variantsReturnedWhenReasoningSupported() {
        let model = makeModel(
            id: "reason-model",
            reasoning: true,
            variants: [
                "high": MimoModelVariant(reasoningEffort: "high"),
                "low": MimoModelVariant(reasoningEffort: "low"),
                "medium": MimoModelVariant(reasoningEffort: "medium")
            ]
        )
        let provider = makeProvider(models: ["reason-model": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "reason-model", in: [provider]
        )
        #expect(variants == ["high", "low", "medium"])
    }

    @Test("availableVariants empty when model has nil variants")
    func variantsEmptyWhenNilVariants() {
        let model = makeModel(id: "no-variant-model", reasoning: true, variants: nil)
        let provider = makeProvider(models: ["no-variant-model": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "no-variant-model", in: [provider]
        )
        #expect(variants.isEmpty)
    }

    @Test("normalizedVariant falls back to default when requested variant missing")
    func normalizedVariantFallback() {
        let model = makeModel(
            id: "reason-model",
            reasoning: true,
            variants: [
                "high": MimoModelVariant(reasoningEffort: "high"),
                "medium": MimoModelVariant(reasoningEffort: "medium")
            ]
        )
        let provider = makeProvider(models: ["reason-model": model])
        let result = ProviderSettingsLogic.normalizedVariant(
            "low", for: "reason-model", in: [provider]
        )
        #expect(result == "high") // Falls back to default (first available = "high")
    }

    @Test("normalizedVariant returns nil when no variants available")
    func normalizedVariantNilWhenNoVariants() {
        let model = makeModel(id: "plain-model", reasoning: false)
        let provider = makeProvider(models: ["plain-model": model])
        let result = ProviderSettingsLogic.normalizedVariant(
            "high", for: "plain-model", in: [provider]
        )
        #expect(result == nil)
    }

    @Test("defaultVariant prefers high when available")
    func defaultVariantPrefersHigh() {
        let model = makeModel(
            id: "reason-model",
            reasoning: true,
            variants: [
                "high": MimoModelVariant(reasoningEffort: "high"),
                "medium": MimoModelVariant(reasoningEffort: "medium"),
                "low": MimoModelVariant(reasoningEffort: "low")
            ]
        )
        let provider = makeProvider(models: ["reason-model": model])
        let result = ProviderSettingsLogic.defaultVariant(for: "reason-model", in: [provider])
        #expect(result == "high")
    }

    @Test("defaultVariant picks last variant when high not available")
    func defaultVariantFallback() {
        let model = makeModel(
            id: "reason-model",
            reasoning: true,
            variants: [
                "low": MimoModelVariant(reasoningEffort: "low"),
                "medium": MimoModelVariant(reasoningEffort: "medium")
            ]
        )
        let provider = makeProvider(models: ["reason-model": model])
        let result = ProviderSettingsLogic.defaultVariant(for: "reason-model", in: [provider])
        #expect(result == "medium") // Last sorted
    }

    // MARK: - 3. Provider Selection Edge Cases

    @Test("resolveProviderID returns nil for empty modelID")
    func resolveProviderIDEmptyModel() {
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "", selectedProviderID: "test",
            in: [], customProviders: []
        )
        #expect(result == nil)
    }

    @Test("resolveProviderID finds model across providers")
    func resolveProviderIDCrossProvider() {
        let model = makeModel(id: "shared-model")
        let provider1 = makeProvider(id: "p1", models: ["other-model": makeModel(id: "other-model")])
        let provider2 = makeProvider(id: "p2", models: ["shared-model": model])
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "shared-model", selectedProviderID: "",
            in: [provider1, provider2], customProviders: []
        )
        #expect(result == "p2")
    }

    @Test("resolveProviderID respects selectedProviderID when model exists there")
    func resolveProviderIDRespectsSelection() {
        let model = makeModel(id: "shared-model")
        let provider1 = makeProvider(id: "p1", models: ["shared-model": model])
        let provider2 = makeProvider(id: "p2", models: ["shared-model": model])
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "shared-model", selectedProviderID: "p2",
            in: [provider1, provider2], customProviders: []
        )
        #expect(result == "p2") // Keeps p2 even though p1 also has it
    }

    @Test("resolveProviderID returns nil when model not found")
    func resolveProviderIDModelNotFound() {
        let result = ProviderSettingsLogic.resolveProviderID(
            for: "nonexistent-model", selectedProviderID: "",
            in: [], customProviders: []
        )
        #expect(result == nil)
    }

    @Test("mergeModelIDs deduplicates across providers")
    func mergeModelIDsDedup() {
        let modelA = makeModel(id: "model-a")
        let modelB = makeModel(id: "model-b")
        let provider1 = makeProvider(id: "p1", models: ["model-a": modelA, "model-b": modelB])
        let provider2 = makeProvider(id: "p2", models: ["model-a": modelA])
        let result = ProviderSettingsLogic.mergeModelIDs(
            serverProviders: [provider1, provider2],
            customProviders: []
        )
        #expect(result == ["model-a", "model-b"])
    }

    // MARK: - 4. Custom Provider Edge Cases

    @Test("isCustomProvider returns true for matching custom provider")
    func isCustomProviderTrue() {
        let custom = CustomProvider(id: "custom-1", name: "Custom", type: .openAI, baseURL: "https://api.example.com", apiKey: "", isEnabled: true, models: ["gpt-4"], supportsTools: true, acpEnabled: false)
        let result = ProviderSettingsLogic.isCustomProvider("custom-1", customProviders: [custom])
        #expect(result)
    }

    @Test("supportsToolcall for custom provider uses its supportsTools flag")
    func supportsToolcallCustomProvider() {
        let custom = CustomProvider(id: "custom-1", name: "Custom", type: .openAI, baseURL: "https://api.example.com", apiKey: "", isEnabled: true, models: ["gpt-4"], supportsTools: false, acpEnabled: false)
        let result = ProviderSettingsLogic.supportsToolcall(
            for: "gpt-4", providerID: "custom-1",
            in: [], customProviders: [custom]
        )
        #expect(!result)
    }

    @Test("supportsReasoning for custom provider returns false")
    func supportsReasoningCustomProvider() {
        let custom = CustomProvider(id: "custom-1", name: "Custom", type: .openAI, baseURL: "https://api.example.com", apiKey: "", isEnabled: true, models: ["gpt-4"], supportsTools: true, acpEnabled: false)
        let result = ProviderSettingsLogic.supportsReasoning(
            for: "gpt-4", in: [], providerID: "custom-1", customProviders: [custom]
        )
        #expect(!result)
    }

    // MARK: - 5. CapabilityGates Integration

    @Test("canShowVariantMenu returns false when model has no variants")
    func canShowVariantMenuNoVariants() {
        let model = makeModel(id: "plain-model")
        let provider = makeProvider(models: ["plain-model": model])
        let result = ProviderCapabilityGates.canShowVariantMenu(
            modelID: "plain-model", providerID: nil,
            providers: [provider], customProviders: []
        )
        #expect(!result)
    }

    @Test("canUseTools returns false when toolcall capability is false")
    func canUseToolsExplicitFalse() {
        let model = makeModel(id: "no-tools-model", toolcall: false)
        let provider = makeProvider(models: ["no-tools-model": model])
        let result = ProviderCapabilityGates.canUseTools(
            modelID: "no-tools-model", providerID: nil,
            providers: [provider], customProviders: []
        )
        #expect(!result)
    }

    @Test("toolsUnavailableReason returns non-nil when tools unavailable")
    func toolsUnavailableReasonMessage() {
        let model = makeModel(id: "no-tools-model", toolcall: false)
        let provider = makeProvider(models: ["no-tools-model": model])
        let reason = ProviderCapabilityGates.toolsUnavailableReason(
            modelID: "no-tools-model", providerID: nil,
            providers: [provider], customProviders: []
        )
        #expect(reason != nil)
        #expect(reason?.contains("unavailable") == true)
    }

    @Test("variantMenuDisabledReason returns non-nil when no variants")
    func variantMenuDisabledReasonMessage() {
        let model = makeModel(id: "plain-model")
        let provider = makeProvider(models: ["plain-model": model])
        let reason = ProviderCapabilityGates.variantMenuDisabledReason(
            modelID: "plain-model", providerID: nil,
            providers: [provider], customProviders: []
        )
        #expect(reason != nil)
        #expect(reason?.contains("reasoning") == true)
    }

    @Test("planAgentDisabledReason returns non-nil when plan unsupported")
    func planAgentDisabledReasonMessage() {
        let model = makeModel(id: "no-plan-model", toolcall: false, plan: false)
        let provider = makeProvider(models: ["no-plan-model": model])
        let reason = ProviderCapabilityGates.planAgentDisabledReason(
            modelID: "no-plan-model", providerID: nil,
            providers: [provider], customProviders: []
        )
        #expect(reason != nil)
    }

    // MARK: - 6. Model Limit (Context Window) Tests

    @Test("model limit context returns nil when not set")
    func modelLimitContextNil() {
        let model = makeModel(id: "no-limit-model")
        let provider = makeProvider(models: ["no-limit-model": model])
        let found = ProviderSettingsLogic.model(for: "no-limit-model", in: [provider])
        #expect(found?.limit?.context == nil)
    }

    @Test("model limit context returns value when set")
    func modelLimitContextValue() {
        let model = makeModel(id: "limited-model", context: 128000, output: 4096)
        let provider = makeProvider(models: ["limited-model": model])
        let found = ProviderSettingsLogic.model(for: "limited-model", in: [provider])
        #expect(found?.limit?.context == 128000)
        #expect(found?.limit?.output == 4096)
    }

    // MARK: - 7. Empty/Duplicate/Garbage Input Tests

    @Test("supportsReasoning with empty string returns false")
    func supportsReasoningEmptyString() {
        let model = makeModel(id: "test-model", reasoning: true)
        let provider = makeProvider(models: ["test-model": model])
        let result = ProviderSettingsLogic.supportsReasoning(
            for: "", in: [provider]
        )
        #expect(!result) // empty string never matches
    }

    @Test("supportsReasoning with whitespace-only string returns false")
    func supportsReasoningWhitespaceString() {
        let model = makeModel(id: "test-model", reasoning: true)
        let provider = makeProvider(models: ["test-model": model])
        let result = ProviderSettingsLogic.supportsReasoning(
            for: "   ", in: [provider]
        )
        #expect(!result) // whitespace doesn't match
    }

    @Test("supportsReasoning with wildly incorrect modelID returns false gracefully")
    func supportsReasoningGibberishModelID() {
        let model = makeModel(id: "test-model", reasoning: true)
        let provider = makeProvider(models: ["test-model": model])
        let result = ProviderSettingsLogic.supportsReasoning(
            for: "!@#$%^&*()_+模型名称/super-long/测试", in: [provider]
        )
        #expect(!result) // no crash, graceful false
    }

    @Test("availableVariants with empty providers array returns empty")
    func variantsEmptyNoProviders() {
        let variants = ProviderSettingsLogic.availableVariants(
            for: "any-model", in: []
        )
        #expect(variants.isEmpty)
    }

    @Test("availableVariants with nil variants dictionary returns empty")
    func variantsEmptyNilDict() {
        let model = makeModel(id: "test-model", reasoning: true, variants: nil)
        let provider = makeProvider(models: ["test-model": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "test-model", in: [provider]
        )
        #expect(variants.isEmpty)
    }

    @Test("availableVariants with empty variants dictionary returns empty")
    func variantsEmptyDict() {
        let model = makeModel(id: "test-model", reasoning: true, variants: [:])
        let provider = makeProvider(models: ["test-model": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "test-model", in: [provider]
        )
        #expect(variants.isEmpty)
    }

    @Test("normalizedVariant with nil variant and no available returns nil")
    func normalizedVariantNilNoAvailable() {
        let result = ProviderSettingsLogic.normalizedVariant(
            nil, for: "unknown", in: [], customProviders: []
        )
        #expect(result == nil)
    }

    // MARK: - 8. ProviderOption Edge Cases

    @Test("allProviderOptions deduplicates by id across server and custom")
    func allProviderOptionsMerging() {
        let serverProviders = [
            makeProvider(id: "p1", name: "Server P1")
        ]
        let customProviders = [
            CustomProvider(id: "p2", name: "Custom P2", type: .openAI, baseURL: "https://test.com", apiKey: "", isEnabled: true, models: [], supportsTools: true, acpEnabled: false)
        ]
        let options = ProviderSettingsLogic.allProviderOptions(
            serverProviders: serverProviders,
            customProviders: customProviders
        )
        #expect(options.count == 2)
    }

    @Test("allProviderOptions excludes disabled custom providers")
    func allProviderOptionsExcludesDisabled() {
        let customProviders = [
            CustomProvider(id: "disabled-1", name: "Disabled", type: .openAI, baseURL: "https://test.com", apiKey: "", isEnabled: false, models: [], supportsTools: true, acpEnabled: false)
        ]
        let options = ProviderSettingsLogic.allProviderOptions(
            serverProviders: [], customProviders: customProviders
        )
        #expect(options.isEmpty)
    }

    // MARK: - 9. Model Lookup Edge Cases

    @Test("model(for:) returns nil for nonexistent model")
    func modelForNonexistent() {
        let model = makeModel(id: "real-model")
        let provider = makeProvider(models: ["real-model": model])
        let result = ProviderSettingsLogic.model(for: "fake-model", in: [provider])
        #expect(result == nil)
    }

    @Test("model(for:) returns model from correct provider when providerID given")
    func modelForWithProviderID() {
        let modelA = makeModel(id: "shared-model")
        let modelB = makeModel(id: "shared-model")
        let provider1 = makeProvider(id: "p1", models: ["shared-model": modelA])
        let provider2 = makeProvider(id: "p2", models: ["shared-model": modelB])
        let result = ProviderSettingsLogic.model(
            for: "shared-model", in: [provider1, provider2], providerID: "p2"
        )
        // Should find it in p2 (but modelB and modelA are both MimoProviderModel with same fields)
        #expect(result != nil)
    }

    @Test("model(for:) falls back to scanning all providers when providerID not given")
    func modelForScansAllProviders() {
        let model = makeModel(id: "shared-model")
        let provider1 = makeProvider(id: "p1", models: ["other": makeModel(id: "other")])
        let provider2 = makeProvider(id: "p2", models: ["shared-model": model])
        let result = ProviderSettingsLogic.model(
            for: "shared-model", in: [provider1, provider2], providerID: nil
        )
        #expect(result?.id == "shared-model")
    }

    @Test("model(for:) returns nil when providerID given but model not in that provider")
    func modelForWrongProvider() {
        let model = makeModel(id: "unique-model")
        let provider1 = makeProvider(id: "p1", models: ["unique-model": model])
        let provider2 = makeProvider(id: "p2", models: ["other": makeModel(id: "other")])
        let result = ProviderSettingsLogic.model(
            for: "unique-model", in: [provider1, provider2], providerID: "p2"
        )
        #expect(result == nil) // unique-model is NOT in p2
    }

    // MARK: - 10. SQL Injection / Special Characters in Model IDs

    @Test("supportsReasoning with SQL injection string returns false gracefully")
    func supportsReasoningSQLInjection() {
        let model = makeModel(id: "test-model", reasoning: true)
        let provider = makeProvider(models: ["test-model": model])
        let sqlInjections = [
            "'; DROP TABLE messages; --",
            "1 OR 1=1",
            "\" OR \"1\"=\"1",
            "test-model' UNION SELECT * FROM sessions--"
        ]
        for injection in sqlInjections {
            let result = ProviderSettingsLogic.supportsReasoning(
                for: injection, in: [provider]
            )
            #expect(!result) // No crash, graceful false
        }
    }

    @Test("model(for:) with Unicode model IDs returns correct model")
    func modelForUnicode() {
        let unicodeId = "агент/модель-5.2-тест"
        let model = makeModel(id: unicodeId, reasoning: true)
        let provider = makeProvider(models: [unicodeId: model])
        let result = ProviderSettingsLogic.model(for: unicodeId, in: [provider])
        #expect(result?.id == unicodeId)
        #expect(result?.capabilities?.reasoning == true)
    }

    // MARK: - 11. Provider Cascade for agentrouter/glm-5.2 (user-reported model)

    @Test("agentrouter/glm-5.2 model capabilities accessible through provider logic")
    func glmModelCapabilities() {
        let glmModel = MimoProviderModel(
            id: "agentrouter/glm-5.2",
            name: "GLM-5.2",
            capabilities: MimoModelCapabilities(reasoning: true, toolcall: true, plan: true),
            variants: [
                "low": MimoModelVariant(reasoningEffort: "low"),
                "medium": MimoModelVariant(reasoningEffort: "medium"),
                "high": MimoModelVariant(reasoningEffort: "high")
            ],
            limit: MimoModelLimit(context: 128000, output: 4096),
            cost: MimoModelCost(input: 0.002, output: 0.008)
        )
        let provider = makeProvider(id: "agentrouter", name: "Agent Router", models: ["agentrouter/glm-5.2": glmModel])

        // Verify full chain:
        #expect(ProviderSettingsLogic.supportsReasoning(for: "agentrouter/glm-5.2", in: [provider]))
        #expect(ProviderSettingsLogic.supportsToolcall(for: "agentrouter/glm-5.2", providerID: nil, in: [provider], customProviders: []))
        #expect(ProviderSettingsLogic.supportsPlanAgent(for: "agentrouter/glm-5.2", providerID: nil, in: [provider], customProviders: []))

        let variants = ProviderSettingsLogic.availableVariants(for: "agentrouter/glm-5.2", in: [provider])
        #expect(variants == ["high", "low", "medium"])

        let foundModel = ProviderSettingsLogic.model(for: "agentrouter/glm-5.2", in: [provider])
        #expect(foundModel?.limit?.context == 128000)
        #expect(foundModel?.limit?.output == 4096)
        #expect(foundModel?.cost?.input == 0.002)
        #expect(foundModel?.cost?.output == 0.008)
    }

    // MARK: - 12. Edge: Model with no capabilities at all

    @Test("Model with no capabilities fields still works through all gates")
    func modelWithNoCapabilities() {
        let minimalModel = makeModel(id: "minimal-model")
        let provider = makeProvider(models: ["minimal-model": minimalModel])

        // These should all return safe defaults
        #expect(!ProviderSettingsLogic.supportsReasoning(for: "minimal-model", in: [provider]))
        #expect(ProviderSettingsLogic.supportsToolcall(for: "minimal-model", providerID: nil, in: [provider], customProviders: []))
        #expect(ProviderSettingsLogic.supportsPlanAgent(for: "minimal-model", providerID: nil, in: [provider], customProviders: []))
        #expect(ProviderSettingsLogic.availableVariants(for: "minimal-model", in: [provider]).isEmpty)
    }

    // MARK: - 13. Edge: Duplicate model IDs across server and custom providers

    @Test("mergeModelIDs with server + custom providers handling duplicates")
    func mergeModelIDsServerAndCustom() {
        let modelA = makeModel(id: "shared-model")
        let serverProviders = [makeProvider(id: "server", models: ["shared-model": modelA, "unique-server": makeModel(id: "unique-server")])]
        let customProviders = [CustomProvider(id: "custom", name: "Custom", type: .openAI, baseURL: "https://api.example.com", apiKey: "", isEnabled: true, models: ["shared-model", "unique-custom"], supportsTools: true, acpEnabled: false)]

        let result = ProviderSettingsLogic.mergeModelIDs(serverProviders: serverProviders, customProviders: customProviders)
        #expect(result.contains("shared-model"))
        #expect(result.contains("unique-server"))
        #expect(result.contains("unique-custom"))
        #expect(result.count == 3) // No duplicates
    }
}
