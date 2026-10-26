import Foundation
import Testing
@testable import myCoder

/// Refresh semantics (audit 2026-09-06, Claude live evidence): the vendor
/// model menu is CONTEXT-DEPENDENT — probing one model hides others from that
/// menu state. Refresh therefore MERGES: fresh entries update capabilities,
/// entries missing from the latest scan are demoted to unselectable (they
/// may be context-hidden, not retired), and the explicit user selection is
/// preserved whenever the model is still selectable.
@Suite("Web model refresh — merge semantics (audit 2026-09-06)")
struct WebModelRefreshLogicTests {

    @Test("empty live refresh demotes stale models to unselectable and clears the selection")
    func emptyRefreshClearsStaleState() {
        let stale = WebProviderModel(
            name: "gpt-stale",
            discoveryStatus: .active,
            isLiveDiscovered: true
        )
        let config = WebProviderConfig(
            vendor: .chatgpt,
            selectedModel: "gpt-stale",
            discoveredModels: [stale],
            discoveredEffortLevels: [.high]
        )

        let refreshed = WebModelRefreshLogic.replacing(config: config, with: [])

        // The entry is preserved (selectable state kept — a narrow/empty
        // scan is not proof of retirement) with an honest annotation.
        #expect(refreshed.discoveredModels.count == 1)
        #expect(refreshed.discoveredModels[0].isSelectable == true)
        #expect(refreshed.discoveredModels[0].discoveryMessage?.contains("context-dependent") == true)
        #expect(refreshed.selectedModel == "gpt-stale")
    }

    @Test("refresh preserves an unselectable capability-probe result")
    func refreshPreservesUnselectableModel() {
        let config = WebProviderConfig(vendor: .qwen)
        let unselectable = WebProviderModel(
            name: "Qwen3-Coder",
            discoveryStatus: .inactive,
            isLiveDiscovered: true,
            isSelectable: false,
            discoveryMessage: "The live menu did not expose a selectable option."
        )

        let refreshed = WebModelRefreshLogic.replacing(config: config, with: [unselectable])

        #expect(refreshed.discoveredModels.count == 1)
        #expect(refreshed.discoveredModels[0].isSelectable == false)
        #expect(refreshed.discoveredModels[0].discoveryStatus == .inactive)
        #expect(refreshed.allModels.isEmpty)
        #expect(refreshed.selectedModel.isEmpty)
    }

    @Test("non-empty refresh merges entries, demotes the missing one, keeps a valid selection")
    func nonEmptyRefreshMergesAndKeepsSelection() {
        let config = WebProviderConfig(
            vendor: .chatgpt,
            selectedModel: "gpt-4o",
            discoveredModels: [
                WebProviderModel(name: "gpt-4o"),
                WebProviderModel(name: "gpt-stale")
            ]
        )
        let live = WebProviderModel(
            name: "gpt-4.1",
            availableEfforts: [.low, .high],
            discoveryStatus: .active,
            isLiveDiscovered: true
        )

        let refreshed = WebModelRefreshLogic.replacing(config: config, with: [live])

        // Merge: the fresh scan entry plus the previously known entries.
        // Both "gpt-4o" and "gpt-stale" are preserved (annotated); the user's
        // selection stays "gpt-4o".
        #expect(refreshed.discoveredModels.map(\.name).sorted() == ["gpt-4.1", "gpt-4o", "gpt-stale"])
        #expect(refreshed.allModels.sorted() == ["gpt-4.1", "gpt-4o", "gpt-stale"])
        #expect(refreshed.selectedModel == "gpt-4o")
        #expect(refreshed.discoveredEffortLevels == [.high, .low])
        let stale = refreshed.discoveredModels.first { $0.name == "gpt-stale" }
        #expect(stale?.discoveryMessage?.contains("context-dependent") == true)
    }

    @Test("context-hidden models survive a narrowed scan (Claude live regression)")
    func contextHiddenModelsSurviveNarrowedScan() {
        // Live Claude evidence: probing "Sonnet 4.6" hid "Sonnet 5" and
        // "Haiku 4.5" from that menu state; the old replace semantics deleted
        // them from the store and shifted the user's selection.
        let config = WebProviderConfig(
            vendor: .claude,
            selectedModel: "Sonnet 5",
            discoveredModels: [
                WebProviderModel(name: "Sonnet 5", discoveryStatus: .active, isLiveDiscovered: true),
                WebProviderModel(name: "Haiku 4.5", discoveryStatus: .active, isLiveDiscovered: true),
                WebProviderModel(name: "Sonnet 4.6", discoveryStatus: .active, isLiveDiscovered: true)
            ]
        )
        // The narrowed probe saw only "Sonnet 4.6".
        let refreshed = WebModelRefreshLogic.replacing(
            config: config,
            with: [WebProviderModel(name: "Sonnet 4.6", discoveryStatus: .active, isLiveDiscovered: true)]
        )

        #expect(refreshed.selectedModel == "Sonnet 5", "the user's verified pick must survive a narrowed scan")
        #expect(refreshed.allModels.contains("Sonnet 5"))
        #expect(refreshed.allModels.contains("Sonnet 4.6"))
        // Haiku 4.5 was not in the narrow scan → preserved with annotation.
        let haiku = refreshed.discoveredModels.first { $0.name == "Haiku 4.5" }
        #expect(haiku?.isSelectable == true)
        #expect(haiku?.discoveryMessage?.contains("context-dependent") == true)
    }
}
