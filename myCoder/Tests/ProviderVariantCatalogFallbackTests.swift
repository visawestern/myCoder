import Testing
import Foundation
@testable import myCoder

/// Селект effort (варианты) в панели отправки должен показываться и для
/// моделей, чей провайдер сам не сообщает варианты, — из встроенного
/// каталога метаданных (например mercury-3 → low/medium/high).
/// Директива 2026-10-30: «у mercury-3 несколько видов эффорта, а в
/// панели нет селекта».
@MainActor
@Suite("Варианты модели: fallback на каталог метаданных")
struct ProviderVariantCatalogFallbackTests {

    @Test("Варианты из серверного каталога имеют приоритет")
    func serverVariantsWin() {
        let model = MimoProviderModel(
            id: "mercury-3",
            name: "Mercury 3",
            capabilities: MimoModelCapabilities(reasoning: true, toolcall: true, plan: nil, vision: nil, imagegen: nil),
            variants: ["max": MimoModelVariant(reasoningEffort: "max")]
        )
        let provider = MimoProviderResponse(id: "p1", name: "P", models: ["mercury-3": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "mercury-3", in: [provider], providerID: "p1"
        )
        #expect(variants == ["max"])
    }

    @Test("Fallback на каталог: mercury-3 известен без серверных вариантов")
    func catalogFallbackProvidesEfforts() {
        let model = MimoProviderModel(
            id: "mercury-3",
            name: "Mercury 3",
            capabilities: MimoModelCapabilities(reasoning: true, toolcall: true, plan: nil, vision: nil, imagegen: nil),
            variants: nil
        )
        let provider = MimoProviderResponse(id: "p1", name: "P", models: ["mercury-3": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "mercury-3", in: [provider], providerID: "p1"
        )
        #expect(variants.contains("low"))
        #expect(variants.contains("medium"))
        #expect(variants.contains("high"))
    }

    @Test("Неизвестная модели без каталога остаётся без вариантов")
    func unknownModelHasNoVariants() {
        let model = MimoProviderModel(
            id: "totally-unknown-model-xyz",
            name: "Unknown",
            capabilities: MimoModelCapabilities(reasoning: true, toolcall: true, plan: nil, vision: nil, imagegen: nil),
            variants: nil
        )
        let provider = MimoProviderResponse(id: "p1", name: "P", models: ["totally-unknown-model-xyz": model])
        let variants = ProviderSettingsLogic.availableVariants(
            for: "totally-unknown-model-xyz", in: [provider], providerID: "p1"
        )
        #expect(variants.isEmpty)
    }
}
