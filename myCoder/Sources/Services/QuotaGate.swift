import Foundation

/// Process-wide, cross-chat quota gate (directive 2026-11-13).
///
/// Every outgoing HTTP model request passes through `acquire` before it is
/// sent and through `recordUsage` after it returns. The gate keeps one
/// 60-second usage window per scope — provider, model and API key — so limits
/// configured for a provider apply across ALL chats, all keys and all models
/// of that provider; per-model limits apply to one model; per-key limits apply
/// to one pool member.
///
/// Defaults are unlimited (0). When a request would exceed a configured limit
/// the gate answers with the seconds until the window resets; the caller waits
/// (surfacing `QuotaWaitMessage` in the chat) and retries.
///
/// Input: provider id, model id, API key pool, limits, token estimate.
/// Output: a `QuotaDecision` — the key to use (pool-aware) or a wait verdict.
/// Dependencies: `QuotaGateLogic` (pure math), `QuotaPolicyResolver`.
actor QuotaGate {

    static let shared = QuotaGate()

    /// All configured limits for one request, resolved from app settings.
    struct Limits {
        var provider: QuotaGateLogic.Policy = .unlimited
        var model: QuotaGateLogic.Policy = .unlimited
        var perKey: QuotaGateLogic.Policy = .unlimited
    }

    struct QuotaDecision: Equatable {
        /// The API key to use for this request (nil = no key).
        let apiKey: String?
        /// 0 = send now; >0 = seconds to wait before retrying.
        let waitSeconds: Int
        /// Message for the chat while waiting (empty when waitSeconds == 0).
        let waitMessage: String
    }

    enum Error: Swift.Error, Equatable {
        /// All keys are exhausted and the wait exceeds the caller's patience.
        case blocked(message: String)
    }

    private var providerWindows: [String: QuotaGateLogic.Window] = [:]
    private var modelWindows: [String: QuotaGateLogic.Window] = [:]
    private var keyWindows: [String: QuotaGateLogic.Window] = [:]
    /// Last decision per provider (for the settings UI's online accounting).
    private var lastKeys: [String: String] = [:]

    /// Resolve the API key and the wait verdict for one request.
    ///
    /// Input: provider/model ids, pool (extra keys; the primary key heads the
    /// candidate list), limits, token estimate, now (injectable for tests).
    /// Output: `QuotaDecision` — never mutates state (pure decision).
    /// Dependencies: `QuotaGateLogic`, `Policy`.
    func decide(providerID: String,
                model: String,
                primaryKey: String?,
                pool: [String],
                limits: Limits,
                tokenEstimate: Int,
                now: Date = Date()) -> QuotaDecision {
        var candidates: [String?] = [primaryKey]
        if !pool.isEmpty {
            candidates = pool.map { $0 as String? }
            if let primary = primaryKey, !primary.isEmpty, !pool.contains(primary) {
                candidates.insert(primary, at: 0)
            }
        }

        let providerWindow = window(for: providerID, in: providerWindows, now: now)
        let modelWindow = window(for: model, in: modelWindows, now: now)

        var bestWait = 0
        var bestMessage = ""
        var bestKey: String? = primaryKey

        for candidate in candidates {
            let key = candidate ?? ""
            let keyWindow = window(for: key, in: keyWindows, now: now)
            let wait = maxWait(
                providerPolicy: limits.provider, providerWindow: providerWindow,
                modelPolicy: limits.model, modelWindow: modelWindow,
                keyPolicy: limits.perKey, keyWindow: keyWindow,
                now: now, tokenEstimate: tokenEstimate
            )
            if wait == 0 {
                return QuotaDecision(apiKey: candidate, waitSeconds: 0, waitMessage: "")
            }
            if bestWait == 0 || wait < bestWait {
                bestWait = wait
                bestKey = candidate
                bestMessage = message(for: limits, providerWindow: providerWindow,
                                     modelWindow: modelWindow, keyWindow: keyWindow,
                                     now: now, tokenEstimate: tokenEstimate)
            }
        }
        return QuotaDecision(apiKey: bestKey, waitSeconds: bestWait, waitMessage: bestMessage)
    }

    /// Reserve quota for one request. Throws `Error.blocked` when even after
    /// `maxWaitSeconds` the limits would still block (callers usually wait and
    /// retry, so this is the honest fail path).
    ///
    /// Input: provider/model ids, chosen API key, limits, token estimate, now.
    /// Output: void; records usage in every applicable window on success.
    /// Dependencies: `QuotaGateLogic`.
    func acquire(providerID: String,
                 model: String,
                 apiKey: String?,
                 limits: Limits,
                 tokenEstimate: Int,
                 now: Date = Date()) throws {
        let decision = decide(providerID: providerID, model: model,
                              primaryKey: apiKey, pool: [],
                              limits: limits, tokenEstimate: tokenEstimate,
                              now: now)
        guard decision.waitSeconds == 0 else {
            throw Error.blocked(message: decision.waitMessage)
        }
        let key = apiKey ?? ""
        providerWindows[providerID] = QuotaGateLogic.acquiring(
            window(for: providerID, in: providerWindows, now: now),
            tokenEstimate: tokenEstimate
        )
        modelWindows[model] = QuotaGateLogic.acquiring(
            window(for: model, in: modelWindows, now: now),
            tokenEstimate: tokenEstimate
        )
        if !key.isEmpty {
            keyWindows[key] = QuotaGateLogic.acquiring(
                window(for: key, in: keyWindows, now: now),
                tokenEstimate: tokenEstimate
            )
        }
        lastKeys[providerID] = key
    }

    /// Report real token usage after a response (the pre-flight estimate is
    /// replaced by the actual prompt+completion tokens).
    func recordUsage(providerID: String, model: String, apiKey: String?,
                     tokens: Int, now: Date = Date()) {
        if let current = providerWindows[providerID], QuotaGateLogic.isCurrent(current, now: now) {
            providerWindows[providerID] = QuotaGateLogic.recording(current, tokens: tokens)
        }
        if let current = modelWindows[model], QuotaGateLogic.isCurrent(current, now: now) {
            modelWindows[model] = QuotaGateLogic.recording(current, tokens: tokens)
        }
        if let key = apiKey, !key.isEmpty,
           let current = keyWindows[key], QuotaGateLogic.isCurrent(current, now: now) {
            keyWindows[key] = QuotaGateLogic.recording(current, tokens: tokens)
        }
    }

    /// Live snapshot for the settings UI (online accounting).
    static func snapshot(gate: QuotaGate = .shared) async -> [QuotaScopeStatus] {
        await gate.snapshot()
    }

    func snapshot() -> [QuotaScopeStatus] {
        let now = Date()
        var result: [QuotaScopeStatus] = []
        for (id, window) in providerWindows {
            result.append(status(kind: .provider, scopeKey: id, window: window, now: now))
        }
        for (id, window) in modelWindows {
            result.append(status(kind: .model, scopeKey: id, window: window, now: now))
        }
        for (id, window) in keyWindows {
            result.append(status(kind: .apiKey, scopeKey: id, window: window, now: now))
        }
        return result
    }

    func activeKey(for providerID: String) -> String? {
        lastKeys[providerID]
    }

    // MARK: - Private

    private func window(for key: String, in store: [String: QuotaGateLogic.Window],
                        now: Date) -> QuotaGateLogic.Window {
        guard let current = store[key], QuotaGateLogic.isCurrent(current, now: now) else {
            return QuotaGateLogic.currentWindow(now: now)
        }
        return current
    }

    private func maxWait(providerPolicy: QuotaGateLogic.Policy,
                         providerWindow: QuotaGateLogic.Window,
                         modelPolicy: QuotaGateLogic.Policy,
                         modelWindow: QuotaGateLogic.Window,
                         keyPolicy: QuotaGateLogic.Policy,
                         keyWindow: QuotaGateLogic.Window,
                         now: Date,
                         tokenEstimate: Int) -> Int {
        var seconds = 0
        if providerPolicy.hasAnyLimit,
           !QuotaGateLogic.allows(policy: providerPolicy, window: providerWindow,
                                  tokenEstimate: tokenEstimate) {
            seconds = max(seconds, QuotaGateLogic.waitSeconds(policy: providerPolicy, window: providerWindow, now: now, tokenEstimate: tokenEstimate))
        }
        if modelPolicy.hasAnyLimit,
           !QuotaGateLogic.allows(policy: modelPolicy, window: modelWindow,
                                  tokenEstimate: tokenEstimate) {
            seconds = max(seconds, QuotaGateLogic.waitSeconds(policy: modelPolicy, window: modelWindow, now: now, tokenEstimate: tokenEstimate))
        }
        if keyPolicy.hasAnyLimit,
           !QuotaGateLogic.allows(policy: keyPolicy, window: keyWindow,
                                  tokenEstimate: tokenEstimate) {
            seconds = max(seconds, QuotaGateLogic.waitSeconds(policy: keyPolicy, window: keyWindow, now: now, tokenEstimate: tokenEstimate))
        }
        return seconds
    }

    private func message(for limits: Limits,
                         providerWindow: QuotaGateLogic.Window,
                         modelWindow: QuotaGateLogic.Window,
                         keyWindow: QuotaGateLogic.Window,
                         now: Date,
                         tokenEstimate: Int) -> String {
        if limits.provider.requestLimit > 0,
           !QuotaGateLogic.allows(policy: limits.provider, window: providerWindow,
                                  tokenEstimate: tokenEstimate) {
            return QuotaWaitMessage.requestLimit(
                limit: limits.provider.requestLimit,
                waitSeconds: QuotaGateLogic.waitSeconds(policy: limits.provider, window: providerWindow, now: now, tokenEstimate: tokenEstimate)
            )
        }
        if limits.provider.tokenQuota > 0,
           !QuotaGateLogic.allows(policy: limits.provider, window: providerWindow,
                                  tokenEstimate: tokenEstimate) {
            return QuotaWaitMessage.tokenQuota(
                quota: limits.provider.tokenQuota,
                waitSeconds: QuotaGateLogic.waitSeconds(policy: limits.provider, window: providerWindow, now: now, tokenEstimate: tokenEstimate)
            )
        }
        if limits.model.requestLimit > 0,
           !QuotaGateLogic.allows(policy: limits.model, window: modelWindow,
                                  tokenEstimate: tokenEstimate) {
            return QuotaWaitMessage.requestLimit(
                limit: limits.model.requestLimit,
                waitSeconds: QuotaGateLogic.waitSeconds(policy: limits.model, window: modelWindow, now: now, tokenEstimate: tokenEstimate)
            )
        }
        if limits.model.tokenQuota > 0,
           !QuotaGateLogic.allows(policy: limits.model, window: modelWindow,
                                  tokenEstimate: tokenEstimate) {
            return QuotaWaitMessage.tokenQuota(
                quota: limits.model.tokenQuota,
                waitSeconds: QuotaGateLogic.waitSeconds(policy: limits.model, window: modelWindow, now: now, tokenEstimate: tokenEstimate)
            )
        }
        if limits.perKey.requestLimit > 0 {
            return QuotaWaitMessage.allKeysExhausted(waitSeconds: 60)
        }
        return "Rate limit reached — waiting"
    }

    private func status(kind: QuotaScopeKind,
                        scopeKey: String,
                        window: QuotaGateLogic.Window,
                        now: Date) -> QuotaScopeStatus {
        let reset = max(0, Int(ceil(window.start + QuotaGateLogic.windowSeconds - now.timeIntervalSince1970)))
        return QuotaScopeStatus(
            scopeKey: scopeKey,
            kind: kind,
            resetSeconds: reset,
            remainingRequests: nil,
            remainingTokens: nil
        )
    }
}

