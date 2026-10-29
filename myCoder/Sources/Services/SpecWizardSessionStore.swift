import Foundation

/// One in-memory session per project so the wizard view and the local action
/// API operate on the same published state. The database remains the source of
/// truth; this cache only avoids two independent sessions racing on the same
/// append-only rows while a project is open.
@MainActor
final class SpecWizardSessionStore {
    static let shared = SpecWizardSessionStore()

    private var sessions: [String: SpecWizardSession] = [:]

    private init() {}

    func session(projectPath: String,
                 projectName: String,
                 appState: AppState) throws -> SpecWizardSession {
        let normalized = ChatSession.normalizedPath(projectPath)
        if let existing = sessions[normalized] {
            // Update the project name in case the folder was renamed or
            // this is a new project at the same path (replaces stale name).
            existing.projectName = projectName
            return existing
        }
        let database = try ProjectDatabaseManager.manager(forProjectPath: normalized)
        let created = SpecWizardSession(
            projectPath: normalized,
            projectName: projectName,
            database: database,
            providerID: appState.selectedProviderID,
            routeProvider: { [weak appState] model, providerID in
                guard let appState else { return nil }
                let resolvedProviderID = providerID ?? appState.selectedProviderID
                let isACP = appState.customProviders.contains {
                    $0.id == resolvedProviderID && $0.type == .acp && $0.acpEnabled
                }
                let route = SendRouteResolver.route(
                    selectedProviderID: resolvedProviderID,
                    selectedModel: model,
                    serverConnected: appState.serverConnected,
                    isACP: isACP,
                    customProviders: appState.customProviders,
                    localProviders: LocalProviderLogic.load(),
                    webProviderIDs: appState.webProviderIDs
                )
                return SpecPlannerRoute(sendRoute: route, model: model)
            },
            languageProvider: { [weak appState] in
                appState?.appLanguage ?? .english
            }
        )
        if created.draft.plannerModel.isEmpty {
            let current = appState.selectedModel.isEmpty
                ? appState.effectiveSelectedModel()
                : appState.selectedModel
            created.draft.plannerModel = current
            created.draft.coderModel = current
            created.draft.plannerProviderID = appState.selectedProviderID
            created.draft.coderProviderID = appState.selectedProviderID
        }
        // The app-wide provider can be a web, ACP, or MiMo serve provider that
        // the wizard cannot call directly. Drop such a preset instead of
        // showing a configured-looking setup that fails on the first turn.
        let groups = SpecWizardModelCatalog.groups(
            serverProviders: appState.serverProviders,
            customProviders: appState.customProviders,
            localProviders: LocalProviderLogic.load(defaults: appState.defaults),
            autoFree: MyCoderAutoFreeStore.shared.provider,
            defaults: appState.defaults
        )
        SpecWizardModelCatalog.pruneUnroutableSelection(
            providerID: &created.draft.plannerProviderID,
            modelID: &created.draft.plannerModel,
            groups: groups
        )
        SpecWizardModelCatalog.pruneUnroutableSelection(
            providerID: &created.draft.coderProviderID,
            modelID: &created.draft.coderModel,
            groups: groups
        )
        sessions[normalized] = created
        return created
    }

    func session(projectPath: String) -> SpecWizardSession? {
        sessions[ChatSession.normalizedPath(projectPath)]
    }

    func evict(projectPath: String) {
        sessions.removeValue(forKey: ChatSession.normalizedPath(projectPath))
    }

    func evictAll() {
        sessions.removeAll()
    }
}
