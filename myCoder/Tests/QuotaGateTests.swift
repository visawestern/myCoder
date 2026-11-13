import Foundation
import Testing
@testable import myCoder

/// TDD for quota limits (directive 2026-11-13): per-model request limits,
/// provider-wide cross-chat request limits, per-API-key limits, token quotas
/// (e.g. Google ~250k tokens/min), and API-key pools with automatic failover.
@Suite("Quota gate — per-model/provider/key limits, token quotas, key pools")
struct QuotaGateTests {

    // MARK: - Pure window math

    @Test func windowIsAlignedToMinuteBoundaries() {
        let now = Date(timeIntervalSince1970: 1_700_000_123) // 23s into a minute
        let window = QuotaGateLogic.currentWindow(now: now)
        #expect(window.start == 1_700_000_100)
        #expect(QuotaGateLogic.isCurrent(window, now: now))
    }

    @Test func staleWindowIsDetected() {
        let now = Date(timeIntervalSince1970: 1_700_000_123)
        let stale = QuotaGateLogic.Window(start: 1_700_000_040, usedRequests: 5, usedTokens: 0)
        #expect(!QuotaGateLogic.isCurrent(stale, now: now))
    }

    @Test func unlimitedPolicyAlwaysAllows() {
        let policy = QuotaGateLogic.Policy.unlimited
        let window = QuotaGateLogic.currentWindow(now: Date(timeIntervalSince1970: 1_700_000_060))
        #expect(QuotaGateLogic.allows(policy: policy, window: window, requestCount: 1000, tokenEstimate: 1_000_000))
        #expect(QuotaGateLogic.waitSeconds(policy: policy, window: window) == 0)
    }

    @Test func requestLimitBlocksWhenExceeded() {
        let policy = QuotaGateLogic.Policy(requestLimit: 3, tokenQuota: 0)
        // now = 30s into the minute that starts at 1_700_000_100.
        let now = Date(timeIntervalSince1970: 1_700_000_130)
        var window = QuotaGateLogic.currentWindow(now: now)
        #expect(window.start == 1_700_000_100)
        // 3 allowed requests, then the 4th must block.
        for _ in 0..<3 {
            #expect(QuotaGateLogic.allows(policy: policy, window: window))
            window = QuotaGateLogic.acquiring(window)
        }
        #expect(!QuotaGateLogic.allows(policy: policy, window: window))
        // Wait is the remainder of the minute (window start + 60 − now).
        #expect(QuotaGateLogic.waitSeconds(policy: policy, window: window, now: now) == 30)
    }

    @Test func tokenQuotaBlocksAtLimit() {
        let policy = QuotaGateLogic.Policy(requestLimit: 0, tokenQuota: 250_000)
        let now = Date(timeIntervalSince1970: 1_700_000_130)
        var window = QuotaGateLogic.currentWindow(now: now)
        window = QuotaGateLogic.acquiring(window, tokenEstimate: 249_999)
        #expect(QuotaGateLogic.allows(policy: policy, window: window, tokenEstimate: 1))
        #expect(!QuotaGateLogic.allows(policy: policy, window: window, tokenEstimate: 2))
    }

    @Test func estimatedTokensUseBytesAndMaxOutput() {
        #expect(QuotaGateLogic.estimatedTokens(contextBytes: 400, maxOutputTokens: 2000) == 2100)
        #expect(QuotaGateLogic.estimatedTokens(contextBytes: 0, maxOutputTokens: 100) == 101)
    }

    // MARK: - Gate decisions (pool + limits)

