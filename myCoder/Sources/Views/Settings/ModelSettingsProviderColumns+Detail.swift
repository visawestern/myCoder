import SwiftUI

extension ModelSettingsProviderColumns {
    var providerDetailColumn: some View {
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

    func providerDetailHeader(_ option: ProviderOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRenameableProvider(option) {
                InlineEditableField(
                    title: nil,
                    value: option.name,
                    placeholder: L.t(AppLocalizationKey.locName),
                    fontSize: 14,
                    fontWeight: .semibold
                ) { value in
                    providerNameDraft = value
                    commitProviderName(option)
                }
            } else {
                Text(option.name)
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
            }

            HStack(spacing: 6) {
                // Status is expressed by the text colour — no status dot.
                Text(option.isConnected ? L.t(AppLocalizationKey.locConnected) : L.t(AppLocalizationKey.locDisconnected))
                    .interfaceFont(size: 12)
                    .foregroundColor(option.isConnected ? Color.mimo.success : Color.mimo.warning)
                if !isProviderEnabled(option) {
                    Text(L.t(AppLocalizationKey.locDisabled))
                        .interfaceFont(size: 9, weight: .medium)
                        .foregroundColor(Color.mimo.warning)
                }
            }

            if appState.selectedProviderID == option.id, !appState.selectedModel.isEmpty {
                Text(appState.selectedModel)
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.brand)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.mimo.brand.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }

    func customProviderFields(_ custom: CustomProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineEditableField(
                title: L.t(AppLocalizationKey.locBaseUrl),
                value: custom.baseURL,
                placeholder: "https://api.example.com/v1",
                monospaced: true
            ) { value in
                guard ProviderEndpointLogic.normalizedBaseURL(value) != nil else { return }
                customBaseURLDraft = value
                commitCustomProviderDraft(custom.id)
            }

            let key = custom.getSecureAPIKey() ?? ""
            InlineEditableField(
                title: L.t(AppLocalizationKey.locApiKey),
                value: key.isEmpty ? "" : "••••••••••••",
                placeholder: custom.type == .openModel ? "om-..." : "sk-...",
                isSecure: true,
                editValue: key
            ) { value in
                customAPIKeyDraft = value
                commitCustomProviderDraft(custom.id)
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

            quotaFields(custom)
        }
    }

    /// Quota settings for one custom provider: provider-wide request limit
    /// (cross-chat), token quota per minute (e.g. Google ~250k/min), per-key
    /// request limit, and the API-key pool (one key per line). All default to
    /// 0 = unlimited. Live usage for this provider is shown below the editor.
    func quotaFields(_ custom: CustomProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Quotas"))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)

            InlineEditableField(
                title: L.t("Request limit per minute (0 = unlimited)"),
                value: custom.requestLimitPerMinute > 0 ? String(custom.requestLimitPerMinute) : "0",
                placeholder: "0"
            ) { value in
                customRequestLimitDraft = value
                commitCustomProviderDraft(custom.id)
            }

            InlineEditableField(
                title: L.t("Token quota per minute, e.g. 250000 (0 = unlimited)"),
                value: custom.tokenQuotaPerMinute > 0 ? String(custom.tokenQuotaPerMinute) : "0",
                placeholder: "0"
            ) { value in
                customTokenQuotaDraft = value
                commitCustomProviderDraft(custom.id)
            }

            InlineEditableField(
                title: L.t("Per-API-key request limit per minute (0 = unlimited)"),
                value: custom.apiKeyLimitPerMinute > 0 ? String(custom.apiKeyLimitPerMinute) : "0",
                placeholder: "0"
            ) { value in
                customPerKeyLimitDraft = value
                commitCustomProviderDraft(custom.id)
            }

            Text(L.t("API key pool (one per line; the primary key above is used first)"))
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.textSecondary)
            TextEditor(text: $apiKeysPoolText)
                .frame(height: 64)
                .zcodeTextFieldStyle()
                .interfaceFont(size: 11, design: .monospaced)
                .onChange(of: apiKeysPoolText) { _ in
                    commitCustomProviderDraft(custom.id)
                }

            QuotaStatusView(providerID: custom.id)
        }
    }

    func localProviderFields(_ local: LocalProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineEditableField(
                title: L.t(AppLocalizationKey.locHost),
                value: local.host,
                placeholder: "127.0.0.1",
                monospaced: true
            ) { value in
                localHostDraft = value
                commitLocalProviderDraft(local.id)
            }
            InlineEditableField(
                title: L.t(AppLocalizationKey.locPort),
                value: String(local.port),
                monospaced: true
            ) { value in
                localPortDraft = value
                commitLocalProviderDraft(local.id)
            }
        }
    }

    func webProviderFields(_ web: WebProviderConfig) -> some View {
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

    func providerActions(_ option: ProviderOption) -> some View {
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

    func loadProviderDrafts() {
        guard let option = options.first(where: { $0.id == detailProviderID }) else { return }
        providerNameDraft = option.name
        didRefreshProvider = false
        localRefreshMessage = nil
        if let custom = customProvider(for: option.id) {
            customBaseURLDraft = custom.baseURL
            customAPIKeyDraft = custom.getSecureAPIKey() ?? ""
            customRequestLimitDraft = custom.requestLimitPerMinute > 0 ? String(custom.requestLimitPerMinute) : ""
            customTokenQuotaDraft = custom.tokenQuotaPerMinute > 0 ? String(custom.tokenQuotaPerMinute) : ""
            customPerKeyLimitDraft = custom.apiKeyLimitPerMinute > 0 ? String(custom.apiKeyLimitPerMinute) : ""
            apiKeysPoolText = ProviderAPIKeyPoolStore.load(providerID: custom.id).joined(separator: "\n")
        }
        if let local = localProvider(for: option.id) {
            localHostDraft = local.host
            localPortDraft = String(local.port)
        }
    }
}
