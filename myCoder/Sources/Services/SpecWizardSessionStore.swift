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
            return existing
        }
        let database = try ProjectDatabaseManager.manager(forProjectPath: normalized)
        let created = SpecWizardSession(
            projectPath: normalized,
            projectName: projectName,
            database: database,
            providerID: appState.selectedProviderID,
            routeProvider: { [weak appState] model in
                guard let appState else { return nil }
                let route = SendRouteResolver.route(
                    selectedProviderID: appState.selectedProviderID,
                    selectedModel: model,
                    serverConnected: appState.serverConnected,
                    isACP: appState.isSelectedACPProvider,
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
        }
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
