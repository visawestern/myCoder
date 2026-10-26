import SwiftUI

struct BottomPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            BottomTabBar(selectedTab: $selectedTab, onClose: { appState.showTerminal = false })
                .environmentObject(appState)
            
            if selectedTab == 0 {
                TerminalView()
                    .environmentObject(appState)
            } else {
                GitPanelView()
            }
        }
        .background(Color.mimo.surface)
    }
}

struct BottomTabBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            BottomTabButton(
                title: AppLocalization.string(.terminalTab, language: appState.appLanguage),
                icon: "terminal",
                tag: 0,
                selectedTag: $selectedTab
            )
            BottomTabButton(
                title: AppLocalization.string(.gitTab, language: appState.appLanguage),
                icon: "command",
                tag: 1,
                selectedTag: $selectedTab
            )
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.mimo.surface)
        .overlay(
            Rectangle()
                .fill(Color.mimo.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct BottomTabButton: View {
    let title: String
    let icon: String
    let tag: Int
    @Binding var selectedTag: Int
    
    var isActive: Bool {
        selectedTag == tag
    }
    
    var body: some View {
        Button(action: { selectedTag = tag }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .interfaceFont(size: 14)
                
                Text(title)
                    .interfaceFont(size: 12, weight: isActive ? .semibold : .regular)
            }
            .foregroundColor(isActive ? Color.mimo.brand : Color.mimo.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.mimo.brand.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.mimo.brand.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(HandCursorButtonStyle())
    }
}

struct TerminalView: View {
    @EnvironmentObject var appState: AppState
    @State private var command = ""
    @State private var output: [TerminalLine] = []
    @State private var isExecuting = false
    @State private var currentTask: Task<Void, Never>?
    @State private var executionStartTime: Date?

    private let timeoutSeconds: TimeInterval = 30
    private var language: AppLanguage { appState.appLanguage }

    private var terminalFont: Font {
        TerminalFontResolver.swiftUIFont(size: 12, settings: appState.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack(spacing: 6) {
                if isExecuting {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.5)
                    Text(executionTimeLabel)
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.cyan)
                        .monospacedDigit()
                }
                Spacer()
                if isExecuting {
                    Button(action: stopExecution) {
                        Image(systemName: "stop.fill")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.error)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help("Stop (⌃C)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.mimo.surface.opacity(0.8))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(output) { line in
                            Text(line.text)
                                .font(terminalFont)
                                .foregroundColor(line.color)
                                .textSelection(.enabled)
                        }
                        
                        if isExecuting {
                            HStack(spacing: 4) {
                                Text("⏳")
                                    .font(terminalFont)
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.5)
                            }
                            .id("cursor")
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(8)
                }
                .background(Color.mimo.codeBg)
                .onChange(of: output.count) { _ in
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo("cursor", anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 0) {
                Text(isExecuting ? "" : "$ ")
                    .font(terminalFont)
                    .foregroundColor(Color.mimo.cyan)

                TextField("", text: $command)
                    .textFieldStyle(.plain)
                    .font(terminalFont)
                    .onSubmit(handleCommandSubmit)
                    .disabled(isExecuting)
            }
            .padding(8)
            .background(Color.mimo.surface)
        }
        .onAppear(perform: seedWelcomeLinesIfNeeded)
        .onChange(of: appState.settings.language) { _ in
            reseedWelcomeLines()
        }
    }

    private var executionTimeLabel: String {
        guard let start = executionStartTime else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        let remain = max(0, timeoutSeconds - elapsed)
        // Show countdown in seconds
        return "\(Int(elapsed))s / \(Int(remain))s"
    }

    // MARK: - Welcome & Help

    private func seedWelcomeLinesIfNeeded() {
        guard output.isEmpty else { return }
        reseedWelcomeLines()
    }

    private func reseedWelcomeLines() {
        output = [
            TerminalLine(text: AppLocalization.string(.terminalWelcome, language: language), type: .system),
            TerminalLine(text: AppLocalization.string(.terminalHelpHint, language: language), type: .system),
            TerminalLine(text: "  sleep [seconds]  — Pause execution", type: .system),
            TerminalLine(text: "  clear — Clear screen", type: .system),
            TerminalLine(text: "", type: .system)
        ]
    }

    // MARK: - Command Handling

    private func handleCommandSubmit() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isExecuting else { return }

        output.append(TerminalLine(text: "$ \(trimmed)", type: .command))
        command = ""

        if trimmed == "clear" {
            output.removeAll()
            return
        } else if trimmed == "help" {
            output.append(TerminalLine(text: AppLocalization.string(.terminalHelpOutput, language: language), type: .output))
            return
        }

        // Built-in sleep command
        if trimmed == "sleep" || trimmed.hasPrefix("sleep ") {
            let secondsStr = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            let seconds = Double(secondsStr) ?? 1.0
            handleSleep(seconds: min(seconds, 30))
            return
        }

        // Async execution with timeout
        startAsyncExecution(command: trimmed)
    }

    // MARK: - Sleep (built-in, non-blocking)

    private func handleSleep(seconds: Double) {
        isExecuting = true
        executionStartTime = Date()

        currentTask = Task {
            let safeSeconds = min(max(seconds, 0.1), 30)
            let interval = 0.1
            var elapsed = 0.0

            while elapsed < safeSeconds, !Task.isCancelled {
                appendLine("⏳ Sleeping... \(String(format: "%.1f", safeSeconds - elapsed))s remaining", type: .system)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                elapsed += interval
            }

            if !Task.isCancelled {
                appendLine("✅ Resumed after \(String(format: "%.1f", safeSeconds))s", type: .system)
            }

            finishExecution()
        }
    }

    // MARK: - Async Shell Execution with Timeout and Streaming

    private func startAsyncExecution(command cmd: String) {
        isExecuting = true
        executionStartTime = Date()

        guard let workspacePath = appState.selectedWorkspace?.path else {
            appendLine("Error: no workspace selected", type: .error)
            finishExecution()
            return
        }

        currentTask = Task {
            let shellProcess = Process()
            shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            shellProcess.arguments = ["-c", cmd]
            shellProcess.currentDirectoryURL = URL(fileURLWithPath: workspacePath)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            shellProcess.standardOutput = outputPipe
            shellProcess.standardError = errorPipe

            // Make stdin available for interactive commands
            let stdinPipe = Pipe()
            shellProcess.standardInput = stdinPipe

            do {
                try shellProcess.run()

                // Stream stdout in real-time
                let outHandle = outputPipe.fileHandleForReading
                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { @MainActor in
                            self.appendLine(text, type: .output)
                        }
                    }
                }

                // Stream stderr in real-time
                let errHandle = errorPipe.fileHandleForReading
                errHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { @MainActor in
                            self.appendLine(text, type: .error)
                        }
                    }
                }

                // Wait with timeout
                let deadline = Date().addingTimeInterval(timeoutSeconds)

                while shellProcess.isRunning, Date() < deadline {
                    if Task.isCancelled {
                        shellProcess.terminate()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms poll
                }

                // Timeout check
                if shellProcess.isRunning {
                    shellProcess.terminate()
                    shellProcess.waitUntilExit()  // Ensure process fully exits before reading status
                    appendLine("⚠️ Command timed out after \(Int(timeoutSeconds))s and was killed", type: .error)
                }

                // Clean up handlers
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil

                let exitCode = shellProcess.terminationStatus
                if exitCode != 0, exitCode != 15 /* SIGTERM */ {
                    appendLine("exit code: \(exitCode)", type: .error)
                }

            } catch {
                appendLine("Error: \(error.localizedDescription)", type: .error)
            }

            finishExecution()
        }
    }

    // MARK: - Execution Control

    private func stopExecution() {
        currentTask?.cancel()
        currentTask = nil
        appendLine("⛔ Stopped", type: .system)
        finishExecution()
    }

    @MainActor
    private func finishExecution() {
        isExecuting = false
        executionStartTime = nil
        currentTask = nil
    }

    private let maxTerminalLines = 500

    @MainActor
    private func appendLine(_ text: String, type: LineType) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            output.append(TerminalLine(text: trimmed, type: type))
        }
        // Prune oldest lines when exceeding max to prevent unbounded memory growth
        if output.count > maxTerminalLines {
            output.removeFirst(output.count - maxTerminalLines)
        }
    }
}

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let type: LineType
    
    var color: Color {
        switch type {
        case .command: return Color.mimo.cyan
        case .output: return Color.mimo.textPrimary
        case .error: return Color.mimo.error
        case .system: return Color.mimo.textMuted
        }
    }
}

