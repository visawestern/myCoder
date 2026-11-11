import SwiftUI
import AppKit

/// Editable card for one web provider (plan Раздел 12 Блок 4 п.43-47).
struct WebProviderCard: View {
    @EnvironmentObject private var appState: AppState
    @Binding var config: WebProviderConfig
    let onSave: () -> Void
    let onLogin: () -> Void
    let onChangeLogin: () -> Void
    let onRemove: () -> Void
    let onRefreshModels: () async -> String?
    let onRefreshEffort: () async -> String?

    @State private var isRefreshing = false
    @State private var lastRefreshError: String?
    @State private var lastRefreshCount: Int = 0
    @State private var showDiscoveredModels = false
    @State private var systemPromptHeight: CGFloat = 24
    @State private var showRemoveConfirmation = false

    private var isConnected: Bool {
        WebProviderConnectivity.isConnected(config)
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
                        .help(L.t(AppLocalizationKey.locLogin))
                } else {
                    HStack(spacing: 8) {
                        Button(action: onChangeLogin) {
                            Image(systemName: "person.crop.circle.badge.arrow.forward")
                                .interfaceFont(size: 12)
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .foregroundColor(Color.mimo.brand)
                        .help(L.t(AppLocalizationKey.locChangeLoginSession))

                        // The complete catalog is rendered below as a full-width
                        // accordion; the header only reports refresh errors.
                        if !isRefreshing && lastRefreshError != nil {
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
                        Text(L.t(AppLocalizationKey.locDetectedModels))
                            .interfaceFont(size: 11, weight: .semibold)
                            .foregroundColor(Color.mimo.textSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        Text("\(config.discoveredModels.count)")
                            .interfaceFont(size: 10, weight: .semibold, design: .monospaced)
                            .foregroundColor(Color.mimo.brand)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.mimo.brand.opacity(0.10))
                            .clipShape(Capsule())
                        Image(systemName: showDiscoveredModels ? "chevron.up" : "chevron.down")
                            .interfaceFont(size: 10, weight: .semibold)
                            .foregroundColor(Color.mimo.textSecondary)
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
                            .help(L.t(AppLocalizationKey.locClear))
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

            // Единственный производственный транспорт — AntiBrowser (CDP+REST).
            // Показываем статус движка прямо в карточке провайдера.
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundColor(Color.mimo.brand)
                Text(L.t(AppLocalizationKey.locInAppBrowser))
                    .interfaceFont(size: 11, weight: .medium)
                Text(WebTransportRuntimeLogic.label(for: config.transport))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer()
                switch EngineStatusCenter.shared.phase {
                case .ready(let info):
                    Label("AntiBrowser · \(info.version)", systemImage: "checkmark.circle.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.success)
                case .launching, .locating:
                    ProgressView().controlSize(.mini)
                case .error(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.warning)
                case .idle:
                    Button(L.t("Start AntiBrowser")) {
                        Task { await EngineStatusCenter.shared.start() }
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
            }

        }
        .padding(12)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: config) { _ in
            onSave()
        }
    }
}
