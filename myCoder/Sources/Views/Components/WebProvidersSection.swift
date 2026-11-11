import SwiftUI

// Preference key for auto-sizing TextEditor height
private struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 28
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
/// Web-free provider management (Kimi/Qwen/ChatGPT) — plan Раздел 12 Блок 4.
/// Configure system prompt / model / effort / tool-call delay / keep-alive,
/// acknowledge ToS, and log in through the AntiBrowser cast. The login is
/// confirmed by a live page check and remembered in the provider config; the
/// persistent browser profile keeps the session itself.
struct WebProvidersSection: View {
    @EnvironmentObject var appState: AppState
    @State private var providers: [WebProviderConfig] = WebProviderStore.load()
    @State private var loginConfig: WebProviderConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t(AppLocalizationKey.locWebProvidersBrowser))
                .interfaceFont(size: 18, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            Text(L.t(AppLocalizationKey.locUseFreeWebModelsKimiQwenChatgptThroughControlle))
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textSecondary)

            HStack(spacing: 12) {
                ForEach([WebChatVendor.kimi, .qwen, .chatgpt, .claude]) { vendor in
                    Button(action: { addVendor(vendor) }) {
                        VStack(spacing: 6) {
                            Image(systemName: "globe")
                                .interfaceFont(size: 20).foregroundColor(Color.mimo.brand)
                            Text(vendor.displayName)
                                .interfaceFont(size: 12, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                            Text(providers.contains { $0.vendor == vendor } ? L.t(AppLocalizationKey.locAddAnotherAccount) : L.t(AppLocalizationKey.locAdd))
                                .interfaceFont(size: 10)
                                .foregroundColor(providers.contains { $0.vendor == vendor } ? Color.mimo.brand : Color.mimo.textMuted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.mimo.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(providers.contains { $0.vendor == vendor } ? L.t(AppLocalizationKey.locAddAnotherAccount) : L.t(AppLocalizationKey.locAdd))
                }
            }

            ForEach($providers) { $cfg in
                WebProviderCard(config: $cfg,
                                onSave: { save() },
                                onLogin: { beginLogin(for: cfg) },
                                onChangeLogin: { beginLogin(for: cfg) },
                                onRemove: { remove(cfg) },
                                onRefreshModels: { await refreshModels(for: cfg) },
                                onRefreshEffort: { await refreshEffort(for: cfg) })
            }
        }
        .sheet(item: $loginConfig) { cfg in
            WebProviderLoginView(config: cfg) {
                confirmLogin(for: cfg)
                loginConfig = nil
            }
        }
    }

    private func beginLogin(for cfg: WebProviderConfig) {
        // Вход в веб-провайдер — реальное использование браузерного движка:
        // поднимаем его здесь (лениво), а не при старте приложения.
        Task { await EngineStatusCenter.shared.start() }
        loginConfig = cfg
    }

    private func addVendor(_ vendor: WebChatVendor) {
        let outcome = WebAccountCloneLogic.next(for: vendor, in: providers)
        providers.append(outcome.config)
        save()
    }

    private func remove(_ cfg: WebProviderConfig) {
        providers.removeAll { $0.id == cfg.id }
        save()
        appState.clearWebRemoteChats(providerID: cfg.id)
        if appState.selectedProviderID == "web:\(cfg.id)" {
            appState.selectProvider("")
        }
    }

    private func save() {
        WebProviderStore.save(providers)
    }

    /// Живая проверка вкладки прошла: запоминаем отметку входа и сразу
    /// обновляем реальный список моделей. Файлы cookie не создаются.
    private func confirmLogin(for cfg: WebProviderConfig) {
        var refreshConfig = cfg
        if var updated = WebProviderStore.load().first(where: { $0.id == cfg.id }) {
            updated.loginConfirmedAt = Date()
            providers = WebProviderStore.upsert(updated, in: providers)
            save()
            refreshConfig = updated
        }
        appState.invalidateProviderConnectedCache()
        Task { await refreshModels(for: refreshConfig) }
    }

    /// Discover the vendor's real models from the page after connect (Round 9 A).
    private func refreshModels(for cfg: WebProviderConfig) async -> String? {
        let message = await appState.refreshWebModels(for: cfg)
        providers = WebProviderStore.load()
        return message
    }

    /// Refresh the complete per-model effort and parameter profile snapshot.
    private func refreshEffort(for cfg: WebProviderConfig) async -> String? {
        let result = await appState.refreshWebModelsAndEffort(for: cfg)
        providers = WebProviderStore.load()
        return "\(result.modelsMsg) \(result.effortMsg)"
    }
}


/// Editor for custom web-model ids. Users can add any model name manually;
/// it is appended to the provider's discoveredModels and persisted.
struct CustomModelEditor: View {
    @Binding var config: WebProviderConfig
    let onSave: () -> Void
    @State private var newModelName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(AppLocalizationKey.locCustomModels))
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.textMuted)

            // Existing manually added models with remove buttons. Discovered
            // vendor models are read-only and must not expose a no-op delete.
            if !config.manuallyAddedModels.isEmpty {
                ForEach(config.manuallyAddedModels, id: \.self) { model in
                    HStack(spacing: 6) {
                        Text(model)
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: {
                            config.removeCustomModel(model)
                            onSave()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .interfaceFont(size: 12)
                                .foregroundColor(Color.mimo.textMuted)
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .help(L.t(AppLocalizationKey.locRemove))
                    }
                }
            }

            // Add new custom model
            HStack(spacing: 6) {
                TextField(L.t(AppLocalizationKey.locAddModel), text: $newModelName)
                    .interfaceFont(size: 11)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addModel()
                    }
                Button(L.t(AppLocalizationKey.locAdd)) {
                    addModel()
                }
                .interfaceFont(size: 11)
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.brand)
                .disabled(newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(L.t(AppLocalizationKey.locAddModel))
            }
        }
    }

    private func addModel() {
        let name = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        config.addCustomModel(name)
        newModelName = ""
        onSave()
    }
}

