import Foundation

/// M1 model router state on `AppState`: loading/saving the routing
/// configuration (project default + chat override), building the transport
/// context snapshot, and the executed-route journal shown in the panel.
extension AppState {

    /// Journal store used for the executed route evidence (per chat).
    var modelRouteJournalStore: ModelRouteJournalStore { ModelRouteJournalStore() }

    /// Snapshot of every provider catalog the role resolver needs. Values
    /// only — no credentials are copied out of their secure stores.
    ///
    /// Вход: режим агента (для serve/ACP agent-поля). Выход: контекст.
    /// Зависимости: `LocalProviderLogic`, `WebProviderConnectivity`.
    func roleTransportContext(agentMode: AgentMode? = nil) -> RoleTransportContext {
        RoleTransportContext(
            customProviders: customProviders,
            localProviders: LocalProviderLogic.load(),
            serverProviders: serverProviders,
            serverConnected: serverConnected,
            webProviderIDs: webProviderIDs,
            serverPort: serverPort,
            agentMode: agentMode ?? self.agentMode
        )
    }

    /// The composer's current selection as the primary assignment every
    /// unassigned role falls back to.
    ///
    /// Вход: нет (читает текущий выбор). Выход: `ModelAssignment`.
    /// Зависимости: `effectiveSelectedModel`, `ModelCallParametersStore`.
    func primaryModelAssignment() -> ModelAssignment {
        let model = effectiveSelectedModel()
        return ModelAssignment(
            providerID: selectedProviderID,
            modelID: model,
            parameters: ModelCallParametersStore.parameters(for: model)
        )
    }

    /// Vision capability of a model from the REAL catalog: manual override →
    /// provider metadata → bundled catalog. `nil` means "not reported" and is
    /// never treated as a name-based guess (M1 contract).
    ///
    /// Вход: назначение. Выход: true/false/nil.
    /// Зависимости: `ModelMetadataResolver`, `ModelMetadataStore`,
    /// `ProviderSettingsLogic`.
    func catalogVisionSupport(for assignment: ModelAssignment) -> Bool? {
        ModelMetadataResolver.resolve(
            modelID: assignment.modelID,
            providerID: assignment.providerID,
            serverModel: ProviderSettingsLogic.model(
                for: assignment.modelID,
                in: serverProviders,
                providerID: assignment.providerID
            ),
            override: ModelMetadataStore.override(
                providerID: assignment.providerID,
                modelID: assignment.modelID
            )
        )?.capabilities?.vision
    }

    /// Loads the routing configuration for a project/chat pair: chat override
    /// first, then the project default, then the empty single-model config.
    /// Also refreshes the executed-route journal for that chat.
    ///
    /// Вход: корень проекта, id чата. Выход: нет (обновляет published-состояние).
    /// Зависимости: `ModelRoutingStore`, `ModelRouteJournalStore`.
    @MainActor
    func loadModelRouting(projectRoot: String, sessionID: String?) {
        let stored = ModelRoutingStore().configuration(projectRoot: projectRoot, sessionID: sessionID)
        modelRoutingConfiguration = stored ?? ModelRoutingConfiguration()
        modelRouteJournal = modelRouteJournalStore.entries(sessionID: sessionID)
    }

    /// Persists the edited configuration to the selected scope (chat override
    /// or project default). Mode switches never discard role assignments.
    ///
    /// Вход: текущая `modelRoutingConfiguration`, область (`modelRoutingScopeIsChat`).
    /// Выход: запись в UserDefaults, bump ревизии для UI.
    /// Зависимости: `ModelRoutingStore`.
    @MainActor
    func saveModelRouting(projectRoot: String, sessionID: String?) {
        let store = ModelRoutingStore()
        if modelRoutingScopeIsChat, let sessionID, !sessionID.isEmpty {
            store.saveChat(modelRoutingConfiguration, sessionID: sessionID)
        } else {
            store.saveProject(modelRoutingConfiguration, projectRoot: projectRoot)
        }
        modelRoutingRevision += 1
    }

    /// Appends one executed node to the chat journal and refreshes the panel.
    ///
    /// Вход: запись узла. Выход: нет.
    /// Зависимости: `ModelRouteJournalStore`.
    @MainActor
    func recordRouteJournalEntry(_ entry: TurnRouteJournalEntry) {
        modelRouteJournalStore.append(entry)
        if let sessionID = entry.sessionID,
           sessionID == selectedSession?.id {
            modelRouteJournal = modelRouteJournalStore.entries(sessionID: sessionID)
        }
    }

    /// Short label for the composer selector: «Единая: provider/model» or
    /// «Маршруты: N» (M1 UX spec).
    ///
    /// Вход: нет. Выход: строка состояния селекта.
    /// Зависимости: `modelRoutingConfiguration`, `primaryModelAssignment`.
    @MainActor
    func modelRoutingShortLabel() -> String {
        switch modelRoutingConfiguration.mode {
        case .single:
            let assignment = primaryModelAssignment()
            let model = assignment.modelID.isEmpty ? "—" : assignment.modelID
            return "Единая: \(model)"
        case .perRole:
            return "Маршруты: \(modelRoutingConfiguration.configuredRoleCount)"
        }
    }

    /// Whether the resolved chain sends data to more than one provider — the
    /// composer shows an explicit cross-provider warning before the first send.
    @MainActor
    func modelRoutingUsesMultipleProviders() -> Bool {
        ModelRouteResolver(
            configuration: modelRoutingConfiguration,
            primary: primaryModelAssignment()
        ).usesMultipleProviders
    }
}
