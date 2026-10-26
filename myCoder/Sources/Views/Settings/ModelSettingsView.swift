import SwiftUI

enum ProviderDetailField: Hashable {
    case name
    case baseURL
    case apiKey
    case host
    case port
}

enum ModelSortOrder: String, CaseIterable, Identifiable {
    case name
    case context
    case reasoning
    case tools

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return L.t(AppLocalizationKey.locSortName)
        case .context: return L.t(AppLocalizationKey.locSortContext)
        case .reasoning: return L.t(AppLocalizationKey.locSortReasoning)
        case .tools: return L.t(AppLocalizationKey.locSortTools)
        }
    }
}

struct ModelSettingsView: View {
    let availableWidth: CGFloat
    @EnvironmentObject var appState: AppState
    @State private var showAddProvider = false
    @State private var newProviderName = ""
    @State private var newProviderType: ProviderType = .openAI
    @State private var newProviderURL = ""
    @State private var newProviderKey = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locModelSettings))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            Text(L.t(AppLocalizationKey.locConfigureModelProvidersAndManageAvailableModels))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)
            
            ModelSettingsProviderColumns(
                showAddProvider: $showAddProvider,
                availableWidth: availableWidth
            )
        }
        .sheet(isPresented: $showAddProvider) {
            AddProviderSheet(
                isPresented: $showAddProvider,
                name: $newProviderName,
                type: $newProviderType,
                url: $newProviderURL,
                apiKey: $newProviderKey
            )
            .environmentObject(appState)
        }
    }

}