    @Test func unlimitedGateChoosesPrimaryKeyImmediately() async {
        let gate = QuotaGate()
        let limits = QuotaGate.Limits() // all unlimited
        let decision = await gate.decide(
            providerID: "p1", model: "m1",
            primaryKey: "key-a", pool: ["key-b", "key-c"],
            limits: limits, tokenEstimate: 100,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(decision.waitSeconds == 0)
        #expect(decision.apiKey == "key-a")
    }

    @Test func providerLimitCrossesChatsAndKeys() async {
        let gate = QuotaGate()
        var limits = QuotaGate.Limits()
        limits.provider = QuotaGateLogic.Policy(requestLimit: 2, tokenQuota: 0)
        let now = Date(timeIntervalSince1970: 1_700_000_060)

        // Two requests consumed the provider-wide budget.
        for key in ["key-a", "key-b"] {
            try? await gate.acquire(
                providerID: "p1", model: "m1", apiKey: key,
                limits: limits, tokenEstimate: 10, now: now
            )
        }
        // A third request — even on a fresh key — must wait (provider limit).
        let decision = await gate.decide(
            providerID: "p1", model: "m1",
            primaryKey: "key-c", pool: ["key-c"],
            limits: limits, tokenEstimate: 10, now: now
        )
        #expect(decision.waitSeconds > 0)
        #expect(decision.waitMessage.contains("requests/min"))
    }

    @Test func perKeyLimitSwitchesPoolKey() async {
        let gate = QuotaGate()
        var limits = QuotaGate.Limits()
        limits.perKey = QuotaGateLogic.Policy(requestLimit: 1, tokenQuota: 0)
        let now = Date(timeIntervalSince1970: 1_700_000_060)

        // Key A exhausted its per-key limit.
        try? await gate.acquire(
            providerID: "p1", model: "m1", apiKey: "key-a",
            limits: limits, tokenEstimate: 10, now: now
        )
        // The next decision must fail over to Key B (free) immediately.
        let decision = await gate.decide(
            providerID: "p1", model: "m1",
            primaryKey: "key-a", pool: ["key-b"],
            limits: limits, tokenEstimate: 10, now: now
        )
        #expect(decision.waitSeconds == 0)
        #expect(decision.apiKey == "key-b")
    }

    @Test func tokenQuotaMessageNamesQuota() async {
        let gate = QuotaGate()
        var limits = QuotaGate.Limits()
        limits.provider = QuotaGateLogic.Policy(requestLimit: 0, tokenQuota: 250_000)
        let now = Date(timeIntervalSince1970: 1_700_000_070)
        try? await gate.acquire(
            providerID: "p1", model: "m1", apiKey: "key-a",
            limits: limits, tokenEstimate: 250_000, now: now
        )
        let decision = await gate.decide(
            providerID: "p1", model: "m1",
            primaryKey: "key-a", pool: [],
            limits: limits, tokenEstimate: 1, now: now
        )
        #expect(decision.waitSeconds > 0)
        #expect(decision.waitMessage.contains("250000/min"))
    }

    // MARK: - Resolver

    @Test func resolverReadsProviderAndModelLimits() {
        var provider = CustomProvider(name: "Test", type: .openAI, baseURL: "https://api.example.com/v1")
        provider.requestLimitPerMinute = 10
        provider.tokenQuotaPerMinute = 250_000
        provider.apiKeyLimitPerMinute = 5

        let suite = "QuotaTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        ProviderAPIKeyPoolStore.save(providerID: provider.id, pool: ["extra-1", "extra-2"], defaults: defaults)

        let modelParams = ["gpt-test": ModelCallParameters(requestLimitPerMinute: 3, tokenQuotaPerMinute: 99)]
        let resolved = QuotaPolicyResolver.resolve(
            baseURL: "https://api.example.com/v1", model: "gpt-test",
            providers: [provider], modelParams: modelParams, defaults: defaults
        )
        #expect(resolved.limits.provider.requestLimit == 10)
        #expect(resolved.limits.provider.tokenQuota == 250_000)
        #expect(resolved.limits.perKey.requestLimit == 5)
        #expect(resolved.limits.model.requestLimit == 3)
        #expect(resolved.limits.model.tokenQuota == 99)
        #expect(resolved.pool == ["extra-1", "extra-2"])
        #expect(resolved.providerID == provider.id)
    }

    @Test func unknownProviderResolvesToUnlimited() {
        let resolved = QuotaPolicyResolver.resolve(
            baseURL: "https://nobody.example.com/v1", model: "m",
            providers: [], modelParams: [:]
        )
        #expect(!resolved.limits.provider.hasAnyLimit)
        #expect(resolved.pool.isEmpty)
    }

    // MARK: - DirectChatClient enforcement

    @Test func preflightWaitsAndReportsWhenProviderLimitReached() async {
        let gate = QuotaGate()
        var limits = QuotaGate.Limits()
        limits.provider = QuotaGateLogic.Policy(requestLimit: 1, tokenQuota: 0)
        let now = Date(timeIntervalSince1970: 1_700_000_070)

        // Consume the only request of the minute.
        let first = await QuotaPreflight.attempt(
            gate: gate, providerID: "p1", model: "m1",
            primaryKey: "k", pool: [],
            limits: limits, tokenEstimate: 10, now: now
        )
        #expect(first.waitSeconds == 0)
        #expect(first.apiKey == "k")

        // Second attempt in the same minute must report the wait + message.
        let second = await QuotaPreflight.attempt(
            gate: gate, providerID: "p1", model: "m1",
            primaryKey: "k", pool: [],
            limits: limits, tokenEstimate: 10, now: now
        )
        #expect(second.waitSeconds > 0)
        #expect(second.message.contains("requests/min"))
    }

    @Test func sendBlocksWhenLimitIsFarFromReset() async throws {
        let gate = QuotaGate()
        let provider = CustomProvider(
            name: "Lim", type: .openAI,
            baseURL: "https://lim.example.com/v1",
            requestLimitPerMinute: 1
        )
        var waited: [String] = []
        // First call consumes the only request of the minute.
        _ = try await DirectChatClient.send(
            baseURL: "https://lim.example.com/v1", apiKey: "k", model: "m",
            messages: [DirectChatMessage(role: "user", content: "hi")],
            transport: FakeQuotaTransport(),
            quotaGate: gate, quotaProviders: [provider],
            onQuotaWait: { waited.append($0) },
            maxWaitSeconds: 0
        )
        // Second call: maxWaitSeconds 0 → immediate honest block, no sleep.
        do {
            _ = try await DirectChatClient.send(
                baseURL: "https://lim.example.com/v1", apiKey: "k", model: "m",
                messages: [DirectChatMessage(role: "user", content: "again")],
                transport: FakeQuotaTransport(),
                quotaGate: gate, quotaProviders: [provider],
                onQuotaWait: { waited.append($0) },
                maxWaitSeconds: 0
            )
            Issue.record("Expected quotaBlocked error")
        } catch let error as DirectChatError {
            guard case .quotaBlocked(let message) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(message.contains("requests/min"))
        }
    }

    @Test func poolFailoverUsesSecondKeyForRequest() async throws {
        let gate = QuotaGate()
        let provider = CustomProvider(
            name: "Pool", type: .openAI,
            baseURL: "https://pool.example.com/v1",
            apiKeyLimitPerMinute: 1
        )
        let suite = "QuotaPoolTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        ProviderAPIKeyPoolStore.save(providerID: provider.id, pool: ["key-b"], defaults: defaults)
        FakeQuotaTransport.resetRecordedKeys()
        let now = Date(timeIntervalSince1970: 1_700_000_070)

        // Resolve limits once, then drive the preflight directly for
        // deterministic (non-sleeping) coverage of pool failover.
        let resolved = QuotaPolicyResolver.resolve(
            baseURL: "https://pool.example.com/v1", model: "m",
            providers: [provider], defaults: defaults
        )
        let first = await QuotaPreflight.attempt(
            gate: gate, providerID: provider.id, model: "m",
            primaryKey: "key-a", pool: resolved.pool,
            limits: resolved.limits, tokenEstimate: 10, now: now
        )
        #expect(first.apiKey == "key-a")
        #expect(first.waitSeconds == 0)

        // Second: key-a exhausted → fail over to key-b, still no wait.
        let second = await QuotaPreflight.attempt(
            gate: gate, providerID: provider.id, model: "m",
            primaryKey: "key-a", pool: resolved.pool,
            limits: resolved.limits, tokenEstimate: 10, now: now
        )
        #expect(second.apiKey == "key-b")
        #expect(second.waitSeconds == 0)
    }

    // MARK: - Fakes

    private final class FakeQuotaTransport: DirectChatTransport {
        static var recordedKeys: [String] = []

        static func resetRecordedKeys() {
            recordedKeys = []
        }

        func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? {
            Self.recordedKeys.append(headers["Authorization"] ?? "no-key")
            let ok = #"{"choices":[{"message":{"role":"assistant","content":"ok"}}],"usage":{"prompt_tokens":5,"completion_tokens":3}}"#
            return (200, Data(ok.utf8))
        }

        func get(url: String, headers: [String: String]) async -> (Int, Data)? {
            nil
        }
    }
}
