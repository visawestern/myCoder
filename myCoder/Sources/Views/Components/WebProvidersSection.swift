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

/// Editable card for one web provider (plan Раздел 12 Блок 4 п.43-47).
struct WebProviderCard: View {
    @EnvironmentObject private var appState: AppState
    @Binding var config: WebProviderConfig
    let onSave: () -> Void
    let onLogin: () -> Void
    let onChangeLogin: () -> Void
    let onSelectSession: (String) -> Void
    let onRemove: () -> Void
    let onRefreshModels: () async -> String?
    let onRefreshEffort: () async -> String?
    let homeDirectory: URL

    @State private var isRefreshing = false
    @State private var lastRefreshError: String?
    @State private var lastRefreshCount: Int = 0
    @State private var showDiscoveredModels = false
    @State private var systemPromptHeight: CGFloat = 24
    @State private var showRemoveConfirmation = false
    @State private var storedSessions: [WebStoredLoginSession] = []

    private var isConnected: Bool {
        WebProviderConnectivity.isConnected(config, homeDirectory: homeDirectory)
    }

    // System prompt templates with tool-specific instructions
    private static let systemPromptTemplates: [(name: String, prompt: String)] = [
        ("Default", ""),
        ("Code Agent", """
You are a code-focused AI agent. You can:
- Read/write files in the project directory
- Run shell commands (bash)
- Search/replace in files
- List directories

Always prefer using tools over explaining. When asked to modify code, make the minimal necessary changes. Run tests after changes.
"""),
        ("Code Reviewer", """
You are a senior code reviewer. Focus on:
- Correctness and edge cases
- Security vulnerabilities
- Performance implications
- Code style and maintainability
- Test coverage

Be specific about issues and suggest concrete improvements.
"""),
        ("Debugging Assistant", """
You are a debugging expert. Help the user by:
- Analyzing error messages and stack traces
- Suggesting hypotheses for root causes
- Proposing minimal reproduction steps
- Recommending debugging strategies (logging, breakpoints, etc.)
- Verifying fixes with tests
"""),
        ("Documentation Writer", """
You are a technical writer. Create clear, concise documentation:
- API references with examples
- Architecture overviews
- Setup/installation guides
- Changelog entries

Use clear headings, code examples, and cross-references.
"""),
        ("Codex-style Agent", """
## Context
You are myCoder, an autonomous coding agent operating locally via a shell and filesystem. You run in the user's project directory. Their machine may or may not be connected to the internet. The user is in control.

## Rules
- Verify code rather than assuming correctness. Run targeted tests, type checks, or minimal build steps when feasible.
- Apply surgical patches; never touch unrelated files.
- Avoid unnecessary mass rewrites. Automate repetitive tasks with scripts.
- Keep secrets and API keys out of code and outputs.

## AGENTS.md / miagents.md
Follow any repository instructions in AGENTS.md or miagents.md. If it instructs linting, formatting, testing, or commit conventions, follow those. If no such file exists, skip rather than create one unless the user requests it.

## Writing style
- Write tiny diffs. One logical change per edit.
- Prefer targeted grep/ripgrep edits over rewriting entire files.
- Be concrete: file paths, line ranges, exact identifiers.
- Explain only when you deviate from direct action.

## Technical style
- For large libraries, think through the minimal reproduction first.
- Check git history when investigating regressions or behavior.
- Run relevant unit tests when available.
- Respect existing code conventions in the repo.

## Permissions
- Default to high autonomy: choose files, run commands, and apply fixes unless the user has restricted specific paths.
- When the user says "full-auto", run without asking.
- When the user is present, act quickly but confirm before large refactors.

## Communicating with users
- Be direct and technical. Explain your reasoning when a decision is non-trivial.
- If unsure, ask one concise clarifying question.
- Present options when trade-offs exist.

## External references
- Use context7 or web search when you need accurate, current library docs.
- Do not fabricate APIs or function signatures.

## Code review and verification
- Prefer targeted tests over manual inspection.
- Prefer type check and build verification over guesswork.
- When modifying public APIs, check downstream callers.

## Test writing
- Use the project's existing test framework. Prefer unit tests for logic, integration tests for I/O.
- Place tests near the code they exercise. Mirror the source tree.

## Logging
- Respect existing logging conventions. Do not add logging unless relevant to the change.
- Prefer structured logs when the codebase uses them.

## Escalation
- If a user request is ambiguous or likely destructive, ask one clarifying question.
- If a request requires credentials you don't have, say so.

## Task completion
- Do the work. Verify it builds or passes tests when possible.
- Summarize what you did and list any files changed.
- If something remains blocked, say so clearly.

## Web integration
- You have access to file tools: list_dir, read_file, write_file, search_replace, shell_command.
- Use them autonomously. Do not just explain what to do — actually do it.
- When the user asks for code changes, apply them directly using write_file or search_replace.
- When investigating issues, use shell_command to run tests and diagnostic commands.
"""),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.mimo.success : Color.mimo.error)
                        .frame(width: 8, height: 8)
                    Text(config.displayName)
                        .interfaceFont(size: 14, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                }
                Spacer()
                if !isConnected {
                    Button(L.t(AppLocalizationKey.locLogin)) { onLogin() }
                        .interfaceFont(size: 12).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand)
                } else {
                    HStack(spacing: 8) {
                        if !storedSessions.isEmpty {
                            Menu {
                                ForEach(storedSessions) { session in
                                    Button {
                                        onSelectSession(session.id)
                                    } label: {
                                        HStack {
                                            Text(session.name)
                                            if session.id == config.activeSessionID { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            } label: {
                                Label(config.activeSessionName ?? L.t(AppLocalizationKey.locLogin), systemImage: "person.crop.circle")
                                    .interfaceFont(size: 10)
                                    .foregroundColor(Color.mimo.textSecondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help(L.t(AppLocalizationKey.locChooseSavedWebLogin))
                        }

                        Button(action: onChangeLogin) {
                            Image(systemName: "person.crop.circle.badge.arrow.forward")
                                .interfaceFont(size: 12)
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .foregroundColor(Color.mimo.brand)
                        .help(L.t(AppLocalizationKey.locChangeLoginSession))

                        // The complete catalog is rendered below as a full-width
                        // accordion; the header only reports the current count.
                        if !isRefreshing && !config.discoveredModels.isEmpty {
                            Text(L.t(AppLocalizationKey.locDetectedCount, config.discoveredModels.count))
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.success)
                        } else if !isRefreshing && lastRefreshError != nil {
                            Label(L.t(AppLocalizationKey.locDetectionFailed), systemImage: "exclamationmark.triangle")
                                .interfaceFont(size: 10).foregroundColor(Color.mimo.warning)
                        }

                        Button(action: {
                            isRefreshing = true
                            lastRefreshError = nil
                            Task {
                                let result = await onRefreshModels()
                                await MainActor.run {
                                    isRefreshing = false
                                    if let updated = WebProviderStore.load().first(where: { $0.id == config.id }) {
                                        lastRefreshCount = updated.discoveredModels.count
                                    }
                                    if let result {
                                        let lower = result.lowercased()
                                        if lower.contains("failed") || lower.contains("could not") || lower.contains("not found") || lower.contains("login") {
                                            lastRefreshError = result
                                        }
                                    }
                                }
                            }
                        }) {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .interfaceFont(size: 12)
                            }
                        }
                        .interfaceFont(size: 12).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand)
                        .disabled(isRefreshing)
                        .help(isRefreshing ? L.t(AppLocalizationKey.locDetecting) : L.t(AppLocalizationKey.locDetectModelsHelp))

                        // Audit 2026-09-06 (user directive): the separate
                        // effort/brain refresh button is GONE. Effort levels
                        // are discovered together with each model during the
                        // same probe cycle (discoverModelCapabilities clicks
                        // every model and its effort control); a standalone
                        // control implied effort was picked independently.

                        if let err = lastRefreshError {
                            Text(err).interfaceFont(size: 10).foregroundColor(Color.mimo.error)
                        }
                    }
                }

                Button(action: { showRemoveConfirmation = true }) {
                    Image(systemName: "trash").interfaceFont(size: 12).foregroundColor(Color.mimo.error)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locRemoveWebProvider))
                .alert(L.t(AppLocalizationKey.locRemoveWebProviderConfirm, config.displayName), isPresented: $showRemoveConfirmation) {
                    Button(L.t(AppLocalizationKey.locRemove), role: .destructive, action: onRemove)
                    Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
                } message: {
                    Text(L.t(AppLocalizationKey.locSavedSessionDeleted))
                }
            }

            if !config.discoveredModels.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showDiscoveredModels.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showDiscoveredModels ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            .interfaceFont(size: 12, weight: .semibold)
                            .foregroundColor(Color.mimo.brand)
                        Image(systemName: "cube.fill")
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                        Text(L.t(AppLocalizationKey.locDetectedModelsCount, config.discoveredModels.count))
                            .interfaceFont(size: 11, weight: .semibold)
                            .foregroundColor(Color.mimo.textSecondary)
                        Spacer()
                        Text(showDiscoveredModels ? L.t(AppLocalizationKey.locHide) : L.t(AppLocalizationKey.locShow))
                            .interfaceFont(size: 10, weight: .medium)
                            .foregroundColor(Color.mimo.brand)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mimo.backgroundAlt)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.mimo.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(showDiscoveredModels ? L.t(AppLocalizationKey.locHideDetectedModels) : L.t(AppLocalizationKey.locShowDetectedModels))

                if showDiscoveredModels {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(config.discoveredModels) { model in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(model.discoveryStatus == .active ? Color.mimo.success : Color.mimo.warning)
                                    .frame(width: 6, height: 6)
                                Text(model.name)
                                    .interfaceFont(size: 11, weight: .medium, design: .monospaced)
                                    .foregroundColor(Color.mimo.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(model.discoveryStatus == .active ? L.t(AppLocalizationKey.locActive) : L.t(model.discoveryStatus.rawValue))
                                    .interfaceFont(size: 9, weight: .medium)
                                    .foregroundColor(model.discoveryStatus == .active ? Color.mimo.success : Color.mimo.warning)
                                if !model.availableEfforts.isEmpty {
                                    Text(L.t(AppLocalizationKey.locEffort))
                                        .interfaceFont(size: 9)
                                        .foregroundColor(Color.mimo.violet)
                                } else {
                                    Text(L.t(AppLocalizationKey.locNoEffort))
                                        .interfaceFont(size: 9)
                                        .foregroundColor(Color.mimo.textMuted)
                                }
                                if !model.parameterProfile.isEmpty {
                                    Text(L.t(AppLocalizationKey.locParams))
                                        .interfaceFont(size: 9)
                                        .foregroundColor(Color.mimo.cyan)
                                }
                                if model.discoveryStatus != .active {
                                    Button {
                                        config.discoveredModels.removeAll { $0.id == model.id }
                                        onSave()
                                    } label: {
                                        Image(systemName: "trash")
                                            .interfaceFont(size: 10, weight: .semibold)
                                            .foregroundColor(Color.mimo.error)
                                    }
                                    .buttonStyle(HandCursorButtonStyle())
                                    .help(L.t(AppLocalizationKey.locRemoveUnavailableDetection))
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(appState.selectedProviderID == "web:\(config.id)" && appState.selectedModel == model.name ? Color.mimo.subtleFill : Color.mimo.surface)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(appState.selectedProviderID == "web:\(config.id)" && appState.selectedModel == model.name ? Color.mimo.brand.opacity(0.35) : Color.clear, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard model.isSelectable, model.discoveryStatus == .active else { return }
                                appState.selectProvider("web:\(config.id)")
                                appState.selectModel(model.name)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.mimo.surface)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.mimo.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            // System prompt — compact when empty, grows with content
            if config.systemPrompt.isEmpty {
                HStack {
                    Text(L.t(AppLocalizationKey.locSystemPrompt)).interfaceFont(size: 11, weight: .medium).foregroundColor(Color.mimo.textMuted)
                    Spacer()
                    Menu {
                        ForEach(Self.systemPromptTemplates, id: \.name) { template in
                            Button(template.name) {
                                config.systemPrompt = template.prompt
                            }
                        }
                        Divider()
                        Button(L.t(AppLocalizationKey.locClear)) { config.systemPrompt = "" }
                    } label: {
                        Label(L.t(AppLocalizationKey.locTemplates), systemImage: "doc.on.doc")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.brand)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L.t(AppLocalizationKey.locSystemPrompt)).interfaceFont(size: 11, weight: .medium).foregroundColor(Color.mimo.textMuted)
                        Spacer()
                        Button(L.t(AppLocalizationKey.locClear)) { config.systemPrompt = "" }
                            .interfaceFont(size: 10).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.error)
                    }
                    TextEditor(text: $config.systemPrompt)
                        .font(.system(size: 12))
                        .frame(minHeight: 24, maxHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
                }
            }

            // Models are discovered from the authenticated page and selected
            // from the shared chat composer. Do not expose a second manual
            // browser model picker that can drift from the real web UI.
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(AppLocalizationKey.locModelEffortAreChosenTheChatInputAfterConnecting))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                HStack(spacing: 6) {
                    MiMoLogoMark(size: 16)
                    Text(WebDetectionStatusLogic.statusText(modelCount: config.allModels.count))
                        .interfaceFont(size: 10)
                        .foregroundColor(config.allModels.isEmpty ? Color.mimo.textMuted : Color.mimo.success)
                }
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .interfaceFont(size: 11)
                    Text(config.discoveredEffortLevels.isEmpty
                         ? L.t(AppLocalizationKey.locEffortNotDetected)
                         : L.t(AppLocalizationKey.locEffortValue, config.discoveredEffortLevels.map(\.displayName).joined(separator: ", ")))
                        .interfaceFont(size: 10)
                    if config.effortDropdown != nil {
                        Text(L.t(AppLocalizationKey.locSelectorAvailable))
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.success)
                    }
                }
                .foregroundColor(Color.mimo.textMuted)
            }

            // Delay + keep-alive
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("\(L.t(AppLocalizationKey.locToolCallDelay)): \(config.toolCallDelayMs) ms")
                        .interfaceFont(size: 11).foregroundColor(Color.mimo.textMuted)
                    Slider(value: Binding(get: { Double(config.toolCallDelayMs) },
                                          set: { config.toolCallDelayMs = Int($0) }),
                           in: 0...3000, step: 100)
                }
                VStack(alignment: .leading) {
                    Text("\(L.t(AppLocalizationKey.locKeepalive)): \(config.sessionKeepAliveSec)s")
                        .interfaceFont(size: 11).foregroundColor(Color.mimo.textMuted)
                    Slider(value: Binding(get: { Double(config.sessionKeepAliveSec) },
                                          set: { config.sessionKeepAliveSec = Int($0) }),
                           in: 30...600, step: 30)
                }
            }

            // The current production transport is the embedded WKWebView. Do
            // not expose a Chrome/CDP option that the send path cannot honor.
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundColor(Color.mimo.brand)
                Text(L.t(AppLocalizationKey.locInAppBrowser))
                    .interfaceFont(size: 11, weight: .medium)
                Text(WebTransportRuntimeLogic.label(for: config.transport))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
            }
            .onAppear {
                if config.transport != .playwrightMCP {
                    config.transport = .playwrightMCP
                }
            }

        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            storedSessions = WebSessionManager.list(providerId: config.id, homeDirectory: homeDirectory)
        }
        .onChange(of: config) { _ in
            storedSessions = WebSessionManager.list(providerId: config.id, homeDirectory: homeDirectory)
            onSave()
        }
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
    @State private var webView = WKWebView()

    @State private var detectResult: DetectResult?
    @State private var capturedCookies: [BrowserCookie] = []

    // Capturing a valid logged-in session is independent from model discovery.
    // DOM discovery and AI-assisted discovery are optional helpers, not a gate.
    private var canCapture: Bool {
        // Capturing a valid logged-in session must not depend on model discovery.
        // Discovery can fail because a vendor changed its DOM while cookies are
        // still perfectly usable for chat.
        !capturedCookies.isEmpty || webView.url != nil ||
            !config.discoveredModels.isEmpty || config.customModelSelector != nil
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

                Button(action: findModelsWithAI) {
                    HStack(spacing: 4) {
                        MiMoLogoMark(size: 14)
                        Text(L.t(AppLocalizationKey.locAskMyCoderAutoFree))
                            .interfaceFont(size: 11)
                    }
                    .foregroundColor(Color.mimo.brand)
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled({
                    if case .detecting = detectResult { return true }
                    return !MyCoderAutoFreeStore.shared.provider.isReady
                }())
                .help(L.t(AppLocalizationKey.locAskMyCoderAutoFreeHelp))

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
                WebViewRepresentable(webView: webView, url: config.chatURL)
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
            let bridge = WKWebViewBrowserBridge(webView: webView, selectors: WebVendorSelectors(input: "", sendButton: "", responseContainer: "", stopButton: ""))
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

    private func findModelsWithAI() {
        Task {
            await MainActor.run { detectResult = .detecting }
            let bridge = WKWebViewBrowserBridge(webView: webView, selectors: WebVendorSelectors(input: "", sendButton: "", responseContainer: "", stopButton: ""))
            do {
                let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
                let dropdownSelector = [
                    config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    catalogEntry?.modelDropdown ?? ""
                ].filter { !$0.isEmpty }.joined(separator: ", ")
                guard !dropdownSelector.isEmpty else {
                    await MainActor.run { detectResult = .failed(L.t(AppLocalizationKey.locNoSelectorFound)) }
                    return
                }

                // AI detection must inspect the same expanded live menu as DOM
                // detection. Reading body text first exposes only the currently
                // selected model, which caused the screenshot's one-of-ten result.
                let liveModels = await WebModelDiscovery.discoverAllModels(
                    using: bridge,
                    dropdownSelector: dropdownSelector,
                    vendor: config.vendor
                ) ?? []
                let structuredCandidates = (try? await bridge.readVisibleModelCandidates()) ?? []
                let candidateLabels = structuredCandidates.compactMap {
                    WebModelListParser.normalize($0.label, vendor: config.vendor)
                }
                let pageText = (try await bridge.pageText())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pageText.isEmpty || !candidateLabels.isEmpty || !liveModels.isEmpty else {
                    await MainActor.run { detectResult = .failed(L.t(AppLocalizationKey.locNoReadablePageText)) }
                    return
                }

                let liveNames = liveModels.map(\.name)
                let prompt = """
                Read the visible text from a \(config.displayName) web chat page below. Extract only selectable model names currently visible in its model menu. Return a JSON array of strings, with one exact model label per item and no explanations. Never return headings, effort labels, descriptions, or feature actions. If no model names are visible, return [].

                STRUCTURED LIVE CANDIDATES:
                \(liveNames.joined(separator: "\\n"))

                PAGE TEXT AFTER MENU EXPANSION:
                \(String(pageText.prefix(60_000)))
                """
                var answer = ""
                let messages = [
                    MyCoderAutoFreeClient.Message(
                        role: "system",
                        content: "You extract UI model labels exactly. Never invent a model name. Return only valid JSON."
                    ),
                    MyCoderAutoFreeClient.Message(role: "user", content: prompt)
                ]
                for try await event in MyCoderAutoFreeStore.shared.streamChat(
                    messages: messages,
                    tools: MyCoderAutoFreeClient.gateToolDefinitions(),
                    toolChoice: "none"
                ) {
                    if case .content(let text) = event {
                        answer += text
                    }
                }
                let aiModels = parseAIDetectedModels(answer)
                let merged = mergeDetectedModels(liveModels: liveModels, aiModels: aiModels)
                saveDetectedModels(merged)
            } catch {
                await MainActor.run { detectResult = .failed(L.t(AppLocalizationKey.locAIDetectionFailed, error.localizedDescription)) }
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
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let mapped = cookies.map {
                BrowserCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path,
                              expiresEpoch: $0.expiresDate?.timeIntervalSince1970,
                              httpOnly: $0.isHTTPOnly, secure: $0.isSecure)
            }
            guard WebLoginCaptureLogic.canPersist(cookieCount: mapped.count) else {
                detectResult = .failed(WebLoginCaptureLogic.captureMessage(cookieCount: mapped.count))
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
              return JSON.stringify(values);
            })();
            """
            webView.evaluateJavaScript(localStorageScript) { result, _ in
                let localStorage: [String: String]
                if let json = result as? String,
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                    localStorage = decoded
                } else {
                    localStorage = [:]
                }
                let session = WebSessionStore(cookies: mapped, localStorage: localStorage, savedAt: Date())
                capturedCookies = mapped  // Update UI immediately
                onSession(session)
                dismiss()
            }
        }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    let url: String

    func makeNSView(context: Context) -> WKWebView {
        // Round 30: maximally permissive navigation for the login surface too —
        // region redirects (kimi.com → kimi.ai), window.open hops and JS
        // dialogs must all work while the user logs in.
        let policy = PermissiveWebNavigationPolicy(ownerWebView: webView)
        webView.navigationDelegate = policy
        webView.uiDelegate = policy
        context.coordinator.retainedPolicy = policy
        if let u = URL(string: url) { webView.load(URLRequest(url: u)) }
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var retainedPolicy: PermissiveWebNavigationPolicy?
    }
}

/// Keeps the persistent chat WebView attached to the AppKit hierarchy so
/// WebKit loads pages and executes JavaScript. A cached but unattached WKWebView
/// can be created successfully while never becoming a usable browser surface.
struct WebChatWebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
