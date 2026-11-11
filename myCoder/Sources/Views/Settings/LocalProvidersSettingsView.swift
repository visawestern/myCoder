import SwiftUI

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
                TextField(L.t("Username (optional)"), text: $detectUsername)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 12)
                SecureField(L.t("Password (optional)"), text: $detectPassword)
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
                    TextField(L.t("Username (default: opencode)"), text: $username)
                        .zcodeTextFieldStyle()
                        .interfaceFont(size: 12)
                        .onSubmit { commitCredentials() }
                    SecureField(L.t("Password (OPENCODE_SERVER_PASSWORD)"), text: $password)
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