/// Embedded login: opens the vendor's page in the AntiBrowser cast. The user
/// logs in once; «Подтвердить вход» runs a live page check and stores only a
/// confirmation mark in the provider config (plan Раздел 12 Блок 3 п.35).
/// Cookie files are not created — the persistent browser profile keeps the
/// session itself.
struct WebProviderLoginView: View {
    @State var config: WebProviderConfig
    let onConfirmed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detectResult: DetectResult?

    /// Мост вкладки логина провайдера (единый для всех login-поверхностей).
    private var loginBridge: AntiBrowserAutomationBridge {
        let tabKey = AntiBrowserTabManager.makeKey(providerID: config.id,
                                                  projectID: "global",
                                                  chatID: "provider-login")
        return AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
    }

    enum DetectResult: Identifiable {
        case detecting, found([WebProviderModel]), failed(String)
        var id: String {
            switch self {
            case .detecting: return "detecting"
            case .found(let m): return "found-\(m.count)"
            case .failed(let e): return "failed-\(e)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact header bar (Apple Design style) — shows real config status
            HStack(spacing: 8) {
                Text("\(L.t(AppLocalizationKey.locWebLoginTitle)) \(config.displayName)")
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)

                Spacer()

                // Live status: whether this provider's login is confirmed.
                if config.loginConfirmedAt != nil {
                    Label(L.t(AppLocalizationKey.locConnected), systemImage: "lock.fill")
                        .interfaceFont(size: 10).foregroundColor(Color.mimo.success)
                } else {
                    Label(L.t(AppLocalizationKey.locNotConfigured), systemImage: "exclamationmark.circle")
                        .interfaceFont(size: 10).foregroundColor(Color.mimo.warning)
                }

                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.circle")
                        .interfaceFont(size: 14)
                        Text(L.t(AppLocalizationKey.locBuiltInBrowserDetection))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                }
                .help(L.t(AppLocalizationKey.locBrowserDetectionHelp))

                Button(action: findModelsBuiltIn) {
                    HStack(spacing: 4) {
                        if case .detecting = detectResult {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.horizontal.circle")
                                .interfaceFont(size: 14)
                        }
                        Text(L.t(AppLocalizationKey.locDetectModels))
                            .interfaceFont(size: 11)
                    }
                    .foregroundColor(Color.mimo.brand)
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled({
                    if case .detecting = detectResult { return true }
                    return false
                }())
                .help(L.t(AppLocalizationKey.locFastDOMDetectionHelp))


                Button(action: confirmLogin) {
                    Text(L.t(AppLocalizationKey.locWebConfirmLogin))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.success)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locWebConfirmLoginHelp))

                // Close button (always available)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textSecondary)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locClose))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Inline detection result (compact, doesn't block the view)
            if let result = detectResult {
                detectionStatusBar(result)
            }

