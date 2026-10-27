import SwiftUI

struct UnifiedProvidersView: View {
    @EnvironmentObject var appState: AppState
    let availableWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            InternalModelsSection()
            Divider().background(Color.mimo.border)
            ModelSettingsView(availableWidth: availableWidth)
            Divider().background(Color.mimo.border)
            LocalProvidersSection()
            Divider().background(Color.mimo.border)
            WebProvidersSection()
        }
    }
}

/// Local provider configuration + auto-detection by host:port (plan Раздел 1
/// Блок 4 + Раздел 9 Блок 3). Uses ProviderAutoDetector / LocalProviderLogic.
struct LocalProvidersSection: View {
    @EnvironmentObject var appState: AppState
    @State private var address: String = "localhost:11434"
    @State private var detectUsername: String = ""
    @State private var detectPassword: String = ""
    @State private var detecting = false
    @State private var detectResult: String = ""
    @State private var locals: [LocalProviderConfig] = LocalProviderLogic.load()
    // E23: auto-detection must never add a provider on its own — it presents
    // the finding and the user explicitly confirms or cancels.
    @State private var pendingDetection: PendingDetection?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t(AppLocalizationKey.locLocalProviders))
                .interfaceFont(size: 18, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            Text(L.t(AppLocalizationKey.locRunModelsLocallyViaOllamaOpencodeMycoderCliserv))
                .interfaceFont(size: 13)
                .foregroundColor(Color.mimo.textSecondary)

            // Auto-detect by address
            HStack(spacing: 8) {
                TextField("localhost:11434 or 192.168.1.10:4096", text: $address)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 13)
                Button(action: { runAutoDetect() }) {
                    HStack(spacing: 4) {
                        if detecting { ProgressView().controlSize(.small) }
                        Image(systemName: "wand.and.stars")
                        Text(detecting ? L.t(AppLocalizationKey.locDetecting) : L.t(AppLocalizationKey.locAutoDetect))
                    }
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.brand)
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled(detecting)
                .help(L.t(AppLocalizationKey.locAutoDetect))
            }
            // Optional basic-auth for locked servers (`opencode serve`
            // answers 401 on every endpoint without it).
            HStack(spacing: 8) {
                TextField("Username (optional)", text: $detectUsername)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 12)
                SecureField("Password (optional)", text: $detectPassword)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 12)
            }

            if !detectResult.isEmpty {
                Text(detectResult)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
            }

            // Quick-add cards for the three local kinds
            HStack(spacing: 12) {
                ForEach(LocalProviderKind.allCases) { kind in
                    LocalProviderCard(kind: kind, isAdded: locals.contains { $0.kind == kind }) {
                        addLocal(kind: kind)
                    }
                }
            }

            // Configured local providers
            if !locals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(locals) { cfg in
                        LocalProviderRow(config: cfg,
                                         onRemove: { removeLocal(cfg) },
                                         onToggle: { toggleLocal(cfg, isEnabled: $0) },
                                         onSelect: { model in selectLocalModel(model, from: cfg) },
                                         onUpdate: { updateLocal($0) },
                                         onPassword: { updated, secret in saveLocalPassword(updated, secret) })
                    }
                }
                .padding(12)
                .background(Color.mimo.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .alert(item: $pendingDetection) { pending in
            Alert(
                title: Text(LocalProviderConfirmLogic.title(for: pending.info)),
                message: Text(LocalProviderConfirmLogic.message(for: pending.info,
                                                                host: pending.host,
                                                                port: pending.port)),
                primaryButton: .default(Text(L.t(AppLocalizationKey.locConfirmAndAdd))) {
                    confirmPendingDetection()
                },
                secondaryButton: .cancel {
                    // E23: a cancel must not leave "Detected: …" on screen —
                    // nothing was added, so say so.
                    detectResult = AutoDetectStatusText.cancelled()
                    pendingDetection = nil
                }
            )
        }
    }

    private func parseAddress() -> (host: String, port: Int)? {
        let parts = address.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        return (String(parts[0]), port)
    }

    private func runAutoDetect() {
        guard let (host, port) = parseAddress() else {
            detectResult = AutoDetectStatusText.invalidAddress()
            return
        }
        // E24/п.34: keep the non-local warning visible — it used to be set here
        // and then immediately wiped by `detectResult = ""` below, so the
        // "is this really your local server?" warning never displayed.
        let warning = AutoDetectStatusText.warningForNonLocal(host)
        let headers = LocalProviderConfig.basicAuthHeader(
            username: detectUsername, password: detectPassword).map { ["Authorization": $0] } ?? [:]
        detecting = true
        detectResult = ""
        Task {
            let probe = URLSessionProviderProbe()
            let info = await ProviderAutoDetector.detect(host: host, port: port, headers: headers, probe: probe)
            await MainActor.run {
                detecting = false
                let line: String
                if let info = info {
                    line = AutoDetectStatusText.detected(info, host: host, port: port)
                    // E23: never add on our own — hold the finding for the
                    // user's explicit confirm/cancel decision.
                    pendingDetection = PendingDetection(info: info, host: host, port: port,
                                                        username: detectUsername, password: detectPassword)
                } else {
                    line = AutoDetectStatusText.nothingDetected(host: host, port: port)
                }
                detectResult = [warning, line].compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    private func confirmPendingDetection() {
        guard let pending = pendingDetection else { return }
        var cfg = LocalProviderConfirmLogic.config(from: pending.info, host: pending.host, port: pending.port)
        cfg = LocalProviderConfirmLogic.applyCredentials(to: cfg, username: pending.username)
        if !pending.password.isEmpty {
            try? cfg.savePassword(pending.password)
        }
        if !LocalProviderConfirmLogic.isDuplicate(locals, of: cfg) {
            locals.append(cfg)
            LocalProviderLogic.save(locals)
        }
        detectResult = AutoDetectStatusText.confirmed(pending.info, host: pending.host, port: pending.port)
        pendingDetection = nil
        detectPassword = ""
    }

    private func selectLocalModel(_ model: String, from config: LocalProviderConfig) {
        let currentConfig = LocalProviderLogic.load().first(where: { $0.id == config.id }) ?? config
        guard currentConfig.models.contains(model) else { return }
        if appState.selectedProviderID != config.id {
            appState.selectProvider(config.id)
        }
        appState.selectModel(model)
    }

    private func addLocal(kind: LocalProviderKind) {
        guard !locals.contains(where: { $0.kind == kind }) else { return }
        locals.append(LocalProviderConfig(kind: kind))
        LocalProviderLogic.save(locals)
    }

    private func removeLocal(_ cfg: LocalProviderConfig) {
        locals.removeAll { $0.id == cfg.id }
        LocalProviderLogic.save(locals)
    }

    private func toggleLocal(_ cfg: LocalProviderConfig, isEnabled: Bool) {
        // One persisted mutation, then read the truth back instead of flipping
        // a local copy: the card and the send picker both follow the config.
        LocalProviderLogic.setEnabled(id: cfg.id, isEnabled: isEnabled)
        locals = LocalProviderLogic.load()
    }

    private func updateLocal(_ cfg: LocalProviderConfig) {
        if let idx = locals.firstIndex(where: { $0.id == cfg.id }) {
            locals[idx] = cfg
            LocalProviderLogic.save(locals)
        }
    }

    private func saveLocalPassword(_ cfg: LocalProviderConfig, _ secret: String) {
        try? cfg.savePassword(secret)
    }
}


/// A detected provider held for the user's explicit confirm/cancel decision
/// (E23). `Identifiable` so it can drive `.alert(item:)`.
struct PendingDetection: Identifiable {
    let id = UUID()
    let info: DetectedProviderInfo
    let host: String
    let port: Int
    /// Transient basic-auth for the confirm step (never persisted as-is:
    /// username lands on the config, password goes to the Keychain).
    var username: String = ""
    var password: String = ""
}

struct LocalProviderCard: View {
    let kind: LocalProviderKind
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .interfaceFont(size: 20)
                    .foregroundColor(Color.mimo.brand)
                Text(kind.displayName)
                    .interfaceFont(size: 12, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(isAdded ? L.t(AppLocalizationKey.locAdded) : L.t(AppLocalizationKey.locAdd))
                    .interfaceFont(size: 10)
                    .foregroundColor(isAdded ? Color.mimo.success : Color.mimo.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.mimo.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HandCursorButtonStyle())
        .disabled(isAdded)
        .help(isAdded ? L.t(AppLocalizationKey.locAdded) : L.t(AppLocalizationKey.locAdd))
    }
}

struct LocalProviderRow: View {
    @EnvironmentObject var appState: AppState
    let config: LocalProviderConfig
    let onRemove: () -> Void
    let onToggle: (Bool) -> Void
    let onSelect: (String) -> Void
    /// Persisted credential edits (username stored on the config).
    let onUpdate: (LocalProviderConfig) -> Void
    /// Password handoff — the section stores it in the Keychain.
    let onPassword: (LocalProviderConfig, String) -> Void

    @State private var refreshing = false
    @State private var models: [String] = []
    @State private var showModelPicker = false
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: config.kind.icon)
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.displayName)
                        .interfaceFont(size: 13, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(config.serveBaseURL)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                }
                Spacer()
                Button(action: { Task { await refreshModels() } }) {
                    HStack(spacing: 3) {
                        if refreshing { ProgressView().controlSize(.small) }
                        Image(systemName: "arrow.clockwise")
                        Text("\(models.count)")
                    }
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.brand)
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled(refreshing)
                .help(L.t(AppLocalizationKey.locRefreshModels))
                Toggle("", isOn: Binding(
                    // Read the persisted config, not the snapshot the card was
                    // created with: switching off must not wait for another
                    // unrelated state change.
                    get: { appState.isProviderEnabled(config.id) },
                    set: { isEnabled in onToggle(isEnabled) }
                ))
                .labelsHidden()
                .toggleStyle(.dotSized)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
                .help(appState.isProviderEnabled(config.id)
                    ? L.t(AppLocalizationKey.locDisable)
                    : L.t(AppLocalizationKey.locEnable))
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.error)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locRemoveProvider))
            }
            if !models.isEmpty {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130, maximum: 240), spacing: 6)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(models, id: \.self) { model in
                            Button(action: { selectModel(model) }) {
                                Text(model)
                                    .interfaceFont(size: 10)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isSelected(model) ? Color.mimo.brand.opacity(0.2) : Color.mimo.surface)
                                    .foregroundColor(isSelected(model) ? Color.mimo.brand : Color.mimo.textSecondary)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected(model) ? Color.mimo.brand : Color.mimo.border, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(HandCursorButtonStyle())
                            .help(model)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            // `opencode serve` locks every endpoint behind basic auth
            // (verified live) — credentials live here, password in Keychain.
            if config.kind == .openCode {
                HStack(spacing: 8) {
                    TextField("Username (default: opencode)", text: $username)
                        .zcodeTextFieldStyle()
                        .interfaceFont(size: 12)
                        .onSubmit { commitCredentials() }
                    SecureField("Password (OPENCODE_SERVER_PASSWORD)", text: $password)
                        .zcodeTextFieldStyle()
                        .interfaceFont(size: 12)
                        .onSubmit { commitCredentials() }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            models = config.models
            username = config.username
        }
    }

    private func commitCredentials() {
        var updated = config
        updated.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdate(updated)
        onPassword(updated, password)
        password = ""
    }

    private func isSelected(_ model: String) -> Bool {
        LocalModelSelectionLogic.isSelected(
            model,
            selectedProviderID: config.id,
            activeProviderID: appState.selectedProviderID,
            selectedModel: appState.selectedModel
        )
    }

    private func selectModel(_ model: String) {
        guard LocalModelSelectionLogic.modelAfterTap(model, catalog: models, current: nil) == model else { return }
        onSelect(model)
    }

    private func refreshModels() async {
        refreshing = true
        if let fetched = await LocalProviderLogic.fetchModels(for: config) {
            await MainActor.run {
                models = fetched
                // Persist fetched models back to config
                var updatedLocal = config
                updatedLocal.models = fetched
                var locals = LocalProviderLogic.load()
                if let idx = locals.firstIndex(where: { $0.id == config.id }) {
                    locals[idx] = updatedLocal
                    LocalProviderLogic.save(locals)
                }
            }
        }
        refreshing = false
    }
}