/// Shared pre-flight for any HTTP path (streaming and one-shot): resolves the
/// provider limits + API-key pool, decides the key, waits when a limit is hit
/// (calling `onWait` with the chat message), then reserves quota.
///
/// Input: gate, provider id, model, primary key, pool, limits, context bytes,
/// parameters (for max output tokens), max wait seconds, `onWait` callback.
/// Output: the API key to use (pool-aware) — nil when no gate/limits apply.
/// Dependencies: `QuotaGate`, `QuotaGateLogic`.
enum QuotaPreflight {
    /// One deterministic step: decide the pool key and reserve quota when the
    /// request is allowed right now; otherwise return the wait in seconds and
    /// its chat message without sleeping (pure decision, test-friendly).
    static func attempt(gate: QuotaGate,
                        providerID: String,
                        model: String,
                        primaryKey: String?,
                        pool: [String],
                        limits: QuotaGate.Limits,
                        tokenEstimate: Int,
                        now: Date = Date()) async -> (apiKey: String?, waitSeconds: Int, message: String) {
        let decision = await gate.decide(
            providerID: providerID,
            model: model,
            primaryKey: primaryKey,
            pool: pool,
            limits: limits,
            tokenEstimate: tokenEstimate,
            now: now
        )
        guard decision.waitSeconds == 0 else {
            return (nil, decision.waitSeconds, decision.waitMessage)
        }
        try? await gate.acquire(
            providerID: providerID,
            model: model,
            apiKey: decision.apiKey,
            limits: limits,
            tokenEstimate: tokenEstimate,
            now: now
        )
        return (decision.apiKey ?? primaryKey, 0, "")
    }