enum LineType {
    case command, output, error, system
}

struct GitPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var showBranchCreation = false
    @State private var newBranchName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Branch info with dropdown
            BranchHeader(
                currentBranch: appState.gitBranch,
                branches: appState.gitBranches,
                isBusy: appState.isGitBusy,
                statusMessage: appState.gitStatusMessage
            ) { branch in
                checkoutBranch(branch)
            }
            .padding(.horizontal, 16)

            Divider()

            // Git action buttons
            GitActionBar(
                onCommit: commitChanges,
                onPush: pushChanges,
                onPull: pullChanges,
                onBranch: { showBranchCreation = true },
                isBusy: appState.isGitBusy,
                hasChanges: !appState.vcsChanges.isEmpty,
                statusMessage: appState.gitStatusMessage
            )
            .padding(.horizontal, 16)
            .alert("Create New Branch", isPresented: $showBranchCreation) {
                TextField(L.t(AppLocalizationKey.locBranchName), text: $newBranchName)
                Button(L.t(AppLocalizationKey.locCreate)) { createBranch() }
                Button(L.t(AppLocalizationKey.locCancel), role: .cancel) { newBranchName = "" }
            } message: {
                Text(L.t(AppLocalizationKey.locNewBranchName, appState.gitBranch))
            }

            // File changes
            ChangesList(
                changes: appState.vcsChanges,
                totals: appState.sessionGitTotals
            )
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Git Operations

    private func checkoutBranch(_ branch: String) {
        guard let repoPath = appState.gitRepositoryPath else { return }
        appState.isGitBusy = true
        Task {
            do {
                let result = try GitRepository.checkout(branch: branch, in: repoPath)
                await MainActor.run {
                    appState.gitBranch = branch
                    appState.isGitBusy = false
                    appState.gitStatusMessage = result.success ? "Switched to \(branch)" : nil
                }
            } catch {
                await MainActor.run {
                    appState.isGitBusy = false
                    appState.gitStatusMessage = "Checkout failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func commitChanges() {
        appState.pendingGitAction = .openCommitComposer
    }

    private func pushChanges() {
        guard let repoPath = appState.gitRepositoryPath else { return }
        appState.isGitBusy = true
        Task {
            do {
                let result = try GitRepository.push(in: repoPath)
                await MainActor.run {
                    appState.isGitBusy = false
                    appState.gitStatusMessage = result.success ? "Pushed successfully" : nil
                }
            } catch {
                await MainActor.run {
                    appState.isGitBusy = false
                    appState.gitStatusMessage = "Push failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func pullChanges() {
        guard let repoPath = appState.gitRepositoryPath else { return }
        appState.isGitBusy = true
        Task {
            do {
                let output = try GitRepository.run(["pull"], in: repoPath)
                await MainActor.run {
                    appState.isGitBusy = false
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.gitStatusMessage = trimmed.isEmpty ? "Pull complete" : trimmed
                }
                refreshGitChanges()
            } catch {
                await MainActor.run {
                    appState.isGitBusy = false
                    appState.gitStatusMessage = "Pull failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func createBranch() {
        let branchName = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty, let repoPath = appState.gitRepositoryPath else {
            newBranchName = ""
            return
        }
        appState.isGitBusy = true
        Task {
            do {
                _ = try GitRepository.run(["checkout", "-b", branchName], in: repoPath)
                await MainActor.run {
                    appState.isGitBusy = false
                    appState.gitBranch = branchName
                    appState.gitStatusMessage = "Created and switched to \(branchName)"
                    // Refresh branch list
                    if let branches = try? GitRepository.branches(in: repoPath) {
                        appState.gitBranches = branches
                    }
                }
            } catch {
                await MainActor.run {
                    appState.isGitBusy = false
                    appState.gitStatusMessage = "Branch creation failed: \(error.localizedDescription)"
                }
            }
        }
        newBranchName = ""
    }

    private func refreshGitChanges() {
        guard let repoPath = appState.gitRepositoryPath else { return }
        Task {
            do {
                let changes = try GitRepository.workingTreeChanges(in: repoPath)
                let branch = GitRepository.currentBranch(in: repoPath)
                let branches = try? GitRepository.branches(in: repoPath)
                let additions = changes.reduce(0) { $0 + $1.additions }
                let deletions = changes.reduce(0) { $0 + $1.deletions }

                await MainActor.run {
                    appState.vcsChanges = GitRepository.toVcsFileDiffs(changes)
                    appState.sessionGitTotals = SessionGitTotals(additions: additions, deletions: deletions)
                    appState.gitBranch = branch
                    if let branches { appState.gitBranches = branches }
                }
            } catch {
                print("Failed to refresh git: \(error)")
            }
        }
    }
}

// MARK: - Branch Header with Dropdown

struct BranchHeader: View {
    let currentBranch: String
    let branches: [String]
    let isBusy: Bool
    let statusMessage: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .interfaceFont(size: 13)
                .foregroundColor(Color.mimo.cyan)

            Menu {
                ForEach(branches, id: \.self) { branch in
                    Button(action: { onSelect(branch) }) {
                        HStack {
                            Text(branch)
                            if branch == currentBranch {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentBranch.isEmpty ? "main" : currentBranch)
                        .interfaceFont(size: 13, design: .monospaced)
                        .foregroundColor(Color.mimo.textPrimary)
                    Image(systemName: "chevron.down")
                        .interfaceFont(size: 9)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isBusy || branches.isEmpty)

            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.5)
            }

            Spacer()

            if let status = statusMessage {
                Text(status)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
    }
}

// MARK: - Git Action Bar

struct GitActionBar: View {
    let onCommit: () -> Void
    let onPush: () -> Void
    let onPull: () -> Void
    let onBranch: () -> Void
    let isBusy: Bool
    let hasChanges: Bool
    let statusMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            GitActionButton(label: "Commit", icon: "checkmark.circle", color: .green, action: onCommit, disabled: isBusy || !hasChanges)
            GitActionButton(label: "Push", icon: "arrow.up.circle", color: .cyan, action: onPush, disabled: isBusy)
            GitActionButton(label: "Pull", icon: "arrow.down.circle", color: .purple, action: onPull, disabled: isBusy)
            GitActionButton(label: "Branch", icon: "arrow.triangle.branch", color: .orange, action: onBranch, disabled: isBusy)
        }
    }
}

// MARK: - Changes List

struct ChangesList: View {
    let changes: [MimoVcsFileDiff]
    let totals: SessionGitTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t(AppLocalizationKey.locChanges))
                    .interfaceFont(size: 11, weight: .bold)
                    .foregroundColor(Color.mimo.textMuted)
                    .tracking(1)

                Spacer()

                if totals.additions > 0 || totals.deletions > 0 {
                    HStack(spacing: 6) {
                        Text("+\(totals.additions)")
                            .interfaceFont(size: 11, weight: .medium)
                            .foregroundColor(Color.mimo.success)
                        Text("-\(totals.deletions)")
                            .interfaceFont(size: 11, weight: .medium)
                            .foregroundColor(Color.mimo.error)
                    }
                }
            }

            if changes.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.mimo.codeBg)
                    .frame(height: 48)
                    .overlay(
                        Text(L.t(AppLocalizationKey.locChanges1))
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textMuted)
                    )
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 1) {
                        ForEach(changes, id: \.path) { change in
                            ChangeRow(change: change)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }
}

struct ChangeRow: View {
    let change: MimoVcsFileDiff

    var statusColor: Color {
        switch change.status {
        case "added", "new": return Color.mimo.success
        case "deleted", "removed": return Color.mimo.error
        case "renamed", "moved": return Color.mimo.brand
        case "modified", "changed": return Color.mimo.textSecondary
        default: return Color.mimo.textMuted
        }
    }

    var statusBadge: String {
        switch change.status {
        case "added", "new": return "A"
        case "deleted", "removed": return "D"
        case "renamed", "moved": return "R"
        case "modified", "changed": return "M"
        default: return "?"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(statusBadge)
                .interfaceFont(size: 9, weight: .bold, design: .monospaced)
                .foregroundColor(statusColor)
                .frame(width: 16)

            Text((change.path as NSString).lastPathComponent)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .lineLimit(1)

            Spacer()

            if change.additions > 0 {
                Text("+\(change.additions)")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.success)
            }
            if change.deletions > 0 {
                Text("-\(change.deletions)")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.error)
            }
        }
        .padding(.vertical, 3)
    }
}

struct GitActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .interfaceFont(size: 12)
                Text(label)
                    .interfaceFont(size: 11, weight: .medium)
            }
            .foregroundColor(disabled ? color.opacity(0.3) : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(disabled ? color.opacity(0.05) : color.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(disabled ? color.opacity(0.1) : color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(HandCursorButtonStyle())
        .disabled(disabled)
    }
}
