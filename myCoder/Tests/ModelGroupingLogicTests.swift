import Testing
import Foundation
@testable import myCoder

@Suite("Model grouping and capability badges")
struct ModelGroupingLogicTests {

    @Test func modelIdsSplitIntoPrefixAndName() {
        let prefixed = ModelGroupingLogic.splitModelID("oc/deepseek")
        #expect(prefixed.prefix == "oc")
        #expect(prefixed.name == "deepseek")

        let plain = ModelGroupingLogic.splitModelID("gpt-4")
        #expect(plain.prefix == nil)
        #expect(plain.name == "gpt-4")

        let emptyPrefix = ModelGroupingLogic.splitModelID("/gpt-4")
        #expect(emptyPrefix.prefix == nil)
        #expect(emptyPrefix.name == "gpt-4")
    }

    @Test func modelsAreGroupedByPrefixInFirstSeenOrder() {
        let groups = ModelGroupingLogic.groupedModels([
            "oc/deepseek",
            "gpt-4",
            "oc/gpt-4",
        ])
        #expect(groups.count == 2)
        #expect(groups[0].prefix == "oc")
        #expect(groups[0].models == ["oc/deepseek", "oc/gpt-4"])
        #expect(groups[1].prefix == nil)
        #expect(groups[1].models == ["gpt-4"])
    }

    @Test func groupKeysSeparateProvidersAndPrefixes() {
        #expect(ModelGroupingLogic.groupKey(prefix: "oc", providerID: "p1") == "p1::oc")
        #expect(ModelGroupingLogic.groupKey(prefix: nil, providerID: "p1") == "p1::__all__")
        #expect(ModelGroupingLogic.groupKey(prefix: "oc", providerID: "p1") != ModelGroupingLogic.groupKey(prefix: "oc", providerID: "p2"))
    }

    @Test func badgesReflectReportedCapabilities() {
        let providers = [
            MimoProviderResponse(
                id: "p1",
                name: "Provider",
                models: [
                    "thinking-model": MimoProviderModel(
                        id: "thinking-model",
                        capabilities: MimoModelCapabilities(
                            reasoning: true,
                            toolcall: true,
                            plan: false,
                            vision: true,
                            imagegen: false
                        ),
                        limit: MimoModelLimit(context: 200_000, output: 64_000)
                    ),
                    "plain-model": MimoProviderModel(
                        id: "plain-model",
                        capabilities: MimoModelCapabilities(reasoning: false, toolcall: false, plan: false)
                    ),
                ]
            )
        ]

        let badges = ModelCapabilityLogic.badges(for: "thinking-model", in: providers, providerID: "p1")
        #expect(badges.map(\.kind) == [.thinking, .tools, .vision])
        #expect(badges.allSatisfy { !$0.label.isEmpty })

        let plain = ModelCapabilityLogic.badges(for: "plain-model", in: providers, providerID: "p1")
        #expect(plain.isEmpty)

        let unknown = ModelCapabilityLogic.badges(for: "missing", in: providers, providerID: "p1")
        #expect(unknown.isEmpty)
    }

    @Test func contextWindowIsReadFromTheModelMetadata() {
        let providers = [
            MimoProviderResponse(
                id: "p1",
                name: "Provider",
                models: [
                    "m": MimoProviderModel(id: "m", limit: MimoModelLimit(context: 1_000_000, output: nil))
                ]
            )
        ]
        #expect(ModelCapabilityLogic.contextWindow(for: "m", in: providers, providerID: "p1") == 1_000_000)
        #expect(ModelCapabilityLogic.contextWindow(for: "other", in: providers, providerID: "p1") == nil)
    }

    @Test func contextLabelsUseCompactUnits() {
        #expect(ModelCapabilityLogic.contextLabel(for: 200_000) == "200k")
        #expect(ModelCapabilityLogic.contextLabel(for: 1_000_000) == "1M")
        #expect(ModelCapabilityLogic.contextLabel(for: 1_500_000) == "1.5M")
        #expect(ModelCapabilityLogic.contextLabel(for: 0) == "")
    }

    @Test func modelsShareAFamilyKey() {
        #expect(ModelGroupingLogic.familyKey(for: "codegemma-1.1-7b") == "codegemma")
        #expect(ModelGroupingLogic.familyKey(for: "codegemma-7b") == "codegemma")
        #expect(ModelGroupingLogic.familyKey(for: "codegemma-7b-instruct") == "codegemma")
        #expect(ModelGroupingLogic.familyKey(for: "codellama-70b") == "codellama")
        #expect(ModelGroupingLogic.familyKey(for: "codestral-22b-instruct-v0.1") == "codestral")
        #expect(ModelGroupingLogic.familyKey(for: "deepseek-coder-6.7b-instruct") == "deepseek")
        #expect(ModelGroupingLogic.familyKey(for: "deepseek-v4.1-flash") == "deepseek")
        #expect(ModelGroupingLogic.familyKey(for: "dbrx-instruct") == "dbrx")
        #expect(ModelGroupingLogic.familyKey(for: "arctic-embed-1") == "arctic")
        // A version glued to the name is a new model line.
        #expect(ModelGroupingLogic.familyKey(for: "qwen3.8-27b-coder") == "qwen3.8")
        #expect(ModelGroupingLogic.familyKey(for: "qwen3-32b") == "qwen3")
        #expect(ModelGroupingLogic.familyKey(for: "ollama/qwen3-32b") == "qwen3")
        #expect(ModelGroupingLogic.familyKey(for: "ai-synthetic-video-detector") == "ai-synthetic-video-detector")
    }

    @Test func modelsAreGroupedByFamily() {
        let groups = ModelGroupingLogic.groupedByFamily([
            "codegemma-1.1-7b",
            "arctic-embed-1",
            "codegemma-7b",
        ])
        #expect(groups.count == 2)
        #expect(groups[0].family == "codegemma")
        #expect(groups[0].models == ["codegemma-1.1-7b", "codegemma-7b"])
        #expect(groups[1].family == "arctic")
        #expect(groups[1].models == ["arctic-embed-1"])
    }

    @Test func sizeAndVersionMarkersAreRecognized() {
        #expect(ModelGroupingLogic.isSizeToken("7b"))
        #expect(ModelGroupingLogic.isSizeToken("1.5b"))
        #expect(ModelGroupingLogic.isSizeToken("a3b"))
        #expect(!ModelGroupingLogic.isSizeToken("b"))
        #expect(!ModelGroupingLogic.isSizeToken("coder"))
        #expect(ModelGroupingLogic.isVersionToken("1.1"))
        #expect(ModelGroupingLogic.isVersionToken("v4.1"))
        #expect(!ModelGroupingLogic.isVersionToken("o1"))
    }

    @Test func effectiveLimitsFallBackToTheDefaults() {
        let providers = [
            MimoProviderResponse(
                id: "p1",
                name: "Provider",
                models: [
                    "m": MimoProviderModel(id: "m", limit: MimoModelLimit(context: 1_000_000, output: nil))
                ]
            )
        ]
        #expect(ModelCapabilityLogic.effectiveContextWindow(for: "m", in: providers, providerID: "p1") == 1_000_000)
        #expect(ModelCapabilityLogic.effectiveContextWindow(for: "other", in: providers, providerID: "p1") == 200_000)
        #expect(ModelCapabilityLogic.effectiveOutputLimit(for: "m", in: providers, providerID: "p1") == 32_000)
    }
}