    /// Full pre-flight for any HTTP path (streaming and one-shot): resolves the
    /// provider limits + API-key pool, decides the key, waits when a limit is
    /// hit (calling `onWait` with the chat message), then reserves quota.
    ///
    /// Input: gate, provider id, model, primary key, pool, limits, context
    /// bytes, parameters (for max output tokens), max wait seconds, `onWait`.
    /// Output: the API key to use (pool-aware) — nil when no gate/limits apply.
    /// Dependencies: `QuotaGate`, `QuotaGateLogic`, `attempt`.
    static func run(gate: QuotaGate?,
                    providerID: String,
                    model: String,
                    primaryKey: String?,
                    pool: [String],
                    limits: QuotaGate.Limits,
                    contextBytes: Int,
                    parameters: ModelCallParameters,
                    maxWaitSeconds: Int,
                    onWait: ((String) -> Void)?) async throws -> String? {
        guard let gate, limits.provider.hasAnyLimit
            || limits.model.hasAnyLimit
            || limits.perKey.hasAnyLimit
            || !pool.isEmpty else {
            return primaryKey
        }
        let tokenEstimate = QuotaGateLogic.estimatedTokens(
            contextBytes: contextBytes,
            maxOutputTokens: parameters.maxTokens
        )
        var effectiveKey = primaryKey
        var waited = 0
        while true {
            let step = await attempt(
                gate: gate,
                providerID: providerID,
                model: model,
                primaryKey: primaryKey ?? effectiveKey,
                pool: pool,
                limits: limits,
                tokenEstimate: tokenEstimate
            )
            if step.waitSeconds == 0 {
                return step.apiKey ?? effectiveKey
            }
            waited += step.waitSeconds
            if waited > maxWaitSeconds {
                throw DirectChatError.quotaBlocked(step.message)
            }
            onWait?(step.message)
            try await Task.sleep(nanoseconds: UInt64(step.waitSeconds) * 1_000_000_000)
        }
    }
}

