import Foundation

/// Built-in OpenCode Zen free-model provider for myCoder.
/// The live anonymous catalog is intersected with a trusted list of temporary
/// free models; no paid model is selected automatically.
struct MyCoderAutoFreeProvider: Identifiable, Codable, Equatable {
    static let builtInID = "mycoder-auto-free"
    static let defaultModelID = MyCoderAutoFreeClient.defaultModelID

    var id: String = MyCoderAutoFreeProvider.builtInID
    var isEnabled: Bool = true
    var selectedModel: String = MyCoderAutoFreeProvider.defaultModelID
    var isModelLocked: Bool = false
    var systemPrompt: String = ""

    var isFreeTier: Bool { MyCoderAutoFreeClient.isEligibleFreeModel(selectedModel) }
    var displayName: String { "OpenCode Zen" }
    var icon: String = "sparkles"
    var isBuiltIn: Bool { true }

    /// True only when the anonymous free catalog contains at least one trusted model.
    var isCatalogReady: Bool = false
    var models: [MyCoderAutoFreeClient.Model] = []
    var lastCatalogRefresh: Date?
    var modelStatuses: [String: String] = [:]
    var consecutiveFailures: Int = 0
    var statusMessage: String = ""

    enum CodingKeys: String, CodingKey {
        case id, isEnabled, selectedModel, isModelLocked, systemPrompt, models
    }

    init() {}

    func refreshModels() async -> [MyCoderAutoFreeClient.Model] {
        do {
            return try await MyCoderAutoFreeClient.shared.listModels()
        } catch {
            return []
        }
    }

    var isReady: Bool {
        isCatalogReady && !models.isEmpty
    }
}

/// Owns the anonymous OpenCode free provider state and performs model failover.
final class MyCoderAutoFreeStore: ObservableObject {
    static let shared = MyCoderAutoFreeStore()

    @Published var provider: MyCoderAutoFreeProvider
    private let defaults = UserDefaults.standard

    private init() {
        var restored = MyCoderAutoFreeProvider()
        restored.selectedModel = UserDefaults.standard.string(forKey: "com.mycoder.autoFree.model")
            ?? MyCoderAutoFreeProvider.defaultModelID
        restored.isModelLocked = UserDefaults.standard.bool(forKey: "com.mycoder.autoFree.locked")
        restored.systemPrompt = UserDefaults.standard.string(forKey: "com.mycoder.autoFree.systemPrompt") ?? ""
        provider = restored
        Task { await refreshModels() }
    }

    @discardableResult
    func refreshModels() async -> Bool {
        do {
            let previousStatus = provider.statusMessage
            let previousSelectedModel = provider.selectedModel
            let fetched = try await MyCoderAutoFreeClient.shared.listModels()
            applyCatalog(fetched)
            provider.lastCatalogRefresh = Date()
            provider.statusMessage = MyCoderAutoFreeCatalogStatusLogic.statusAfterRefresh(
                previousStatus: previousStatus,
                previousSelectedModel: previousSelectedModel,
                currentSelectedModel: provider.selectedModel,
                fetchedModelIDs: fetched.map(\.id)
            )
            return true
        } catch {
            // Keep the last known free catalog during a transient discovery
            // failure. It still gives the send path a chance to fail over.
            provider.isCatalogReady = !provider.models.isEmpty
            provider.statusMessage = error.localizedDescription
            return false
        }
    }

    /// Manual model choice (settings list, API control, user tap). Pins the
    /// model so in-chat failover never overrides it — unlock explicitly via
    /// the lock toggle to re-enable automatic fallback.
    func selectModel(_ modelID: String) {
        let allKnownModels = Set(provider.models.map { $0.id } + MyCoderAutoFreeClient.freeModelIDs)
        guard allKnownModels.contains(modelID) else { return }
        provider.selectedModel = modelID
        provider.modelStatuses[modelID] = "Healthy"
        provider.isModelLocked = true
        provider.consecutiveFailures = 0
        provider.statusMessage = "Pinned to \(modelID). Automatic fallback is off."
        defaults.set(modelID, forKey: "com.mycoder.autoFree.model")
        defaults.set(true, forKey: "com.mycoder.autoFree.locked")
    }

