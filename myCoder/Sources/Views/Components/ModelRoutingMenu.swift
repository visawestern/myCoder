import SwiftUI

/// M1 routing selector in the composer: single model vs per-role routes, the
/// nine role assignments with REAL catalog capability badges, pre-send warnings
/// for shapes that cannot execute, bulk actions, the chain preview and the
/// executed-route journal. Style mirrors `ModelPickerDropdown`.
struct ModelRoutingMenu: View {
    @EnvironmentObject var appState: AppState
    @State private var isOpen = false

    /// Project root of the current chat (project-scope storage key).
    ///
    /// Вход: нет. Выход: нормализованный путь проекта.
    /// Зависимости: `SessionProjectRootLogic`.
    private func projectRoot() -> String {
        SessionProjectRootLogic.resolve(
            sessionDirectory: appState.selectedSession?.directory,
            selectedWorkspacePath: appState.selectedWorkspace?.path
        )
    }

    private func sessionID() -> String? { appState.selectedSession?.id }

    /// Persists the edited configuration into the active scope.
    private func save() {
        appState.saveModelRouting(projectRoot: projectRoot(), sessionID: sessionID())
    }

    /// Switches edit scope and re-reads the STORED configuration of that scope
    /// (chat override first; project default when the chat has none).
    private func switchScope(toChat: Bool) {
        appState.modelRoutingScopeIsChat = toChat
        let store = ModelRoutingStore()
        if toChat {
            appState.modelRoutingConfiguration =
                store.chatConfiguration(sessionID: sessionID() ?? "")
                ?? store.projectConfiguration(projectRoot: projectRoot())
                ?? ModelRoutingConfiguration()
        } else {
            appState.modelRoutingConfiguration =
                store.projectConfiguration(projectRoot: projectRoot())
                ?? ModelRoutingConfiguration()
        }
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.modelRoutingConfiguration.mode == .perRole
                      ? "point.3.connected.trianglepath.dotted" : "arrow.triangle.swap")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(appState.modelRoutingConfiguration.mode == .perRole
                                     ? Color.mimo.brand : Color.mimo.textMuted)
                Text(appState.modelRoutingShortLabel())
                    .interfaceFont(size: 11)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .interfaceFont(size: 8, weight: .semibold)
            }
            .foregroundColor(Color.mimo.textSecondary)
        }
        .buttonStyle(HandCursorButtonStyle())
        .fixedSize()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdownContent
        }
    }

    private var dropdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    modeSection
                    scopeSection
                    if appState.modelRoutingConfiguration.mode == .perRole {
                        Divider().padding(.vertical, 2)
                        bulkSection
                        Divider().padding(.vertical, 2)
                        chainSection
                        Divider().padding(.vertical, 2)
                        ForEach(ModelRole.allCases) { role in
                            roleRow(role)
                        }
                    }
                    Divider().padding(.vertical, 2)
                    journalSection
                }
                .padding(8)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 440)
        .background(Color.mimo.background)
    }

    // MARK: - Sections

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("Routing mode"))
                .interfaceFont(size: 10, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)
            modeRow(.single, title: L.t("Single model"),
                    subtitle: L.t("Every role uses the model from the selector next to it."))
            modeRow(.perRole, title: L.t("Per-role routes"),
                    subtitle: L.t("Each role gets its own provider and model; hidden fallback is forbidden."))
        }
    }

    private func modeRow(_ mode: ModelRoutingMode, title: String, subtitle: String) -> some View {
        let isSelected = appState.modelRoutingConfiguration.mode == mode
        return Button {
            // Mode switches never discard the role configuration.
            appState.modelRoutingConfiguration = appState.modelRoutingConfiguration.changingMode(to: mode)
            save()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .interfaceFont(size: 11)
                    .foregroundColor(isSelected ? Color.mimo.brand : Color.mimo.textMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(subtitle).interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private var scopeSection: some View {
        HStack(spacing: 6) {
            Text(L.t("Scope:"))
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
            scopeButton(L.t(AppLocalizationKey.locGoal), isChat: false)
            scopeButton(L.t("Chat"), isChat: true)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func scopeButton(_ title: String, isChat: Bool) -> some View {
        let isSelected = appState.modelRoutingScopeIsChat == isChat
        return Button {
            switchScope(toChat: isChat)
        } label: {
            Text(title)
                .interfaceFont(size: 10, weight: isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Color.mimo.brand : Color.mimo.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.mimo.brand.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(HandCursorButtonStyle())
        .disabled(isChat && sessionID() == nil)
        .help(isChat && sessionID() == nil ? L.t("Select a chat first") : "")
    }

    private var bulkSection: some View {
        HStack(spacing: 8) {
            Button {
                // «Применить ко всем»: текущая основная модель на каждую роль.
                let primary = appState.primaryModelAssignment()
                for role in ModelRole.allCases {
                    appState.modelRoutingConfiguration.assignments[role] = primary
                }
                save()
            } label: {
                Text(L.t("Apply to all"))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            Button {
                // «Сбросить к единой»: режим single, назначения ролей сохраняются.
                appState.modelRoutingConfiguration = appState.modelRoutingConfiguration.changingMode(to: .single)
                save()
            } label: {
                Text(L.t("Reset to single"))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            Spacer()
        }
    }

    private var chainSection: some View {
        let graph = TurnRouteGraph.build(agentMode: appState.agentMode)
        let resolver = ModelRouteResolver(
            configuration: appState.modelRoutingConfiguration,
            primary: appState.primaryModelAssignment()
        )
        return VStack(alignment: .leading, spacing: 3) {
            Text(L.t("Turn chain (%@):", appState.agentMode.rawValue))
                .interfaceFont(size: 10, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)
            Text(graph.chainPreview)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textPrimary)
            ForEach(graph.initialRoles, id: \.self) { role in
                if let assignment = resolver.assignment(for: role) {
                    Text("· \(role.displayName): \(assignment.providerID)/\(assignment.modelID)")
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textSecondary)
                }
            }
            if appState.modelRoutingUsesMultipleProviders() {
                Label(L.t("The chain sends data to several providers. Check that this is allowed for your code and data."),
                      systemImage: "exclamationmark.triangle.fill")
                    .interfaceFont(size: 9)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Role row

    private func roleRow(_ role: ModelRole) -> some View {
        let override = appState.modelRoutingConfiguration.assignments[role]
        let effective = override ?? appState.primaryModelAssignment()
        let available = RoleTransportResolver.availableModels(context: appState.roleTransportContext())
        let vision = appState.catalogVisionSupport(for: effective)
        let tools = ModelMetadataResolver.resolve(
            modelID: effective.modelID,
            providerID: effective.providerID,
            serverModel: ProviderSettingsLogic.model(
                for: effective.modelID,
                in: appState.serverProviders,
                providerID: effective.providerID
            ),
            override: ModelMetadataStore.override(
                providerID: effective.providerID,
                modelID: effective.modelID
            )
        )?.capabilities?.toolcall
        let warning = assignmentWarning(for: effective, available: available)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.displayName)
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(role.roleDescription)
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                // Capability badges come from the REAL catalog, never from the
                // model name (M1 contract). nil = «не сообщается» → no badge.
                if vision == true {
                    badge("vision", system: "eye.fill")
                }
                if tools == true {
                    badge("tools", system: "wrench.fill")
                }
                modelMenu(role: role, override: override, available: available)
                if override != nil {
                    Button {
                        appState.modelRoutingConfiguration.assignments[role] = nil
                        save()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t("Reset role to a single model"))
                }
            }
            if override == nil {
                Text(L.t("= single (%@/%@)", effective.providerID, effective.modelID))
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.textMuted)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .interfaceFont(size: 9)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, system: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: system).interfaceFont(size: 7)
            Text(text).interfaceFont(size: 8, weight: .semibold)
        }
        .foregroundColor(Color.mimo.brand)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.mimo.brand.opacity(0.12)))
    }

    private func modelMenu(role: ModelRole, override: ModelAssignment?, available: [String: [String]]) -> some View {
        Menu {
            ForEach(available.keys.sorted(), id: \.self) { providerID in
                Menu(providerID) {
                    ForEach(available[providerID] ?? [], id: \.self) { modelID in
                        Button {
                            appState.modelRoutingConfiguration.assignments[role] = ModelAssignment(
                                providerID: providerID,
                                modelID: modelID,
                                parameters: ModelCallParametersStore.parameters(for: modelID)
                            )
                            save()
                        } label: {
                            if override?.providerID == providerID, override?.modelID == modelID {
                                Text("✓ \(modelID)")
                            } else {
                                Text(modelID)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(override.map { "\($0.providerID)/\($0.modelID)" } ?? L.t("Select…"))
                    .interfaceFont(size: 10)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .interfaceFont(size: 7, weight: .semibold)
            }
            .foregroundColor(override == nil ? Color.mimo.textMuted : Color.mimo.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.mimo.textMuted.opacity(0.4), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Pre-send warning for an assignment that cannot execute honestly:
    /// web/unresolved transport, a model missing from the real catalog, or a
    /// custom provider without an API key. Shown BEFORE the first send.
    ///
    /// Вход: назначение, каталог доступных моделей. Выход: RU-текст или nil.
    /// Зависимости: `RoleTransportResolver`, `CustomProvider.getSecureAPIKey`.
    private func assignmentWarning(for assignment: ModelAssignment, available: [String: [String]]) -> String? {
        guard assignment.isComplete else {
            return L.t("No model selected — sending will end with an honest error.")
        }
        let context = appState.roleTransportContext()
        switch RoleTransportResolver.kind(for: assignment, context: context) {
        case .webUnsupported(let configID):
            return L.t("Web provider “%@” cannot make one-shot role requests. Assign a direct provider/model.", configID)
        case .unresolved:
            return L.t("Provider “%@” is unavailable, disabled, or its model was removed.", assignment.providerID)
        case .openAICompatible, .openCodeServe, .mimoServe, .acp:
            break
        }
        if !(available[assignment.providerID]?.contains(assignment.modelID) ?? false) {
            return L.t("Model %@ is not in the provider %@ catalog.", assignment.modelID, assignment.providerID)
        }
        if let custom = appState.customProviders.first(where: { $0.id == assignment.providerID }),
           (custom.getSecureAPIKey() ?? "").isEmpty {
            return L.t("Provider %@ has no API key — sending will fail.", custom.name)
        }
        return nil
    }

    // MARK: - Journal

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.t("Routing journal"))
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                if !appState.modelRouteJournal.isEmpty {
                    Button(L.t("Clear")) {
                        if let sessionID = sessionID() {
                            ModelRouteJournalStore().clear(sessionID: sessionID)
                        }
                        appState.modelRouteJournal = []
                    }
                    .interfaceFont(size: 10)
                    .buttonStyle(HandCursorButtonStyle())
                }
            }
            if appState.modelRouteJournal.isEmpty {
                Text(L.t("Empty: completed nodes will appear here after a routed turn."))
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.textMuted)
            } else {
                ForEach(appState.modelRouteJournal, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .interfaceFont(size: 8)
                                .foregroundColor(entry.isCompleted ? .green : .red)
                            Text("\(entry.role.displayName) · \(entry.assignment.providerID)/\(entry.assignment.modelID)")
                                .interfaceFont(size: 9)
                                .foregroundColor(Color.mimo.textSecondary)
                            Spacer()
                            if let usage = entry.usage,
                               (usage.inputTokens ?? 0) > 0 || (usage.outputTokens ?? 0) > 0 {
                                Text("↓\(usage.inputTokens ?? 0) ↑\(usage.outputTokens ?? 0)")
                                    .interfaceFont(size: 8)
                                    .foregroundColor(Color.mimo.textMuted)
                            }
                        }
                        if let error = entry.error {
                            Text(error)
                                .interfaceFont(size: 9)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