            Divider()
            ZStack {
                CastPanelHost(bridge: loginBridge)
            }
        }
        .frame(width: 900, height: 640)
        .task(id: config.id) {
            // Экран входа обязан ОТКРЫТЬ страницу провайдера: раньше вкладка
            // создавалась пустой (about:blank) и пользователь видел белый каст.
            // Уже открытую страницу не перезагружаем — сессия могла быть
            // начата в прошлый раз.
            let bridge = loginBridge
            let loginURL = (try? WebProviderCatalog.loadBundled().loginURL(for: config.vendor.id))
                ?? config.vendor.defaultChatURL
            if !loginURL.isEmpty {
                // Движок мог ещё запускаться (или мост создан до готовности,
                // тогда токен пуст и запросы получают 401). Ждём готовность
                // и повторяем навигацию, иначе экран остаётся пустым без
                // объяснения.
                for _ in 0..<60 {
                    if Task.isCancelled { return }
                    if EngineStatusCenter.shared.isReady { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                for _ in 0..<20 {
                    if Task.isCancelled { return }
                    let current = (try? await bridge.currentURL()) ?? ""
                    if !current.isEmpty && current != "about:blank" { break }
                    if (try? await bridge.navigate(to: loginURL)) != nil { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            // Round 30b: model/effort detection must happen AUTOMATICALLY and
            // immediately — the login page is already loading here, BEFORE the
            // user confirms the login. It never required a session, so it
            // should not wait for one (or for a manual button press).
            findModelsBuiltIn()
        }
    }

    @ViewBuilder
    private func detectionStatusBar(_ result: DetectResult) -> some View {
        HStack(spacing: 6) {
            switch result {
            case .detecting:
                ProgressView().controlSize(.mini)
                Text(L.t(AppLocalizationKey.locWebDetecting)).interfaceFont(size: 10)
            case .found(let models):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.mimo.success)
                    Text(L.t(AppLocalizationKey.locWebModelsFoundCount, models.count))
                    .interfaceFont(size: 10).foregroundColor(Color.mimo.textSecondary)
                ForEach(models.prefix(3)) { m in
                    Text(m.name).interfaceFont(size: 9)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.mimo.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if models.count > 3 {
                    Text("+\(models.count - 3)").interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                }
            case .failed(let err):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color.mimo.warning)
                Text(err).interfaceFont(size: 10).foregroundColor(Color.mimo.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.mimo.surface)
    }

    private func findModelsBuiltIn() {
        Task {
            await MainActor.run { detectResult = .detecting }
            let bridge = loginBridge
            let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
            let catalogModelSelector = catalogEntry?.modelDropdown ?? ""
            let customSelector = config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dropdownSelector = [customSelector, catalogModelSelector]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if dropdownSelector.isEmpty {
                await MainActor.run { detectResult = .failed(L.t(AppLocalizationKey.locNoSelectorFound)) }
                return
            }
            // Wait for full page hydration (up to 10s)
            for _ in 0..<40 {
                if (try? await bridge.exists(selector: dropdownSelector)) == true {
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            // Discover every nested model and then probe effort per model.
            // Effort is optional and never inferred from model labels.
            let models = await WebModelDiscovery.discoverAllModels(
                using: bridge,
                dropdownSelector: dropdownSelector,
                vendor: config.vendor
            ) ?? []
            let effortSelector = catalogEntry?.effortDropdown
            let profiledModels = await WebModelDiscovery.discoverModelCapabilities(
                using: bridge,
                dropdownSelector: dropdownSelector,
                vendor: config.vendor,
                models: models,
                effortDropdownSelector: effortSelector
            )
            let resolvedModels = profiledModels.isEmpty ? models : profiledModels
            let efforts = Array(Set(resolvedModels.flatMap(\.availableEfforts))).sorted { $0.rawValue < $1.rawValue }
            await MainActor.run {
                let updated = WebModelRefreshLogic.replacing(config: config, with: resolvedModels)
                var persisted = updated
                persisted.discoveredEffortLevels = efforts
                WebProviderStore.save(WebProviderStore.upsert(persisted, in: WebProviderStore.load()))
                config = persisted
                if resolvedModels.isEmpty {
                    detectResult = .failed(L.t(AppLocalizationKey.locNoModelsFound))
                } else {
                    detectResult = .found(resolvedModels)
                }
            }
        }
    }

    /// Живая проверка вкладки: читает cookie и текст страницы, не сохраняя их
    /// на диск. Подтверждает вход только при настоящей авторизации.
    private func confirmLogin() {
        Task {
            let bridge = loginBridge
            do {
                let cookieList = try await bridge.cookies()
                let pageText = (try? await bridge.pageText()) ?? ""
                let verdict = WebLoginVerificationLogic.verdict(
                    vendor: config.vendor,
                    cookies: cookieList,
                    pageText: pageText
                )
                guard verdict == .confirmed else {
                    await MainActor.run {
                        detectResult = .failed(WebLoginVerificationLogic.message(for: verdict))
                    }
                    return
                }
                await MainActor.run {
                    var updated = config
                    updated.loginConfirmedAt = Date()
                    WebProviderStore.save(WebProviderStore.upsert(updated, in: WebProviderStore.load()))
                    config = updated
                    onConfirmed()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    detectResult = .failed(error.localizedDescription)
                }
            }
        }
    }
}