struct ModelSettingsProviderColumns: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAddProvider: Bool
    let availableWidth: CGFloat
    @State private var detailProviderID: String = ""
    @State private var customAPIKeyDraft: String = ""
    @State private var customBaseURLDraft: String = ""
    @State private var parameterModelID: String = ""
    @State private var parameterProviderID: String = ""
    @State private var parameterTemperature: String = ""
    @State private var parameterMaxTokens: String = ""
    @State private var parameterTopP: String = ""
    @State private var parameterSystemPrompt: String = ""
    @State private var parameterError: String?
    @State private var modelSearchQuery: String = ""
    @State private var modelSortOrder: ModelSortOrder = .name
    @State private var providerNameDraft: String = ""
    @State private var localRefreshMessage: String?
    @State private var providerPendingDelete: ProviderOption?
    @State private var providerRevision: Int = 0
    @State private var didRefreshProvider = false
    @State private var providerSaveTask: Task<Void, Never>?
    @FocusState private var focusedProviderField: ProviderDetailField?
    @State private var localHostDraft: String = ""
    @State private var localPortDraft: String = ""
    @State private var editingModelProviderID: String = ""
    @State private var cloneModelProviderID: String = ""
    @State private var cloneSourceModelID: String = ""
    @State private var cloneModelDraft: String = ""
    @State private var newModelProviderID: String = ""
    @State private var newModelDraft: String = ""
    @State private var editingModelID: String = ""
    @State private var editingModelDraft: String = ""

    private var options: [ProviderOption] {
        appState.manageableProviderOptions
    }

    private func webConfig(for providerID: String) -> WebProviderConfig? {
        guard let id = WebProviderConnectivity.configID(fromOptionID: providerID) else { return nil }
        return WebProviderStore.load().first(where: { $0.id == id })
    }

    private func isMutableProvider(_ option: ProviderOption) -> Bool {
        option.isCustom || webConfig(for: option.id) != nil
    }

    private func localProvider(for providerID: String) -> LocalProviderConfig? {
        LocalProviderLogic.load().first(where: { $0.id == providerID })
    }

    private func customProvider(for providerID: String) -> CustomProvider? {
        appState.customProviders.first(where: { $0.id == providerID })
    }

    private func isProviderEnabled(_ option: ProviderOption) -> Bool {
        if let custom = customProvider(for: option.id) { return custom.isEnabled }
        if let local = localProvider(for: option.id) { return local.isEnabled }
        return true
    }

    private func isToggleableProvider(_ option: ProviderOption) -> Bool {
        customProvider(for: option.id) != nil || localProvider(for: option.id) != nil
    }

    private func setProviderEnabled(_ option: ProviderOption, enabled: Bool) {
        if customProvider(for: option.id) != nil {
            appState.setCustomProviderEnabled(option.id, isEnabled: enabled)
            return
        }
        guard localProvider(for: option.id) != nil else { return }
        LocalProviderLogic.setEnabled(id: option.id, isEnabled: enabled)
        if !enabled, appState.selectedProviderID == option.id {
            appState.selectProvider("")
        }
        appState.validateAndReconcileSelections()
    }

    private func isRenameableProvider(_ option: ProviderOption) -> Bool {
        customProvider(for: option.id) != nil
    }

    private func commitProviderName(_ option: ProviderOption) {
        let trimmed = providerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            providerNameDraft = option.name
            return
        }
        guard trimmed != option.name else { return }
        guard let index = appState.customProviders.firstIndex(where: { $0.id == option.id }) else {
            providerNameDraft = option.name
            return
        }
        var updated = appState.customProviders[index]
        updated.name = trimmed
        appState.updateCustomProvider(updated)
    }

    private func scheduleProviderSave(_ action: @escaping () -> Void) {
        providerSaveTask?.cancel()
        providerSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { action() }
        }
    }

    private func commitCustomProviderDraft(_ providerID: String) {
        guard let index = appState.customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var updated = appState.customProviders[index]
        let url = customBaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = customAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url != updated.baseURL || key != (updated.getSecureAPIKey() ?? "") else { return }
        updated.baseURL = url
        updated.apiKey = key
        appState.updateCustomProvider(updated)
    }

    private func commitLocalProviderDraft(_ providerID: String) {
        guard var local = localProvider(for: providerID) else { return }
        let host = localHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(localPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? local.port
        guard !host.isEmpty, host != local.host || port != local.port else { return }
        local.host = host
        local.port = port
        LocalProviderLogic.update(local)
    }

    private func refreshProvider(_ option: ProviderOption) {
        localRefreshMessage = nil
        if let custom = customProvider(for: option.id) {
            appState.refreshModels(for: custom.id)
            return
        }
        if let local = localProvider(for: option.id) {
            Task {
                await appState.refreshLocalModels(local.id)
                await MainActor.run {
                    let refreshed = localProvider(for: option.id)
                    localRefreshMessage = refreshed.map {
                        L.t(AppLocalizationKey.locModelsCount, $0.models.count)
                    }
                }
            }
            return
        }
        if let web = webConfig(for: option.id) {
            Task {
                let message = await appState.refreshWebModels(for: web)
                await MainActor.run { localRefreshMessage = message }
            }
        }
    }

    private func modelCountLabel(_ count: Int) -> String {
        count == 1 ? L.t(AppLocalizationKey.locModelCount, count) : L.t(AppLocalizationKey.locModelsCount, count)
    }

    private func providerKindLabel(_ option: ProviderOption) -> String {
        if webConfig(for: option.id) != nil { return L.t(AppLocalizationKey.locWebSession) }
        if localProvider(for: option.id) != nil { return L.t(AppLocalizationKey.locLocalProviders) }
        if customProvider(for: option.id) != nil { return L.t(AppLocalizationKey.locCustomProvider) }
        return L.t(AppLocalizationKey.locLocalAgent)
    }

    private func selectProvider(_ option: ProviderOption) {
        detailProviderID = option.id
        guard isProviderEnabled(option) else { return }
        appState.selectProvider(option.id)
    }

    private func removeProvider(_ option: ProviderOption) {
        if let custom = customProvider(for: option.id) {
            appState.removeCustomProvider(custom)
            DisabledModelStore.clear(providerID: custom.id)
            return
        }
        if let local = localProvider(for: option.id) {
            LocalProviderLogic.remove(id: local.id)
            DisabledModelStore.clear(providerID: local.id)
            if appState.selectedProviderID == option.id { appState.selectProvider("") }
            return
        }
        if let web = webConfig(for: option.id) {
            var configs = WebProviderStore.load()
            configs.removeAll { $0.id == web.id }
            WebProviderStore.save(configs)
            try? WebSessionManager.clear(providerId: web.id,
                                         homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            if appState.selectedProviderID == option.id { appState.selectProvider("") }
        }
    }

    private func canDeleteModels(providerID: String) -> Bool {
        customProvider(for: providerID) != nil || localProvider(for: providerID) != nil
    }

    private func deleteModel(_ modelID: String, from providerID: String) {
        if customProvider(for: providerID) != nil {
            appState.removeModel(modelID, from: providerID)
            return
        }
        guard localProvider(for: providerID) != nil else { return }
        LocalProviderLogic.removeModel(modelID, from: providerID)
    }

    private func isModelDisabled(_ modelID: String, providerID: String) -> Bool {
        DisabledModelStore.isDisabled(providerID: providerID, modelID: modelID)
    }

    private func toggleModelDisabled(_ modelID: String, providerID: String) {
        let disabled = !isModelDisabled(modelID, providerID: providerID)
        DisabledModelStore.setDisabled(disabled, providerID: providerID, modelID: modelID)
        guard disabled,
              appState.selectedProviderID == providerID,
              appState.selectedModel == modelID else { return }
        if let replacement = appState.modelsForSelectedProvider.first(where: { $0 != modelID }) {
            appState.selectModel(replacement)
        } else {
            appState.selectModel("")
        }
    }

    private func isEditingModel(modelID: String, providerID: String) -> Bool {
        editingModelProviderID == providerID && editingModelID == modelID
    }

    private func beginRename(_ modelID: String, providerID: String) {
        editingModelProviderID = providerID
        editingModelID = modelID
        editingModelDraft = modelID
    }

    private func beginClone(_ modelID: String, providerID: String) {
        cloneModelProviderID = providerID
        cloneSourceModelID = modelID
        cloneModelDraft = modelID + "-copy"
    }

    private func cancelRename() {
        editingModelProviderID = ""
        editingModelID = ""
        editingModelDraft = ""
    }

    private func commitRename(modelID: String, providerID: String) {
        let renamed = editingModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()
        guard !renamed.isEmpty, renamed != modelID else { return }
        appState.renameCustomModel(providerID: providerID, modelID: modelID, to: renamed)
    }

    private func commitClone(sourceModelID: String, providerID: String) {
        let name = cloneModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        cloneSourceModelID = ""
        cloneModelProviderID = ""
        cloneModelDraft = ""
        guard !name.isEmpty, name != sourceModelID else { return }
        appState.cloneCustomModel(providerID: providerID, modelID: sourceModelID, newName: name)
    }

    private func commitAddModel(providerID: String) {
        let id = newModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        newModelDraft = ""
        newModelProviderID = ""
        guard !id.isEmpty else { return }
        appState.addCustomModel(providerID: providerID, modelID: id)
    }

    private func isEditingClone(modelID: String, providerID: String) -> Bool {
        cloneModelProviderID == providerID && cloneSourceModelID == modelID
    }

    private func models(for providerID: String) -> [String] {
        if let web = webConfig(for: providerID) {
            return WebProviderConnectivity.models(for: web)
        }
        if let local = localProvider(for: providerID) {
            return local.models
        }
        if let custom = customProvider(for: providerID) {
            return custom.models.sorted()
        }
        return ProviderSettingsLogic.models(
            for: providerID,
            in: appState.serverProviders,
            customProviders: appState.customProviders
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t(AppLocalizationKey.locProvidersModels))
                    .interfaceFont(size: 16, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                Button(action: { showAddProvider = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(L.t(AppLocalizationKey.locAddProvider1))
                    }
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.brand)
                }
                .buttonStyle(HandCursorButtonStyle())
            }

            if layoutMode == .wide {
                HStack(alignment: .top, spacing: 12) {
                    providerListColumn
                        .frame(width: 200)
                    providerDetailColumn
                        .frame(width: 240)
                    modelsColumn
                        .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)
                        .layoutPriority(1)
                }
                // Custom-provider credentials and endpoint controls need more
                // room than the old 320pt card allowed; otherwise the Save /
                // Refresh actions were clipped and effectively unreachable.
                .frame(height: 480)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        providerListColumn
                            .frame(maxWidth: .infinity)
                        providerDetailColumn
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 240)

                    modelsColumn
                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                }
            }

        }
        .onAppear {
            if detailProviderID.isEmpty {
                // Prefill so Details/Models are populated instead of blank.
                detailProviderID = appState.selectedProviderID.isEmpty
                    ? (options.first?.id ?? "")
                    : appState.selectedProviderID
            }
        }
        .onChange(of: appState.selectedProviderID) { newValue in
            if !newValue.isEmpty {
                detailProviderID = newValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providersChanged)) { _ in
            providerRevision &+= 1
            if !options.contains(where: { $0.id == detailProviderID }) {
                detailProviderID = options.first?.id ?? ""
            }
        }
        .alert(item: $providerPendingDelete) { option in
            Alert(
                title: Text(L.t(AppLocalizationKey.locRemoveProvider)),
                message: Text(option.name),
                primaryButton: .destructive(Text(L.t(AppLocalizationKey.locRemoveProvider))) {
                    removeProvider(option)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var layoutMode: ModelSettingsLayoutMode {
        ModelSettingsLayoutLogic.mode(availableWidth: availableWidth)
    }

    private var providerListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.t(AppLocalizationKey.locProviders))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)
                .padding(.bottom, 8)

            if options.isEmpty {
                SettingsCardEmptyState(
                    icon: "server.rack",
                    title: L.t(AppLocalizationKey.locProvidersYet),
                    hint: L.t(AppLocalizationKey.locConnectTheLocalAgentAddCustomProviderGetStarted),
                    actionTitle: L.t(AppLocalizationKey.locAddProvider),
                    action: { showAddProvider = true }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(options) { option in
                            providerOptionRow(option)
                        }
                    }
                    .id(providerRevision)
                }
            }
        }
        .settingsCardFrame()
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func providerOptionRow(_ option: ProviderOption) -> some View {
        let enabled = isProviderEnabled(option)
        let isSelected = detailProviderID == option.id
        let toggleable = isToggleableProvider(option)

        return HStack(spacing: 8) {
            if toggleable {
                Toggle("", isOn: Binding(
                    get: { isProviderEnabled(option) },
                    set: { setProviderEnabled(option, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(VuexySwitchStyle(width: 40, height: 24))
                .help(enabled ? L.t(AppLocalizationKey.locDisable) : L.t(AppLocalizationKey.locEnable))
            } else {
                Circle()
                    .fill(option.isConnected ? Color.mimo.success : Color.mimo.textMuted)
                    .frame(width: 7, height: 7)
                    .frame(width: 18)
            }

            Button(action: { selectProvider(option) }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.name)
                        .interfaceFont(size: 12, weight: isSelected ? .semibold : .regular)
                        .foregroundColor(enabled ? Color.mimo.textPrimary : Color.mimo.textMuted)
                        .lineLimit(1)
                    Text(providerKindLabel(option))
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())

            if isSelected {
                Image(systemName: "checkmark")
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(Color.mimo.brand)
            }

            if isMutableProvider(option) {
                Menu {
                    Button {
                        selectProvider(option)
                    } label: {
                        Label(L.t("Edit provider"), systemImage: "pencil")
                    }
                    Button {
                        refreshProvider(option)
                    } label: {
                        Label(L.t(AppLocalizationKey.locRefreshModels), systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        providerPendingDelete = option
                    } label: {
                        Label(L.t(AppLocalizationKey.locRemoveProvider), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .interfaceFont(size: 11, weight: .bold)
                        .foregroundColor(Color.mimo.textMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            enabled
                ? (isSelected ? Color.mimo.subtleFill : Color.mimo.surface)
                : Color.gray.opacity(0.13)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.mimo.border : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(enabled ? 1 : 0.78)
        .contextMenu {
            Button(L.t("Edit provider")) { selectProvider(option) }
            if isMutableProvider(option) {
                Button(L.t(AppLocalizationKey.locRefreshModels)) { refreshProvider(option) }
                Divider()
                Button(role: .destructive) { providerPendingDelete = option } label: {
                    Text(L.t(AppLocalizationKey.locRemoveProvider))
                }
            }
        }
    }

    private var providerDetailColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t(AppLocalizationKey.locDetails))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)

                if let option = options.first(where: { $0.id == detailProviderID }) {
                    providerDetailHeader(option)

                    if let custom = customProvider(for: option.id) {
                        customProviderFields(custom)
                    }
                    if let local = localProvider(for: option.id) {
                        localProviderFields(local)
                    }
                    if let web = webConfig(for: option.id) {
                        webProviderFields(web)
                    }

                    providerActions(option)

                    if didRefreshProvider, let message = appState.providerModelLoadMessage(for: option.id) {
                        Text(message)
                            .interfaceFont(size: 10)
                            .foregroundColor(message.hasPrefix("Loaded") ? Color.mimo.success : Color.mimo.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let localRefreshMessage {
                        Text(localRefreshMessage)
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !appState.supportsToolcallForSelection && appState.selectedProviderID == option.id {
                        Text(L.t(AppLocalizationKey.locToolsUnavailableForCurrentModel))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.warning)
                    }
                } else {
                    SettingsCardEmptyState(
                        icon: "slider.horizontal.3",
                        title: L.t(AppLocalizationKey.locProviderSelected),
                        hint: L.t(AppLocalizationKey.locPickProviderTheLeftViewItsConnectionAndSettings)
                    )
                }
            }
        }
        .settingsCardFrame()
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { loadProviderDrafts() }
        .onChange(of: detailProviderID) { _ in loadProviderDrafts() }
    }

    private func providerDetailHeader(_ option: ProviderOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRenameableProvider(option) {
                TextField(L.t(AppLocalizationKey.locName), text: $providerNameDraft)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 13, weight: .semibold)
                    .focused($focusedProviderField, equals: .name)
                    .onSubmit { commitProviderName(option) }
                    .onChange(of: providerNameDraft) { _ in
                        scheduleProviderSave { commitProviderName(option) }
                    }
            } else {
                Text(option.name)
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(option.isConnected ? Color.mimo.success : Color.mimo.warning)
                    .frame(width: 8, height: 8)
                Text(providerKindLabel(option))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
                if isToggleableProvider(option), !isProviderEnabled(option) {
                    Text(L.t(AppLocalizationKey.locDisabled))
                        .interfaceFont(size: 9, weight: .medium)
                        .foregroundColor(Color.mimo.warning)
                }
            }

            if appState.selectedProviderID == option.id, !appState.selectedModel.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.brand)
                    Text(appState.selectedModel)
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.mimo.brand.opacity(0.08))
                .clipShape(Capsule())
            }
        }
    }

    private func customProviderFields(_ custom: CustomProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(AppLocalizationKey.locBaseUrl))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                TextField("https://api.example.com/v1", text: $customBaseURLDraft)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 11, design: .monospaced)
                    .focused($focusedProviderField, equals: .baseURL)
                    .onSubmit { commitCustomProviderDraft(custom.id) }
                    .onChange(of: customBaseURLDraft) { _ in
                        scheduleProviderSave { commitCustomProviderDraft(custom.id) }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(AppLocalizationKey.locApiKey))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                SecureField(custom.type == .openModel ? "om-..." : "sk-...", text: $customAPIKeyDraft)
                    .zcodeTextFieldStyle()
                    .focused($focusedProviderField, equals: .apiKey)
                    .onSubmit { commitCustomProviderDraft(custom.id) }
                    .onChange(of: customAPIKeyDraft) { _ in
                        scheduleProviderSave { commitCustomProviderDraft(custom.id) }
                    }
            }

            Toggle(L.t(AppLocalizationKey.locEnableToolCalling), isOn: Binding(
                get: { custom.supportsTools },
                set: { newValue in
                    guard let index = appState.customProviders.firstIndex(where: { $0.id == custom.id }) else { return }
                    var updated = appState.customProviders[index]
                    updated.supportsTools = newValue
                    appState.updateCustomProvider(updated)
                }
            ))
            .toggleStyle(VuexySwitchStyle())
            .interfaceFont(size: 11)

            if custom.type == .openCodeZen {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .foregroundColor(Color.mimo.violet)
                    Text(OpenCodeZenCatalog.accessSummary(hasAPIKey: !(custom.getSecureAPIKey() ?? "").isEmpty))
                        .interfaceFont(size: 10, weight: .medium)
                        .foregroundColor(Color.mimo.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.mimo.violet.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if custom.type == .acp {
                Toggle(L.t(AppLocalizationKey.locEnableACP), isOn: Binding(
                    get: { custom.acpEnabled },
                    set: { newValue in
                        guard let index = appState.customProviders.firstIndex(where: { $0.id == custom.id }) else { return }
                        var updated = appState.customProviders[index]
                        updated.acpEnabled = newValue
                        appState.updateCustomProvider(updated)
                    }
                ))
                .toggleStyle(VuexySwitchStyle())
                .interfaceFont(size: 11)
            }
        }
    }

    private func localProviderFields(_ local: LocalProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(AppLocalizationKey.locHost))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                TextField("127.0.0.1", text: $localHostDraft)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 11, design: .monospaced)
                    .focused($focusedProviderField, equals: .host)
                    .onSubmit { commitLocalProviderDraft(local.id) }
                    .onChange(of: localHostDraft) { _ in
                        scheduleProviderSave { commitLocalProviderDraft(local.id) }
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(AppLocalizationKey.locPort))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                TextField(String(local.port), text: $localPortDraft)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 11, design: .monospaced)
                    .focused($focusedProviderField, equals: .port)
                    .onSubmit { commitLocalProviderDraft(local.id) }
                    .onChange(of: localPortDraft) { _ in
                        scheduleProviderSave { commitLocalProviderDraft(local.id) }
                    }
            }
        }
    }

    private func webProviderFields(_ web: WebProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(web.chatURL)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textMuted)
                .lineLimit(2)
            Text(WebProviderConnectivity.connectionSummary(web, connected: true))
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textSecondary)
        }
    }

    private func providerActions(_ option: ProviderOption) -> some View {
        HStack(spacing: 12) {
            Button {
                didRefreshProvider = true
                refreshProvider(option)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.brand)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locRefreshModels))

            Spacer()

            if isMutableProvider(option) {
                Button(role: .destructive) {
                    providerPendingDelete = option
                } label: {
                    Image(systemName: "trash")
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(Color.mimo.error)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locRemoveProvider))
            }
        }
        .padding(.top, 2)
    }

    private func loadProviderDrafts() {
        guard let option = options.first(where: { $0.id == detailProviderID }) else { return }
        providerNameDraft = option.name
        didRefreshProvider = false
        localRefreshMessage = nil
        if let custom = customProvider(for: option.id) {
            customBaseURLDraft = custom.baseURL
            customAPIKeyDraft = custom.getSecureAPIKey() ?? ""
        }
        if let local = localProvider(for: option.id) {
            localHostDraft = local.host
            localPortDraft = String(local.port)
        }
    }

    private var selectedParameterMetadata: MimoProviderModel? {
        guard !parameterModelID.isEmpty else { return nil }
        return ProviderSettingsLogic.model(
            for: parameterModelID,
            in: appState.serverProviders,
            providerID: parameterProviderID.isEmpty ? nil : parameterProviderID
        )
    }

    private var selectedWebModel: WebProviderModel? {
        guard !parameterModelID.isEmpty,
              let web = webConfig(for: parameterProviderID) else { return nil }
        return web.discoveredModels.first(where: { $0.name == parameterModelID })
    }

    @ViewBuilder
    private var modelParametersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t(AppLocalizationKey.locModelParameters))
                        .interfaceFont(size: 14, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text("\(parameterProviderID.isEmpty ? L.t(AppLocalizationKey.locProvider) : parameterProviderID) / \(parameterModelID)")
                        .interfaceFont(size: 10, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                }
                Spacer()
                Button {
                    parameterModelID = ""
                    parameterError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .interfaceFont(size: 15)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .accessibilityLabel(L.t(AppLocalizationKey.locCloseModelParameters))
            }

            if let webModel = selectedWebModel {
                webProfilePanel(webModel)
            }

            if let meta = selectedParameterMetadata {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L.t(AppLocalizationKey.locProviderMetadata))
                        .interfaceFont(size: 11, weight: .semibold)
                        .foregroundColor(Color.mimo.textSecondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                        metadataValue(L.t(AppLocalizationKey.locParamContext), meta.limit?.context.map { "\($0 / 1000)k" } ?? "—")
                        metadataValue(L.t(AppLocalizationKey.locParamOutput), meta.limit?.output.map { String($0) } ?? "—")
                        metadataValue(L.t(AppLocalizationKey.locParamReasoning), meta.capabilities?.reasoning == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        metadataValue(L.t(AppLocalizationKey.locParamTools), meta.capabilities?.toolcall != false ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        metadataValue(L.t(AppLocalizationKey.locParamPlan), meta.capabilities?.plan == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        metadataValue(L.t(AppLocalizationKey.locParamVariants), meta.variants.map { String($0.count) } ?? "—")
                    }
                }
            } else if selectedWebModel == nil {
                Text(L.t(AppLocalizationKey.locNoModelMetadata))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }

            HStack(spacing: 10) {
                parameterField(title: L.t(AppLocalizationKey.locTemperature), placeholder: L.t(AppLocalizationKey.locDefault), text: $parameterTemperature)
                parameterField(title: L.t(AppLocalizationKey.locMaxTokens), placeholder: L.t(AppLocalizationKey.locDefault), text: $parameterMaxTokens)
                parameterField(title: L.t(AppLocalizationKey.locTopP), placeholder: L.t(AppLocalizationKey.locDefault), text: $parameterTopP)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(L.t(AppLocalizationKey.locSystemPromptOverride))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                TextEditor(text: $parameterSystemPrompt)
                    .font(.system(size: 11))
                    .frame(minHeight: 58, maxHeight: 100)
                    .padding(6)
                    .background(Color.mimo.background)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
            }

            if let parameterError {
                Text(parameterError)
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(L.t(AppLocalizationKey.locBlankValuesProviderDefaults))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Button(L.t(AppLocalizationKey.locResetParameters)) { resetParameters() }
                    .buttonStyle(HandCursorButtonStyle())
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                Button(L.t(AppLocalizationKey.locSaveParameters)) { saveParameters() }
                    .buttonStyle(.borderedProminent)
                    .interfaceFont(size: 11)
            }
        }
        .padding(14)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mimo.brand.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func webProfilePanel(_ model: WebProviderModel) -> some View {
        let metadataBackground: Color = Color.mimo.backgroundAlt.opacity(0.45)
        return VStack(alignment: .leading, spacing: 7) {
            Text(L.t(AppLocalizationKey.locLiveWebProfile))
                .interfaceFont(size: 11, weight: .semibold)
                .foregroundColor(Color.mimo.textSecondary)
            HStack(spacing: 6) {
                Text(model.discoveryStatus == .active ? L.t(AppLocalizationKey.locActive) : L.t(model.discoveryStatus.rawValue))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(model.discoveryStatus == .active ? Color.mimo.success : Color.mimo.warning)
                Text(model.parameterProfile.availableKeys.isEmpty ? L.t(AppLocalizationKey.locNoParameterControls) : model.parameterProfile.availableKeys.joined(separator: ", "))
                    .interfaceFont(size: 10, design: .monospaced)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(2)
            }
            let detected = model.parameterProfile.values
            Text(L.t(AppLocalizationKey.locDetectedDefaults, "temperature \(detected.temperature.map { String(describing: $0) } ?? "—") · max tokens \(detected.maxTokens.map { String(describing: $0) } ?? "—") · top P \(detected.topP.map { String(describing: $0) } ?? "—")"))
                .interfaceFont(size: 10, design: .monospaced)
                .foregroundColor(Color.mimo.textMuted)
                .lineLimit(2)
            if !model.parameterProfile.labels.isEmpty {
                Text(L.t(AppLocalizationKey.locDetectedLabels, model.parameterProfile.labels.joined(separator: ", ")))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(metadataBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func metadataValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .interfaceFont(size: 8, weight: .bold)
                .foregroundColor(Color.mimo.textMuted)
            Text(value)
                .interfaceFont(size: 10, weight: .medium)
                .foregroundColor(Color.mimo.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parameterField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .interfaceFont(size: 10, weight: .medium)
                .foregroundColor(Color.mimo.textSecondary)
            TextField(placeholder, text: text)
                .zcodeTextFieldStyle()
                .interfaceFont(size: 11, design: .monospaced)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openParameters(modelID: String, providerID: String) {
        parameterModelID = modelID
        parameterProviderID = providerID
        let params = ModelCallParametersStore.parameters(for: modelID)
        parameterTemperature = params.temperature.map { String($0) } ?? ""
        parameterMaxTokens = params.maxTokens.map { String($0) } ?? ""
        parameterTopP = params.topP.map { String($0) } ?? ""
        parameterSystemPrompt = params.systemPrompt ?? ""
        parameterError = nil
    }

    private func resetParameters() {
        parameterTemperature = ""
        parameterMaxTokens = ""
        parameterTopP = ""
        parameterSystemPrompt = ""
        saveParameters()
    }

    private func saveParameters() {
        guard !parameterModelID.isEmpty else { return }
        let trimmedTemperature = parameterTemperature.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMaxTokens = parameterMaxTokens.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopP = parameterTopP.trimmingCharacters(in: .whitespacesAndNewlines)
        let temperature = trimmedTemperature.isEmpty ? nil : Double(trimmedTemperature)
        let maxTokens = trimmedMaxTokens.isEmpty ? nil : Int(trimmedMaxTokens)
        let topP = trimmedTopP.isEmpty ? nil : Double(trimmedTopP)
        guard trimmedTemperature.isEmpty || temperature != nil,
              trimmedMaxTokens.isEmpty || maxTokens != nil,
              trimmedTopP.isEmpty || topP != nil else {
            parameterError = L.t(AppLocalizationKey.locUseNumericParameters)
            return
        }
        if let temperature, !(0...2).contains(temperature) {
            parameterError = L.t(AppLocalizationKey.locTemperatureRange)
            return
        }
        if let maxTokens, maxTokens <= 0 {
            parameterError = L.t(AppLocalizationKey.locMaxTokensRange)
            return
        }
        if let topP, !(0...1).contains(topP) {
            parameterError = L.t(AppLocalizationKey.locTopPRange)
            return
        }
        ModelCallParametersStore.set(
            ModelCallParameters(
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP,
                systemPrompt: {
                    let trimmed = parameterSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }()
            ),
            for: parameterModelID
        )
        parameterError = nil
    }

    /// Разделить modelID на префикс (провайдер) и имя модели
    /// Например "oc/deepseek" → ("oc", "deepseek"), "gpt-4" → (nil, "gpt-4")
    static func splitModelID(_ modelID: String) -> (prefix: String?, name: String) {
        ModelGroupingLogic.splitModelID(modelID)
    }

    private var modelsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t(AppLocalizationKey.locModels))
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Menu {
                    ForEach(ModelSortOrder.allCases) { order in
                        Button {
                            modelSortOrder = order
                        } label: {
                            Label(order.title, systemImage: modelSortOrder == order ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }
                } label: {
                    Label(L.t(AppLocalizationKey.locSortModels, modelSortOrder.title), systemImage: "arrow.up.arrow.down")
                        .interfaceFont(size: 10, weight: .medium)
                        .foregroundColor(Color.mimo.brand)
                }
                .menuStyle(.borderlessButton)
            }

            let providerID = detailProviderID.isEmpty ? appState.selectedProviderID : detailProviderID
            let allModels = models(for: providerID)
            let filteredModels = visibleModelIDs(allModels, providerID: providerID)
            let displayModels = ModelSettingsListLogic.visibleModels(filteredModels, query: "")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                TextField(L.t(AppLocalizationKey.locFilterModels), text: $modelSearchQuery)
                    .textFieldStyle(.plain)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textPrimary)
                if !modelSearchQuery.isEmpty {
                    Button {
                        modelSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.mimo.background)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if allModels.isEmpty {
                SettingsCardEmptyState(
                    icon: "cpu",
                    title: L.t(AppLocalizationKey.locModelsLoaded),
                    hint: providerID.isEmpty
                        ? L.t(AppLocalizationKey.locSelectProviderToBrowseModels)
                        : L.t(AppLocalizationKey.locStartLocalAgentOrCheck)
                )
            } else if filteredModels.isEmpty {
                Text(L.t(AppLocalizationKey.locNoModelsMatchFilter))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.vertical, 8)
            } else {
                Text(L.t(AppLocalizationKey.locModelsCountOf, filteredModels.count, allModels.count))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(displayModels, id: \.self) { modelID in
                            compactModelCard(modelID: modelID, providerID: providerID, prefix: nil)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            if customProvider(for: providerID) != nil {
                HStack(spacing: 6) {
                    if newModelProviderID == providerID {
                        TextField(L.t("Model ID"), text: $newModelDraft)
                            .textFieldStyle(.plain)
                            .interfaceFont(size: 11, design: .monospaced)
                            .foregroundColor(Color.mimo.textPrimary)
                            .onSubmit { commitAddModel(providerID: providerID) }
                        Button(action: { commitAddModel(providerID: providerID) }) {
                            Image(systemName: "checkmark")
                                .interfaceFont(size: 11, weight: .semibold)
                                .foregroundColor(Color.mimo.success)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        Button(action: {
                            newModelProviderID = ""
                            newModelDraft = ""
                        }) {
                            Image(systemName: "xmark")
                                .interfaceFont(size: 11, weight: .semibold)
                                .foregroundColor(Color.mimo.textMuted)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HandCursorButtonStyle())
                    } else {
                        Button {
                            newModelProviderID = providerID
                            newModelDraft = ""
                        } label: {
                            Label(L.t("Add custom model"), systemImage: "plus")
                                .interfaceFont(size: 11, weight: .medium)
                                .foregroundColor(Color.mimo.brand)
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        Spacer()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.mimo.background)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

        }
        .settingsCardFrame()
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func visibleModelIDs(_ models: [String], providerID: String) -> [String] {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? models : models.filter { modelID in
            let meta = ProviderSettingsLogic.model(
                for: modelID,
                in: appState.serverProviders,
                providerID: providerID.isEmpty ? nil : providerID
            )
            return modelID.localizedCaseInsensitiveContains(query)
                || (meta?.name?.localizedCaseInsensitiveContains(query) == true)
        }
        return filtered.sorted { lhs, rhs in
            switch modelSortOrder {
            case .name:
                return Self.splitModelID(lhs).name.localizedCaseInsensitiveCompare(Self.splitModelID(rhs).name) == .orderedAscending
            case .context:
                let left = ProviderSettingsLogic.model(for: lhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.limit?.context ?? -1
                let right = ProviderSettingsLogic.model(for: rhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.limit?.context ?? -1
                return left == right ? lhs < rhs : left > right
            case .reasoning:
                let left = ProviderSettingsLogic.model(for: lhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.reasoning == true
                let right = ProviderSettingsLogic.model(for: rhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.reasoning == true
                return left == right ? lhs < rhs : left && !right
            case .tools:
                let left = ProviderSettingsLogic.model(for: lhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.toolcall != false
                let right = ProviderSettingsLogic.model(for: rhs, in: appState.serverProviders, providerID: providerID.isEmpty ? nil : providerID)?.capabilities?.toolcall != false
                return left == right ? lhs < rhs : left && !right
            }
        }
    }

    @ViewBuilder
    private func compactModelCard(modelID: String, providerID: String, prefix: String?) -> some View {
        if isEditingModel(modelID: modelID, providerID: providerID) {
            modelEditRow(modelID: modelID, providerID: providerID)
        } else if isEditingClone(modelID: modelID, providerID: providerID) {
            modelCloneRow(sourceModelID: modelID, providerID: providerID)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                modelDisplayRow(modelID: modelID, providerID: providerID, prefix: prefix)
                if parameterModelID == modelID {
                    modelParametersPanel
                        .padding(.leading, 18)
                        .padding(.bottom, 2)
                }
            }
        }
    }

    private func modelCloneRow(sourceModelID: String, providerID: String) -> some View {
        HStack(spacing: 6) {
            TextField(L.t("Model ID"), text: $cloneModelDraft)
                .textFieldStyle(.plain)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .onSubmit { commitClone(sourceModelID: sourceModelID, providerID: providerID) }
            Button(action: { commitClone(sourceModelID: sourceModelID, providerID: providerID) }) {
                Image(systemName: "checkmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.success)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            Button(action: {
                cloneSourceModelID = ""
                cloneModelProviderID = ""
                cloneModelDraft = ""
            }) {
                Image(systemName: "xmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.mimo.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func modelEditRow(modelID: String, providerID: String) -> some View {
        HStack(spacing: 6) {
            TextField(L.t("Model ID"), text: $editingModelDraft)
                .textFieldStyle(.plain)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .onSubmit { commitRename(modelID: modelID, providerID: providerID) }
            Button(action: { commitRename(modelID: modelID, providerID: providerID) }) {
                Image(systemName: "checkmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.success)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            Button(action: { cancelRename() }) {
                Image(systemName: "xmark")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.mimo.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func modelDisplayRow(modelID: String, providerID: String, prefix: String?) -> some View {
        let meta = ProviderSettingsLogic.model(
            for: modelID,
            in: appState.serverProviders,
            providerID: providerID.isEmpty ? nil : providerID
        )
        let isSelected = appState.selectedModel == modelID
        let shortName = Self.splitModelID(modelID).name
        let isDisabled = isModelDisabled(modelID, providerID: providerID)
        let isCustomModel = customProvider(for: providerID) != nil

        return HStack(spacing: 6) {
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.brand)
                    .frame(width: 14)
            } else {
                Circle()
                    .fill(Color.mimo.border)
                    .frame(width: 6, height: 6)
                    .padding(.horizontal, 4)
            }

            // Model name
            Text(shortName)
                .interfaceFont(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced)
                .foregroundColor(isDisabled ? Color.mimo.textMuted : (isSelected ? Color.mimo.brand : Color.mimo.textPrimary))
                .strikethrough(isDisabled)
                .lineLimit(1)

            if isDisabled {
                Text(L.t(AppLocalizationKey.locDisabled))
                    .interfaceFont(size: 9, weight: .medium)
                    .foregroundColor(Color.mimo.warning)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.mimo.warning.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Compact capability chips
            if meta?.capabilities?.reasoning == true {
                Text("R")
                    .interfaceFont(size: 8, weight: .bold, design: .monospaced)
                    .foregroundColor(Color.mimo.violet)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.mimo.violet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if meta?.capabilities?.toolcall != false {
                Text("T")
                    .interfaceFont(size: 8, weight: .bold, design: .monospaced)
                    .foregroundColor(Color.mimo.cyan)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.mimo.cyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if let context = meta?.limit?.context {
                Text("\(context / 1000)k")
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(1)
            }

            if meta?.cost != nil {
                Text("$")
                    .interfaceFont(size: 8, weight: .bold, design: .monospaced)
                    .foregroundColor(Color.mimo.warning)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.mimo.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Spacer(minLength: 4)

            // Three-dot menu
            Menu {
                // Selection is performed by clicking the full model row.
                // Keep the menu for parameters and secondary actions only.
                Button(action: {
                    openParameters(modelID: modelID, providerID: providerID)
                }) {
                    Label(L.t(AppLocalizationKey.locParameters), systemImage: "slider.horizontal.3")
                }

                if isCustomModel {
                    Button(action: {
                        beginRename(modelID, providerID: providerID)
                    }) {
                        Label(L.t("Rename model"), systemImage: "pencil")
                    }
                    Button(action: {
                        beginClone(modelID, providerID: providerID)
                    }) {
                        Label(L.t("Clone model"), systemImage: "plus.square.on.square")
                    }
                }

                Button(action: {
                    toggleModelDisabled(modelID, providerID: providerID)
                }) {
                    Label(
                        isDisabled ? L.t("Enable model") : L.t("Disable model"),
                        systemImage: isDisabled ? "checkmark.circle" : "slash.circle"
                    )
                }

                if canDeleteModels(providerID: providerID) {
                    Divider()
                    Button(role: .destructive) {
                        deleteModel(modelID, from: providerID)
                    } label: {
                        Label(L.t("Delete model"), systemImage: "trash")
                    }
                }

                if let meta = meta {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        let info = """
                        Model: \(meta.id)
                        Name: \(meta.name ?? "—")
                        Provider: \(meta.providerID ?? providerID)
                        Context: \(meta.limit?.context.map { "\($0/1000)k" } ?? "—")
                        Output: \(meta.limit?.output.map { "\($0)" } ?? "—")
                        Reasoning: \(meta.capabilities?.reasoning == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        Tools: \(meta.capabilities?.toolcall != false ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        Plan: \(meta.capabilities?.plan == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                        Cost: \(meta.cost.map { "\(String(describing: $0.input))/\(String(describing: $0.output)) per 1K" } ?? "—")
                        """
                        NSPasteboard.general.setString(info, forType: .string)
                    }) {
                        Label(L.t(AppLocalizationKey.locCopyInfo), systemImage: "doc.on.doc")
                    }
                }

                // OmniRouter/agentRouter special config
                if isAgentRouterModel(modelID: modelID, providerID: providerID) {
                    Divider()
                    Button(action: {
                        toggleToolResultFix(for: modelID)
                    }) {
                        Label(
                            isToolResultFixEnabled(for: modelID) ? L.t(AppLocalizationKey.locToolResultFixOn) : L.t(AppLocalizationKey.locToolResultFixOff),
                            systemImage: isToolResultFixEnabled(for: modelID) ? "checkmark.shield.fill" : "shield.slash"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.vertical")
                    .interfaceFont(size: 12, weight: .bold)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isDisabled
                ? Color.gray.opacity(0.13)
                : (isSelected ? Color.mimo.subtleFill : Color.clear)
        )
        .opacity(isDisabled ? 0.82 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.mimo.brand.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSelected, !isDisabled else { return }
            if !providerID.isEmpty {
                appState.selectProvider(providerID)
            }
            appState.selectModel(modelID)
        }
    }

    // MARK: - OmniRouter / agentRouter support

    /// Определяет, является ли модель agentRouter-совместимой
    private func isAgentRouterModel(modelID: String, providerID: String) -> Bool {
        let pid = providerID.lowercased()
        let mid = modelID.lowercased()
        return pid == "agentrouter" || pid == "omni" || pid == "omnirouter"
            || mid.contains("agentrouter") || mid.contains("omni")
    }

    /// Ключ UserDefaults для хранения включенности фикса формата tool result
    private func toolResultFixKey(for modelID: String) -> String {
        "com.mycoder.toolResultFix.\(modelID)"
    }

    /// Проверить включен ли фикс для модели
    private func isToolResultFixEnabled(for modelID: String) -> Bool {
        UserDefaults.standard.bool(forKey: toolResultFixKey(for: modelID))
    }

    /// Переключить фикс для модели
    private func toggleToolResultFix(for modelID: String) {
        let key = toolResultFixKey(for: modelID)
        let current = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(!current, forKey: key)
    }
}

struct CustomProviderCard: View {
    let provider: CustomProvider
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        SettingsCard {
            HStack {
                Image(systemName: provider.type.icon)
                    .interfaceFont(size: 20)
                Text(provider.name)
                    .interfaceFont(size: 14, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(provider.type.rawValue)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.mimo.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                
                Spacer()
                
                if provider.isEnabled {
                    Circle().fill(Color.mimo.success).frame(width: 8, height: 8)
                } else {
                    Circle().fill(Color.mimo.textMuted).frame(width: 8, height: 8)
                }
                
                Button(action: {
                    appState.removeCustomProvider(provider)
                }) {
                    Image(systemName: "trash")
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.error)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.t(AppLocalizationKey.locUrl))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                    Text(provider.baseURL)
                        .interfaceFont(size: 11, design: .monospaced)
                        .foregroundColor(Color.mimo.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                if !provider.models.isEmpty {
                    HStack {
                        Text(L.t(AppLocalizationKey.locModels1))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                        Text(L.t(AppLocalizationKey.locAvailableCount, provider.models.count))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                }
            }
        }
    }
}

struct AddProviderSheet: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var type: ProviderType
    @Binding var url: String
    @Binding var apiKey: String
    @EnvironmentObject var appState: AppState
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded: Bool?
    @State private var supportsTools = true
    @State private var acpEnabled = false
    @State private var requiresAPIKey = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t(AppLocalizationKey.locAddProvider))
                    .interfaceFont(size: 16, weight: .semibold)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .interfaceFont(size: 16)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            .padding(16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t(AppLocalizationKey.locProviderType))
                            .interfaceFont(size: 13, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                        
                        Picker(L.t(AppLocalizationKey.locProviderType), selection: $type) {
                            ForEach(ProviderType.allCases) { t in
                                Label(t.rawValue, systemImage: t.icon).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: type) { newType in
                            url = newType.defaultURL
                            requiresAPIKey = ProviderEndpointLogic.defaultRequiresAPIKey(for: newType)
                            if newType == .openCodeZen,
                               name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                name = L.t(AppLocalizationKey.locOpenCodeZen)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t(AppLocalizationKey.locName))
                            .interfaceFont(size: 13, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                        TextField(L.t(AppLocalizationKey.locProviderNameExample), text: $name)
                            .zcodeTextFieldStyle()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t(AppLocalizationKey.locBaseUrl))
                            .interfaceFont(size: 13, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                        TextField(L.t(AppLocalizationKey.locApiEndpointURL), text: $url)
                            .zcodeTextFieldStyle()
                            .interfaceFont(size: 12, design: .monospaced)
                        if !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           ProviderEndpointLogic.normalizedBaseURL(url) == nil {
                            Text(L.t(AppLocalizationKey.locInvalidEndpoint))
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.error)
                        }
                    }
                    
                    if type != .ollama && type != .acp && (requiresAPIKey || type == .openCodeZen) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(type == .openCodeZen ? L.t(AppLocalizationKey.locOpenCodeZenApiKeyOptional) : L.t(AppLocalizationKey.locApiKey))
                                .interfaceFont(size: 13, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                            SecureField(type == .openModel ? "om-..." : L.t(AppLocalizationKey.locSecretKeyPlaceholder), text: $apiKey)
                                .zcodeTextFieldStyle()
                            if type == .openCodeZen {
                                Text(L.t(AppLocalizationKey.locNoZenKeyDescription))
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textSecondary)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(type == .openCodeZen ? "Require a Zen API key" : L.t(AppLocalizationKey.locRequiresAPIKey), isOn: $requiresAPIKey)
                            .interfaceFont(size: 13, weight: .medium)
                        Text(L.t(AppLocalizationKey.locDisableForLocalModelsProvidersThatDontNeedAuthe))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L.t(AppLocalizationKey.locEnableToolCalling), isOn: $supportsTools)
                            .interfaceFont(size: 13, weight: .medium)
                        Text(L.t(AppLocalizationKey.locEnableFunctiontoolCallingSupportForThisProvider))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                    
                    if type == .acp {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(L.t(AppLocalizationKey.locEnableACP), isOn: $acpEnabled)
                                .interfaceFont(size: 13, weight: .medium)
                            Text(L.t(AppLocalizationKey.locEnableAgentCoderProtocolForAutonomousCodingTask))
                                .interfaceFont(size: 11)
                                .foregroundColor(Color.mimo.textSecondary)
                        }
                    }
                    
                    if let result = testResult, let succeeded = testSucceeded {
                        ProviderConnectionResultBanner(message: result, succeeded: succeeded)
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            HStack {
                Button(action: {
                    isTesting = true
                    Task {
                        let success = await appState.testProvider(
                            url: ProviderEndpointLogic.normalizedBaseURL(url) ?? url,
                            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            type: type
                        )
                        await MainActor.run {
                            isTesting = false
                            testSucceeded = success
                            testResult = success ? L.t(AppLocalizationKey.locConnectionSuccess) : L.t(AppLocalizationKey.locConnectionFailed)
                        }
                    }
                }) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(L.t(AppLocalizationKey.locTestConnection))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          ProviderEndpointLogic.normalizedBaseURL(url) == nil)
                
                Spacer()
                
                Button(L.t(AppLocalizationKey.locCancel)) {
                    isPresented = false
                }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.textSecondary)
                
                Button(action: {
                    guard let normalizedURL = ProviderEndpointLogic.normalizedBaseURL(url) else { return }
                    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let provider = CustomProvider(
                        id: UUID().uuidString,
                        name: normalizedName.isEmpty ? type.rawValue : normalizedName,
                        type: type,
                        baseURL: normalizedURL,
                        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        isEnabled: true,
                        models: [],
                        supportsTools: supportsTools,
                        acpEnabled: acpEnabled,
                        requiresAPIKey: requiresAPIKey
                    )
                    appState.addCustomProvider(provider)
                    isPresented = false
                    name = ""
                    url = ""
                    apiKey = ""
                    requiresAPIKey = true
                }) {
                    Text(L.t(AppLocalizationKey.locAddProvider))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             ProviderEndpointLogic.normalizedBaseURL(url) == nil
                             ? Color.mimo.textMuted : Color.mimo.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          ProviderEndpointLogic.normalizedBaseURL(url) == nil)
            }
            .padding(16)
        }
        .frame(width: 480, height: 600)
        .background(Color.mimo.background)
    }
}


private struct ProviderConnectionResultBanner: View {
    let message: String
    let succeeded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .interfaceFont(size: 17, weight: .semibold)
                .foregroundColor(succeeded ? Color.mimo.success : Color.mimo.error)
            VStack(alignment: .leading, spacing: 2) {
                Text(succeeded ? "Connection verified" : "Connection failed")
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(message)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background((succeeded ? Color.mimo.success : Color.mimo.error).opacity(0.13))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((succeeded ? Color.mimo.success : Color.mimo.error).opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
