import Foundation
#if canImport(Combine)
import Combine
#endif

/// One provider/model pair assigned to myCoder's background work.
struct InternalModelRef: Codable, Equatable, Hashable, Identifiable {
    let providerID: String
    let modelID: String

    var id: String { "\(providerID)::\(modelID)" }
}

/// Ordered list of models used for internal requests. The list is the source
/// of truth: each model is tried in order, so a failed provider falls through
/// to the next assigned model instead of silently using a hardcoded default.
final class InternalModelStore: ObservableObject {
    static let shared = InternalModelStore()

    private static let storageKey = "com.mycoder.internalModels"
    private let defaults: UserDefaults

    @Published private(set) var models: [InternalModelRef]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([InternalModelRef].self, from: data) {
            models = decoded
        } else {
            models = []
        }
    }

    func contains(_ ref: InternalModelRef) -> Bool {
        models.contains(ref)
    }

    func add(_ ref: InternalModelRef) {
        guard !contains(ref) else { return }
        models.append(ref)
        persist()
    }

    func remove(_ ref: InternalModelRef) {
        models.removeAll { $0 == ref }
        persist()
    }

    func move(_ ref: InternalModelRef, offset: Int) {
        guard let index = models.firstIndex(of: ref) else { return }
        let target = index + offset
        guard models.indices.contains(target) else { return }
        models.swapAt(index, target)
        persist()
    }

    func replaceAll(_ refs: [InternalModelRef]) {
        models = refs
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// Resolves an internal model reference to the same direct transports the
/// spec planner already uses. Web, ACP and MiMo Serve providers are excluded:
/// they cannot run a background turn without opening a visible chat session.
enum InternalModelResolver {
    static let customProvidersKey = "com.mycoder.customProviders"

    static func customProviders(defaults: UserDefaults = .standard) -> [CustomProvider] {
        guard let data = defaults.data(forKey: customProvidersKey),
              let providers = try? JSONDecoder().decode([CustomProvider].self, from: data) else {
            return []
        }
        return providers
    }

    static func route(for ref: InternalModelRef,
                      customProviders: [CustomProvider]? = nil,
                      localProviders: [LocalProviderConfig]? = nil) -> SpecPlannerRoute? {
        if ref.providerID == MyCoderAutoFreeProvider.builtInID {
            return .autoFree(model: ref.modelID)
        }

        let customs = customProviders ?? Self.customProviders()
        if let custom = customs.first(where: { $0.id == ref.providerID && $0.isEnabled }) {
            let key = custom.getSecureAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .openAICompatible(
                baseURL: custom.baseURL,
                apiKey: (key?.isEmpty == false) ? key : nil,
                model: ref.modelID
            )
        }

        let locals = localProviders ?? LocalProviderLogic.load()
        guard let local = locals.first(where: { $0.id == ref.providerID && $0.isEnabled }) else {
            return nil
        }
        switch local.kind {
        case .ollama, .openAICompatible, .localAgent:
            return .openAICompatible(
                baseURL: local.kind == .ollama ? "\(local.apiBaseURL)/v1" : local.apiBaseURL,
                apiKey: nil,
                model: ref.modelID
            )
        case .openCode:
            return .openCodeServe(
                baseURL: local.apiBaseURL,
                headers: local.authHeaders(),
                providerID: local.openCodeProviderID,
                model: ref.modelID
            )
        case .acp:
            return nil
        }
    }

    static func availableModels(customProviders: [CustomProvider],
                                localProviders: [LocalProviderConfig],
                                freeModels: [String]) -> [InternalModelRef] {
        var refs: [InternalModelRef] = []
        for custom in customProviders where custom.isEnabled {
            refs.append(contentsOf: custom.models.sorted().map {
                InternalModelRef(providerID: custom.id, modelID: $0)
            })
        }
        for local in localProviders where local.isEnabled && local.kind != .acp {
            refs.append(contentsOf: local.models.sorted().map {
                InternalModelRef(providerID: local.id, modelID: $0)
            })
        }
        refs.append(contentsOf: freeModels.map {
            InternalModelRef(providerID: MyCoderAutoFreeProvider.builtInID, modelID: $0)
        })
        return refs
    }

    static func displayName(for ref: InternalModelRef,
                            customProviders: [CustomProvider],
                            localProviders: [LocalProviderConfig]) -> String {
        if ref.providerID == MyCoderAutoFreeProvider.builtInID {
            return L.t(AppLocalizationKey.locOpenCodeZen)
        }
        if let custom = customProviders.first(where: { $0.id == ref.providerID }) {
            return custom.name
        }
        if let local = localProviders.first(where: { $0.id == ref.providerID }) {
            return local.kind.displayName
        }
        return ref.providerID
    }
}

/// Runs an internal completion through the ordered model list. Every model is
/// attempted until one succeeds; the last error is surfaced when all fail.
enum InternalModelRunner {
    struct NoModelError: LocalizedError {
        var errorDescription: String? {
            "No internal model is available. Add one in Settings → Providers → Internal models."
        }
    }

    static func complete(messages: [DirectChatMessage],
                         store: InternalModelStore = .shared) async throws -> String {
        let refs = store.models
        guard !refs.isEmpty else { throw NoModelError() }
        var lastError: Error?
        for ref in refs {
            guard let route = InternalModelResolver.route(for: ref) else { continue }
            do {
                return try await LiveSpecCompletionProvider().complete(
                    SpecCompletionRequest(route: route, messages: messages)
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NoModelError()
    }
}
