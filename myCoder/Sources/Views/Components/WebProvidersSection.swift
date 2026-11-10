import SwiftUI
import WebKit

// Preference key for auto-sizing TextEditor height
private struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 28
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
/// Web-free provider management (Kimi/Qwen/ChatGPT) — plan Раздел 12 Блок 4.
/// Configure system prompt / model / effort / tool-call delay / keep-alive,
/// acknowledge ToS, and log in via an embedded web view that captures cookies.
struct WebProvidersSection: View {
    @EnvironmentObject var appState: AppState
    @State private var providers: [WebProviderConfig] = WebProviderStore.load()
    @State private var loginConfig: WebProviderConfig?
    @State private var loginSessionID: String = WebSessionManager.defaultSessionID
    @State private var loginSessionName: String = "Default login"

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
                                onLogin: { beginLogin(for: cfg, newSession: false) },
                                onChangeLogin: { beginLogin(for: cfg, newSession: true) },
                                onSelectSession: { sessionID in activateSession(sessionID, for: cfg) },
                                onRemove: { remove(cfg) },
                                onRefreshModels: { await refreshModels(for: cfg) },
                                onRefreshEffort: { await refreshEffort(for: cfg) },
                                homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            }
        }
        .sheet(item: $loginConfig) { cfg in
            WebProviderLoginView(config: cfg) { session in
                persistSession(session, for: cfg, sessionID: loginSessionID, sessionName: loginSessionName)
                loginConfig = nil
            }
        }
    }

    private func beginLogin(for cfg: WebProviderConfig, newSession: Bool) {
        // Вход в веб-провайдер — реальное использование браузерного движка:
        // поднимаем его здесь (лениво), а не при старте приложения.
        Task { await EngineStatusCenter.shared.start() }
        loginSessionID = newSession ? UUID().uuidString : (cfg.activeSessionID ?? WebSessionManager.defaultSessionID)
        loginSessionName = newSession
            ? "Login \(Date().formatted(date: .abbreviated, time: .shortened))"
            : (cfg.activeSessionName ?? "Default login")
        loginConfig = cfg
    }

    private func activateSession(_ sessionID: String, for cfg: WebProviderConfig) {
        var updated = cfg
        let sessions = WebSessionManager.list(providerId: cfg.id, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        updated.activeSessionID = sessionID
        updated.activeSessionName = sessions.first(where: { $0.id == sessionID })?.name
        providers = WebProviderStore.upsert(updated, in: providers)
        save()
    }

    private func addVendor(_ vendor: WebChatVendor) {
        let outcome = WebAccountCloneLogic.next(for: vendor, in: providers)
        providers.append(outcome.config)
        save()
    }

    private func remove(_ cfg: WebProviderConfig) {
        providers.removeAll { $0.id == cfg.id }
        save()
        try? WebSessionManager.clear(providerId: cfg.id,
                                      homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        appState.clearWebRemoteChats(providerID: cfg.id)
        if appState.selectedProviderID == "web:\(cfg.id)" {
            appState.selectProvider("")
        }
    }

    private func save() {
        WebProviderStore.save(providers)
    }

    private func persistSession(_ store: WebSessionStore,
                                for cfg: WebProviderConfig,
                                sessionID: String,
                                sessionName: String) {
        do {
            try WebSessionManager.persist(store,
                                          providerId: cfg.id,
                                          homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                          sessionID: sessionID,
                                          sessionName: sessionName)
        } catch {
            appState.notificationService.error(
                title: "Web session not saved",
                message: "Could not save \(cfg.displayName) login: \(error.localizedDescription)"
            )
            return
        }
        guard WebLoginCaptureLogic.shouldActivateSession(
            cookieCount: store.cookies.count,
            persistenceSucceeded: true
        ) else { return }
        var refreshConfig = cfg
        if var updated = WebProviderStore.load().first(where: { $0.id == cfg.id }) {
            updated.activeSessionID = sessionID
            updated.activeSessionName = sessionName
            providers = WebProviderStore.upsert(updated, in: providers)
            save()
            refreshConfig = updated
        }
        // Refresh the real model+capability list using the newly captured named
        // session, never the old session from the login sheet's input config.
        Task { await refreshModels(for: refreshConfig) }
    }

    /// Discover the vendor's real models from the page after connect (Round 9 A).
    private func refreshModels(for cfg: WebProviderConfig) async -> String? {
        #if canImport(WebKit)
        let message = await appState.refreshWebModels(for: cfg)
        providers = WebProviderStore.load()
        return message
        #else
        return L.t(AppLocalizationKey.locWebRequiresWebKit)
        #endif
    }

    /// Refresh the complete per-model effort and parameter profile snapshot.
    private func refreshEffort(for cfg: WebProviderConfig) async -> String? {
        #if canImport(WebKit)
        let result = await appState.refreshWebModelsAndEffort(for: cfg)
        providers = WebProviderStore.load()
        return "\(result.modelsMsg) \(result.effortMsg)"
        #else
        return L.t(AppLocalizationKey.locWebRequiresWebKit)
        #endif
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

/// Embedded login: opens the vendor's chat URL; the user logs in once; on close
/// we capture cookies for session persistence (plan Раздел 12 Блок 3 п.35).
struct WebProviderLoginView: View {
    @State var config: WebProviderConfig
    let onSession: (WebSessionStore) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detectResult: DetectResult?
    @State private var capturedCookies: [BrowserCookie] = []

    /// Мост вкладки логина провайдера (единый для всех login-поверхностей).
    private var loginBridge: AntiBrowserAutomationBridge {
        let tabKey = AntiBrowserTabManager.makeKey(providerID: config.id,
                                                  projectID: "global",
                                                  chatID: "provider-login")
        return AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
    }

    // Capturing a valid logged-in session is independent from model discovery.
    // Раньше кнопка блокировалась без сохранённых cookie/найденных моделей —
    // и после ПЕРВОГО входа сессию нельзя было сохранить: на странице логина
    // моделей ещё нет. Проверку cookie делает сам capture(): при их отсутствии
    // он показывает «No authenticated cookies...».
    private var canCapture: Bool { true }

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

                // Live status: cookies + detected models count
                if !capturedCookies.isEmpty {
                    Label(L.t(AppLocalizationKey.locCookiesCount, capturedCookies.count), systemImage: "lock.fill")
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


                // Capture only enabled when we have models OR user explicitly wants session
                Button(action: capture) {
                    Text(L.t(AppLocalizationKey.locWebCaptureSession))
                        .interfaceFont(size: 11)
                        .foregroundColor(canCapture ? Color.mimo.success : Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled(!canCapture)
                .help(canCapture ? L.t(AppLocalizationKey.locSaveSessionModels) : L.t(AppLocalizationKey.locDetectModelsFirst))

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
        .task(id: "\(config.id)|\(config.activeSessionID ?? WebSessionManager.defaultSessionID)") {
            // Pre-load the active named session to show its real status.
            let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
            if let store = WebSessionManager.restore(providerId: config.id,
                                                      homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                                      sessionID: sessionID) {
                capturedCookies = store.cookies
            }
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
            // user captures any cookies. It never required a session, so it
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

    private func mergeDetectedModels(liveModels: [WebProviderModel],
                                     aiModels: [WebProviderModel]) -> [WebProviderModel] {
        var result: [WebProviderModel] = []
        var seen = Set<String>()
        for model in liveModels + aiModels {
            let key = model.name.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(model)
        }
        return result
    }

    private func parseAIDetectedModels(_ answer: String) -> [WebProviderModel] {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let names = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return uniqueModelNames(names)
        }

        // Be tolerant of a fenced JSON response from a provider-side wrapper.
        if let start = trimmed.firstIndex(of: "["),
           let end = trimmed.lastIndex(of: "]"), start <= end {
            let candidate = String(trimmed[start...end])
            if let data = candidate.data(using: .utf8),
               let names = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return uniqueModelNames(names)
            }
        }
        return uniqueModelNames(trimmed.components(separatedBy: .newlines))
    }

    private func uniqueModelNames(_ rawNames: [String]) -> [WebProviderModel] {
        var seen = Set<String>()
        return rawNames.compactMap { raw in
            var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            name = name.replacingOccurrences(of: "^[\\s`\\\"'•*-]+", with: "", options: .regularExpression)
            name = name.replacingOccurrences(of: "^[0-9]+[.)]\\s*", with: "", options: .regularExpression)
            name = name.replacingOccurrences(of: "[`\\\"']", with: "", options: .regularExpression)
            guard !name.isEmpty, name.count <= 100,
                  !name.contains(":"), !name.contains("\n"),
                  let normalized = WebModelListParser.normalize(name, vendor: config.vendor),
                  seen.insert(normalized.lowercased()).inserted else { return nil }
            return WebProviderModel(name: normalized,
                                    discoveryStatus: .notDetected,
                                    isLiveDiscovered: false,
                                    isSelectable: false,
                                    discoveryMessage: L.t(AppLocalizationKey.locAICandidateVerification))
        }
    }

    @MainActor
    private func saveDetectedModels(_ models: [WebProviderModel]) {
        guard !models.isEmpty else {
            detectResult = .failed(L.t(AppLocalizationKey.locNoModelNamesReturned))
            return
        }
        detectResult = .found(models)
        var updated = config
        var merged = updated.discoveredModels
        let existingNames = Set(merged.map { $0.name.lowercased() })
        merged.append(contentsOf: models.filter { !existingNames.contains($0.name.lowercased()) })
        updated.discoveredModels = merged
        WebProviderStore.save(WebProviderStore.upsert(updated, in: WebProviderStore.load()))
        config = updated
    }

    private func capture() {
        Task {
            let bridge = loginBridge
            do {
                let cookieList = try await bridge.cookies()
                guard WebLoginCaptureLogic.canPersist(cookieCount: cookieList.count) else {
                    detectResult = .failed(WebLoginCaptureLogic.captureMessage(cookieCount: cookieList.count))
                    return
                }
                let localStorageScript = """
                (function(){
                  const values = {};
                  try {
                    for (let i = 0; i < localStorage.length; i++) {
                      const key = localStorage.key(i);
                      if (key !== null) values[key] = localStorage.getItem(key) || "";
                    }
                  } catch (_) {}
                  return values;
                })();
                """
                let localStorageValues = (try? await bridge.evaluateJS(localStorageScript)) as? [String: String] ?? [:]
                let session = WebSessionStore(cookies: cookieList, localStorage: localStorageValues, savedAt: Date())
                await MainActor.run {
                    capturedCookies = cookieList
                    onSession(session)
                    dismiss()
                }
            } catch {
                detectResult = .failed(error.localizedDescription)
            }
        }
    }
}