struct ProvidersSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddProvider = false
    @State private var providerFilter = ""
    @State private var newProviderName = ""
    @State private var newProviderType: ProviderType = .openAI
    @State private var newProviderURL = ""
    @State private var newProviderKey = ""
    
    private var filteredProviders: [ProviderOption] {
        if providerFilter.isEmpty {
            return appState.providerOptions
        }
        return appState.providerOptions.filter {
            $0.name.localizedCaseInsensitiveContains(providerFilter)
        }
    }
    
    private var providerCount: Int {
        appState.providerOptions.count
    }
    
    private var modelCount: Int {
        appState.availableModels.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locProviders))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            Text(L.t(AppLocalizationKey.locManageCustomModelProvidersAndViewServerconnecte))
                .interfaceFont(size: 14)
                .foregroundColor(Color.mimo.textSecondary)
            
            // Stats chips
            HStack(spacing: 16) {
                ProviderCountChip(title: L.t(AppLocalizationKey.locProviders), count: providerCount)
                ProviderCountChip(title: L.t(AppLocalizationKey.locModels), count: modelCount)
                Spacer()
            }
            
            // Search and add
            searchAndAddSection
            
            // Providers list
            providersList
            
            // Add provider sheet
            if showAddProvider {
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
    
    private var searchAndAddSection: some View {
        HStack {
            TextField(L.t(AppLocalizationKey.locSearchProviders), text: $providerFilter)
                .zcodeTextFieldStyle()
                .interfaceFont(size: 13)
            
            Button(action: { showAddProvider = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text(L.t(AppLocalizationKey.locAdd))
                }
                .interfaceFont(size: 13)
                .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locAddProvider1))
        }
    }
    
    private var providersList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t(AppLocalizationKey.locProviders))
                .interfaceFont(size: 16, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            
            if filteredProviders.isEmpty {
                Text(L.t(AppLocalizationKey.locProvidersConfigured))
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredProviders) { option in
                        ProviderRowView(option: option)
                    }
                }
                .padding(12)
                .background(Color.mimo.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Provider Count Chip

struct ProviderCountChip: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: title == L.t(AppLocalizationKey.locProviders) ? "server.rack" : "cpu")
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
            Text(title)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textSecondary)
            Text("\(count)")
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.brand)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.mimo.backgroundAlt.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Provider Row View