    /// Lock-preserving mirror of the app-level selection for the send path.
    /// Called on every chat send — must NOT touch isModelLocked, otherwise a
    /// manually pinned model would be silently unpinned mid-conversation and
    /// failover would override the user's choice.
    func syncModel(_ modelID: String) {
        let allKnownModels = Set(provider.models.map { $0.id } + MyCoderAutoFreeClient.freeModelIDs)
        guard !modelID.isEmpty,
              allKnownModels.contains(modelID),
              provider.selectedModel != modelID else { return }
        provider.selectedModel = modelID
        provider.modelStatuses[modelID] = "Healthy"
        provider.statusMessage = "Using \(modelID)."
        defaults.set(modelID, forKey: "com.mycoder.autoFree.model")
    }

    func modelStatus(for modelID: String) -> String {
        if provider.selectedModel == modelID {
            return provider.isModelLocked ? "Pinned" : "Active · fallback eligible"
        }
        return provider.modelStatuses[modelID] ?? "Live · available"
    }

    func setModelLocked(_ locked: Bool) {
        guard provider.models.contains(where: { $0.id == provider.selectedModel }) else { return }
        provider.isModelLocked = locked
        provider.statusMessage = locked
            ? "Locked to \(provider.selectedModel). Automatic fallback is off."
            : "Unlocked \(provider.selectedModel). Automatic fallback is on."
        defaults.set(locked, forKey: "com.mycoder.autoFree.locked")
    }

    func setSystemPrompt(_ prompt: String) {
        provider.systemPrompt = prompt
        defaults.set(prompt, forKey: "com.mycoder.autoFree.systemPrompt")
    }

