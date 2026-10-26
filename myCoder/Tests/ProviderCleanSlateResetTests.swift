import Foundation
import Testing
@testable import myCoder

@Suite("Provider clean slate")
struct ProviderCleanSlateResetTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "mycoder-cleanslate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("wipes provider rows, selections and credentials once")
    func wipesProviderStateOnce() {
        let defaults = makeDefaults()
        defaults.set("data", forKey: "com.mycoder.serverProviders")
        defaults.set("openai", forKey: "com.mycoder.selectedProviderID")
        defaults.set("gpt-4o", forKey: "com.mycoder.selectedModel")
        defaults.set("secret", forKey: "api_key_openai")
        defaults.set("secret", forKey: "secret_local-provider-password-x")
        defaults.set("keep", forKey: "com.mycoder.settings")

        #expect(ProviderCleanSlateReset.runIfNeeded(defaults: defaults))

        #expect(defaults.object(forKey: "com.mycoder.serverProviders") == nil)
        #expect(defaults.object(forKey: "com.mycoder.selectedProviderID") == nil)
        #expect(defaults.object(forKey: "com.mycoder.selectedModel") == nil)
        #expect(defaults.object(forKey: "api_key_openai") == nil)
        #expect(defaults.object(forKey: "secret_local-provider-password-x") == nil)
        // Unrelated preferences stay untouched.
        #expect(defaults.string(forKey: "com.mycoder.settings") == "keep")

        // The wipe happens exactly once.
        defaults.set("again", forKey: "com.mycoder.serverProviders")
        #expect(!ProviderCleanSlateReset.runIfNeeded(defaults: defaults))
        #expect(defaults.string(forKey: "com.mycoder.serverProviders") == "again")
    }

    @Test("tool-result fixes are part of the provider state")
    func wipesToolResultFixes() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "com.mycoder.toolResultFix.gpt-4o")
        ProviderCleanSlateReset.wipe(defaults: defaults)
        #expect(defaults.object(forKey: "com.mycoder.toolResultFix.gpt-4o") == nil)
    }
}

@Suite("Provider enablement store")
struct ProviderEnablementStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "mycoder-provider-enable-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("providers start enabled and can be switched off")
    func togglesProviderState() {
        let defaults = makeDefaults()
        #expect(!ProviderEnablementStore.isDisabled("server-1", defaults: defaults))
        ProviderEnablementStore.setDisabled(true, providerID: "server-1", defaults: defaults)
        #expect(ProviderEnablementStore.isDisabled("server-1", defaults: defaults))
        ProviderEnablementStore.setDisabled(false, providerID: "server-1", defaults: defaults)
        #expect(!ProviderEnablementStore.isDisabled("server-1", defaults: defaults))
        #expect(defaults.object(forKey: ProviderEnablementStore.storageKey) == nil)
    }

    @Test("removing a provider forgets its switch state")
    func clearsProviderState() {
        let defaults = makeDefaults()
        ProviderEnablementStore.setDisabled(true, providerID: "server-1", defaults: defaults)
        ProviderEnablementStore.clear(providerID: "server-1", defaults: defaults)
        #expect(!ProviderEnablementStore.isDisabled("server-1", defaults: defaults))
    }
}