struct ProviderRowView: View {
    let option: ProviderOption
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: option.isCustom ? "network.badge" : "server")
                    .interfaceFont(size: 14)
                    .foregroundColor(option.isCustom ? Color.mimo.brand : Color.mimo.textSecondary)
                
                Text(option.name)
                    .interfaceFont(size: 13, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                
                Spacer()

                Toggle("", isOn: Binding(
                    get: { appState.isProviderEnabled(option.id) },
                    set: { appState.setProviderEnabled(option.id, isEnabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.dotSized)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
                .help(appState.isProviderEnabled(option.id)
                    ? L.t(AppLocalizationKey.locDisable)
                    : L.t(AppLocalizationKey.locEnable))

                Button(action: {
                    if option.isCustom,
                       let custom = appState.customProviders.first(where: { $0.id == option.id }) {
                        appState.removeCustomProvider(custom)
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .interfaceFont(size: 14)
                        .foregroundColor(Color.mimo.error.opacity(0.7))
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locRemoveProvider))
                .opacity(option.isCustom ? 1 : 0)
            }
            
            if option.isCustom,
               let custom = appState.customProviders.first(where: { $0.id == option.id }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(custom.baseURL)
                        .interfaceFont(size: 11, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack {
                        Text(L.t(AppLocalizationKey.locModelsCount, custom.models.count))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                        
                        if custom.supportsTools {
                            Image(systemName: "checkmark.circle")
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.cyan)
                        }
                        
                        if custom.acpEnabled {
                            Image(systemName: "gearshape")
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.violet)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Model Parameter Spoiler

struct ModelParameterSpoiler: View {
    let modelID: String
    let meta: MimoProviderModel?
    let providerID: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let meta = meta {
                VStack(alignment: .leading, spacing: 6) {
                    ParameterRow(
                        label: L.t(AppLocalizationKey.locParamContext),
                        value: ModelCapabilityLogic.contextLabel(
                            for: ContextWindowCatalog.limit(for: modelID, reported: meta.limit?.context)
                        )
                    )
                    ParameterRow(
                        label: L.t(AppLocalizationKey.locParamOutput),
                        value: "\(ContextWindowCatalog.outputLimit(for: modelID, reported: meta.limit?.output))"
                    )
                    ParameterRow(label: L.t(AppLocalizationKey.locParamReasoning), value: meta.capabilities?.reasoning == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                    ParameterRow(label: L.t(AppLocalizationKey.locParamTools), value: meta.capabilities?.toolcall != false ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))
                    ParameterRow(label: L.t(AppLocalizationKey.locParamPlan), value: meta.capabilities?.plan == true ? L.t(AppLocalizationKey.locYes) : L.t(AppLocalizationKey.locNo))

                    if let cost = meta.cost {
                        ParameterRow(label: L.t(AppLocalizationKey.locParamCost), value: "\(cost.input ?? 0)/\(cost.output ?? 0) \(L.t(AppLocalizationKey.locPer1KTokens))")
                    }

                    if let variants = meta.variants, !variants.isEmpty {
                        ParameterRow(label: L.t(AppLocalizationKey.locParamVariants), value: variants.keys.sorted().joined(separator: ", "))
                    }
                }
                .interfaceFont(size: 11)
            } else {
                Text(L.t(AppLocalizationKey.locParametersAvailable))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
        .padding(8)
        .background(Color.mimo.backgroundAlt.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private struct ParameterRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label + ":")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Text(value)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textPrimary)
            }
        }
    }
}

// MARK: - Model Detail Spoiler

struct ModelDetailSpoiler: View {
    let modelID: String
    let providerID: String
    let meta: MimoProviderModel?
    @EnvironmentObject var appState: AppState
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(L.t(AppLocalizationKey.locModelDetails))
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(isExpanded ? L.t(AppLocalizationKey.locCollapse) : L.t(AppLocalizationKey.locShow))
            
            if isExpanded, let meta = meta {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t(AppLocalizationKey.locConfiguration))
                        .interfaceFont(size: 11, weight: .semibold)
                        .foregroundColor(Color.mimo.textSecondary)
                    
                    ParameterDetailRow(label: "ID", value: meta.id)
                    ParameterDetailRow(label: L.t(AppLocalizationKey.locName), value: meta.name ?? "—")
                    ParameterDetailRow(label: L.t(AppLocalizationKey.locParamProvider), value: meta.providerID ?? providerID)

                    if let context = meta.limit?.context {
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamContextLength), value: "\(context)")
                    }

                    if let capabilities = meta.capabilities {
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamReasoning), value: capabilities.reasoning == true ? L.t(AppLocalizationKey.locSupported) : L.t(AppLocalizationKey.locNotSupported))
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamTools), value: capabilities.toolcall != false ? L.t(AppLocalizationKey.locSupported) : L.t(AppLocalizationKey.locNotSupported))
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamPlanMode), value: capabilities.plan == true ? L.t(AppLocalizationKey.locSupported) : L.t(AppLocalizationKey.locNotSupported))
                    }

                    if let variants = meta.variants, !variants.isEmpty {
                        ParameterDetailRow(label: L.t(AppLocalizationKey.locParamVariants), value: variants.keys.sorted().joined(separator: ", "))
                    }
                }
                .interfaceFont(size: 11)
                .padding(8)
                .background(Color.mimo.backgroundAlt)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    private struct ParameterDetailRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                Text(value)
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
            }
        }
    }
}