    func streamChat(
        messages: [MyCoderAutoFreeClient.Message],
        projectRoot: String = "",
        isGitRepo: Bool = false,
        context: OpenCodeRequestContext = .generated(),
        tools: [MyCoderAutoFreeClient.ToolDefinition] = MyCoderAutoFreeClient.agentToolDefinitions(),
        toolChoice: String? = "auto"
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                if provider.models.isEmpty {
                    _ = await refreshModels()
                }
                var attemptedModels = Set<String>()
                var currentModel = provider.selectedModel
                if !provider.models.contains(where: { $0.id == currentModel }) {
                    guard !provider.isModelLocked,
                          let replacement = provider.models.first else {
                        continuation.finish(throwing: MyCoderAutoFreeError.noFreeModels)
                        return
                    }
                    let previous = currentModel
                    currentModel = replacement.id
                    provider.selectedModel = currentModel
                    provider.statusMessage = "Previously selected model \(previous) is unavailable; switched to \(currentModel)."
                    defaults.set(currentModel, forKey: "com.mycoder.autoFree.model")
                    NotificationCenter.default.post(
                        name: .myCoderAutoFreeModelSwitched,
                        object: nil,
                        userInfo: ["fromModel": previous, "toModel": currentModel, "reason": "model unavailable"]
                    )
                }
                while true {
                    let modelParameters = ModelCallParametersStore.parameters(for: currentModel)
                    var effectiveMessages = messages
                    // BUG-30-01: the tool preamble must carry the project
                    // environment (working dir, git, date) exactly like the web
                    // branch — a free model with no working directory cannot
                    // resolve relative tool paths.
                    let toolPreamble = MyCoderAutoFreeClient.toolUsagePreamble(
                        projectRoot: projectRoot,
                        isGitRepo: isGitRepo
                    )
                    let systemPrompts = [
                        toolPreamble,
                        provider.systemPrompt,
                        modelParameters.systemPrompt ?? ""
                    ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    for prompt in systemPrompts.reversed() {
                        effectiveMessages.insert(
                            MyCoderAutoFreeClient.Message(role: "system", content: prompt),
                            at: 0
                        )
                    }
                    do {
                        for try await event in MyCoderAutoFreeClient.shared.chatCompletion(
                            model: currentModel,
                            messages: effectiveMessages,
                            parameters: modelParameters,
                            context: context,
                            tools: tools,
                            toolChoice: toolChoice,
                            projectRoot: projectRoot,
                            isGitRepo: isGitRepo
                        ) {
                            continuation.yield(event)
                        }
                        provider.consecutiveFailures = 0
                        if provider.statusMessage.isEmpty || provider.statusMessage.hasPrefix("OpenCode model") {
                            provider.statusMessage = "Using \(currentModel)."
                        }
                        continuation.finish()
                        return
                    } catch {
                        // Upstream client-identity gate: no other free model
                        // will pass it — stop the carousel with one honest
                        // message instead of failing model after model.
                        if MyCoderAutoFreeClient.shouldHaltFailover(for: error) {
                            provider.modelStatuses[currentModel] = "Blocked by upstream free-tier gate"
                            provider.statusMessage = (error as? LocalizedError)?.errorDescription
                                ?? "OpenCode free tier is gated upstream."
                            continuation.finish(throwing: error)
                            return
                        }
                        if provider.isModelLocked {
                            provider.modelStatuses[currentModel] = "Rate limited / failed while pinned"
                            if let autoFreeError = error as? MyCoderAutoFreeError,
                               case .rateLimited = autoFreeError {
                                provider.modelStatuses[currentModel] = "Rate limited"
                            }

                            provider.consecutiveFailures += 1
                            provider.statusMessage = "\(currentModel) failed while locked. Unlock the model to allow automatic fallback."
                            continuation.finish(throwing: error)
                            return
                        }
                        provider.consecutiveFailures += 1
                        let failureCount = provider.consecutiveFailures
                        provider.modelStatuses[currentModel] = Self.modelFailureStatus(for: error, failureCount: failureCount)
                        let switchNow = MyCoderAutoFreeClient.shouldSwitch(
                            for: error,
                            consecutiveFailures: failureCount
                        )

                        guard switchNow else {
                            provider.statusMessage = "\(currentModel) failed (\(failureCount)/\(MyCoderAutoFreeClient.maxConsecutiveFailures)). Retry to continue."
                            continuation.finish(throwing: error)
                            return
                        }

                        attemptedModels.insert(currentModel)
                        if provider.models.filter({ !attemptedModels.contains($0.id) }).isEmpty {
                            _ = await refreshModels()
                        }
                        guard let nextModel = provider.models.first(where: { !attemptedModels.contains($0.id) }) else {
                            provider.isCatalogReady = false
                            provider.statusMessage = "No free OpenCode models are currently available."
                            continuation.finish(throwing: error)
                            return
                        }

                        let reason = Self.switchReason(for: error, failureCount: failureCount)
                        provider.selectedModel = nextModel.id
                        provider.modelStatuses[nextModel.id] = "Active · fallback eligible"
                        provider.consecutiveFailures = 0
                        provider.statusMessage = "Switched from \(currentModel) to \(nextModel.id): \(reason)"
                        NotificationCenter.default.post(
                            name: .myCoderAutoFreeModelSwitched,
                            object: nil,
                            userInfo: [
                                "fromModel": currentModel,
                                "toModel": nextModel.id,
                                "reason": reason
                            ]
                        )
                        defaults.set(nextModel.id, forKey: "com.mycoder.autoFree.model")
                        continuation.yield(.content("\n\n[OpenCode Zen switched to \(nextModel.id): \(reason)]\n\n"))
                        currentModel = nextModel.id
                    }
                }
            }
        }
    }

    private func applyCatalog(_ fetched: [MyCoderAutoFreeClient.Model]) {
        provider.models = fetched
        let liveIDs = Set(fetched.map(\.id))
        provider.modelStatuses = provider.modelStatuses.filter { liveIDs.contains($0.key) }
        provider.isCatalogReady = !fetched.isEmpty
        if !fetched.contains(where: { $0.id == provider.selectedModel }) {
            provider.isModelLocked = false
            provider.selectedModel = fetched.first?.id ?? MyCoderAutoFreeProvider.defaultModelID
            provider.statusMessage = fetched.isEmpty
                ? "No free OpenCode models are currently available."
                : "Previously selected model is unavailable; switched to \(provider.selectedModel)."
            defaults.set(provider.selectedModel, forKey: "com.mycoder.autoFree.model")
            defaults.set(false, forKey: "com.mycoder.autoFree.locked")
        }
    }

    private static func modelFailureStatus(for error: Error, failureCount: Int) -> String {
        if let autoFreeError = error as? MyCoderAutoFreeError,
           case .rateLimited = autoFreeError {
            return "Rate limited"
        }
        if let autoFreeError = error as? MyCoderAutoFreeError,
           case .modelUnavailable = autoFreeError {
            return "Unavailable"
        }
        return "Failed \(failureCount)/\(MyCoderAutoFreeClient.maxConsecutiveFailures)"
    }

    private static func switchReason(for error: Error, failureCount: Int) -> String {
        if let autoFreeError = error as? MyCoderAutoFreeError {
            switch autoFreeError {
            case .rateLimited:
                return "rate limit"
            case .modelUnavailable:
                return "model unavailable"
            case .apiError(let message):
                return MyCoderAutoFreeFailoverLogic.reason(
                    errorDescription: message,
                    failureCount: failureCount
                )
            default:
                break
            }
        }
        return MyCoderAutoFreeFailoverLogic.reason(
            errorDescription: error.localizedDescription,
            failureCount: failureCount
        )
    }
}