/// Resolves the effective quota limits for one outgoing request from the
/// configured providers and per-model parameters.
///
/// Input: base URL the request goes to, model id, the custom provider catalog
/// and the per-model parameter store.
/// Output: `QuotaGate.Limits` (all zero → unlimited) plus the provider's API
/// key pool and primary key.
/// Dependencies: `CustomProvider`, `ModelCallParametersStore`,
/// `ProviderAPIKeyPoolStore`.
enum QuotaPolicyResolver {
    struct Resolution {
        let limits: QuotaGate.Limits
        let primaryKey: String?
        let pool: [String]
        let providerID: String?
    }

    static func resolve(baseURL: String,
                        model: String,
                        providers: [CustomProvider],
                        modelParams: [String: ModelCallParameters] = ModelCallParametersStore.loadAll(),
                        defaults: UserDefaults = .standard) -> Resolution {
        let normalizedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let provider = providers.first(where: {
            $0.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalizedBase
        }) else {
            return Resolution(limits: QuotaGate.Limits(), primaryKey: nil, pool: [], providerID: nil)
        }
        var limits = QuotaGate.Limits()
        limits.provider = QuotaGateLogic.Policy(
            requestLimit: max(0, provider.requestLimitPerMinute),
            tokenQuota: max(0, provider.tokenQuotaPerMinute)
        )
        limits.perKey = QuotaGateLogic.Policy(
            requestLimit: max(0, provider.apiKeyLimitPerMinute),
            tokenQuota: 0
        )
        if let params = modelParams[model] {
            if let requestLimit = params.requestLimitPerMinute {
                limits.model.requestLimit = max(0, requestLimit)
            }
            if let tokenQuota = params.tokenQuotaPerMinute {
                limits.model.tokenQuota = max(0, tokenQuota)
            }
        }
        let primaryKey = provider.getSecureAPIKey() ?? ""
        let pool = ProviderAPIKeyPoolStore.load(providerID: provider.id, defaults: defaults)
        return Resolution(
            limits: limits,
            primaryKey: primaryKey.isEmpty ? nil : primaryKey,
            pool: pool,
            providerID: provider.id
        )
    }
}
