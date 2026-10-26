import Testing
import Foundation
@testable import myCoder

/// Round 30b user report: with a vendor already configured, the vendor tile in
/// Settings did NOTHING on click (`guard !providers.contains else { return }`)
/// and there was no "Add account" button anywhere — even though
/// /api/add-account supports cloning. Adding another account of the same
/// vendor must clone settings under a NEW id/name with a clean session state.
@Suite("Round 30b — web account cloning logic")
struct WebAccountCloneLogicTests {

    @Test("first vendor config is created fresh")
    func firstConfigFresh() {
        let result = WebAccountCloneLogic.next(for: .qwen, in: [])
        #expect(result.isNewDefault)
        #expect(result.config.vendor == .qwen)
    }

    @Test("second account clones the last config with a new id and clean session")
    func secondAccountClones() {
        var source = WebProviderConfig(vendor: .qwen)
        source.displayName = "Qwen"
        source.selectedModel = "Qwen3.8-Max"
        source.activeSessionID = "sess-old"
        source.activeSessionName = "old login"
        source.discoveredModels = [WebProviderModel(name: "Qwen3.7-Plus")]

        let outcome = WebAccountCloneLogic.next(for: .qwen, in: [source])
        #expect(!outcome.isNewDefault)
        let clone = outcome.config
        #expect(clone.id != source.id, "clone must have its own id")
        #expect(clone.vendor == .qwen)
        #expect(clone.chatURL == source.chatURL, "settings are inherited")
        #expect(clone.transport == source.transport)
        #expect(clone.displayName == "Qwen (Account 2)", "got \(clone.displayName)")
        #expect(clone.selectedModel.isEmpty, "new account starts unbound")
        #expect(clone.activeSessionID == nil && clone.activeSessionName == nil,
                "session/cookies must NOT be copied to the new account")
    }

    @Test("n-th clone numbering follows existing accounts")
    func numberingFollowsExisting() {
        var first = WebProviderConfig(vendor: .kimi)
        first.displayName = "Kimi"
        let second = WebAccountCloneLogic.next(for: .kimi, in: [first]).config
        #expect(second.displayName == "Kimi (Account 2)")
        let third = WebAccountCloneLogic.next(for: .kimi, in: [first, second]).config
        #expect(third.displayName == "Kimi (Account 3)")
        #expect(third.id != second.id)
    }
}
