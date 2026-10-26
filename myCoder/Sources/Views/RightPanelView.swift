import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            GitToolsSection()
            
            Divider()
            
            SubagentsSection()
            
            Divider()
            
            ProgressSection()
            
            Spacer()
        }
        .background(Color.mimo.surface)
    }
}

struct GitToolsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var showCommitDialog = false
    @State private var showInitDialog = false
    @State private var showPublishDialog = false
    @State private var showAutoReviewDialog = false
    @State private var isGitInitialized = false
    @State private var hasRemote = false
    
    private var language: AppLanguage { appState.appLanguage }
    
    private var hasChanges: Bool {
        appState.sessionGitTotals.additions > 0
            || appState.sessionGitTotals.deletions > 0
            || !appState.vcsChanges.isEmpty
    }

    private var autoSummary: String {
        CommitMessageComposer.summary(
            fileNames: appState.vcsChanges.map { ($0.path as NSString).lastPathComponent },
            insertions: appState.sessionGitTotals.additions,
            deletions: appState.sessionGitTotals.deletions
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.string(.gitToolsTitle, language: language))
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                
                Spacer()
                
                Button(action: refreshGit) {
                    Image(systemName: appState.isGitBusy ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .interfaceFont(size: 13)
                        .foregroundColor(Color.mimo.textMuted)
                        .rotationEffect(appState.isGitBusy ? .degrees(360) : .degrees(0))
                        .animation(appState.isGitBusy ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.isGitBusy)
                }
                .buttonStyle(HandCursorButtonStyle())
                .disabled(appState.isGitBusy)
            }
            
            if let status = appState.gitStatusMessage, !status.isEmpty {
                Text(status)
                    .interfaceFont(size: 11)
                    .foregroundColor(status.lowercased().contains("error") || status.contains("fatal") ? Color.mimo.error : Color.mimo.textSecondary)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mimo.backgroundAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            HStack(spacing: 8) {
                Image(systemName: RightPanelLayout.changesIcon)
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textMuted)
                
                Text(AppLocalization.string(.gitChanges, language: language))
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textPrimary)
                
                Spacer()
                
                if hasChanges {
                    HStack(spacing: 8) {
                        Text("+\(appState.sessionGitTotals.additions)")
                            .interfaceFont(size: 12, weight: .medium)
                            .foregroundColor(Color.mimo.success)
                        Text("-\(appState.sessionGitTotals.deletions)")
                            .interfaceFont(size: 12, weight: .medium)
                            .foregroundColor(Color.mimo.error)
                    }
                } else {
                    Text(AppLocalization.string(.gitNoChanges, language: language))
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            
            if !appState.vcsChanges.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.vcsChanges, id: \.path) { file in
                            HStack(spacing: 6) {
                                Text((file.path as NSString).lastPathComponent)
                                    .interfaceFont(size: 11, design: .monospaced)
                                    .foregroundColor(Color.mimo.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if file.additions > 0 {
                                    Text("+\(file.additions)")
                                        .interfaceFont(size: 10, weight: .medium)
                                        .foregroundColor(Color.mimo.success)
                                }
                                if file.deletions > 0 {
                                    Text("-\(file.deletions)")
                                        .interfaceFont(size: 10, weight: .medium)
                                        .foregroundColor(Color.mimo.error)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
            
            HStack(spacing: 8) {
                Image(systemName: RightPanelLayout.branchIcon)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
                
                Text(AppLocalization.string(.gitBranch, language: language))
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textPrimary)
                
                Spacer()
                
                Menu {
                    ForEach(appState.gitBranches, id: \.self) { branch in
                        Button(action: { checkout(branch) }) {
                            HStack {
                                Text(branch)
                                if branch == appState.gitBranch {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(appState.gitBranch)
                        .interfaceFont(size: 12, design: .monospaced)
                        .foregroundColor(Color.mimo.textPrimary)
                }
                .menuStyle(.borderlessButton)
            }
            
            if isGitInitialized {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: RightPanelLayout.commitIcon)
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textMuted)
                        
                        Text(AppLocalization.string(.gitCommit, language: language))
                            .interfaceFont(size: 13)
                            .foregroundColor(Color.mimo.textPrimary)
                    }
                    
                    HStack(spacing: 8) {
                        PremiumPrimaryButton(
                            title: AppLocalization.string(.gitCommit, language: language),
                            systemImage: "checkmark.circle.fill",
                            isBusy: appState.isGitBusy,
                            isEnabled: hasChanges
                        ) {
                            showCommitDialog = true
                        }
                        .frame(maxWidth: .infinity)
                        
                        PremiumPrimaryButton(
                            title: AppLocalization.string(.gitReviewPush, language: language),
                            systemImage: "arrow.up.circle.fill",
                            isBusy: appState.isGitBusy,
                            isEnabled: appState.gitRepositoryPath != nil
                        ) {
                            showAutoReviewDialog = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                
                if !hasRemote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .interfaceFont(size: 12)
                                .foregroundColor(Color.mimo.textMuted)
                            
                            Text(AppLocalization.string(.gitPublish, language: language))
                                .interfaceFont(size: 13)
                                .foregroundColor(Color.mimo.textPrimary)
                        }
                        
                        PremiumPrimaryButton(
                            title: AppLocalization.string(.gitPublishToGithub, language: language),
                            systemImage: "arrow.up.forward.app.fill",
                            isBusy: appState.isGitBusy
                        ) {
                            showPublishDialog = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textMuted)
                        
                        Text(AppLocalization.string(.gitInitialize, language: language))
                            .interfaceFont(size: 13)
                            .foregroundColor(Color.mimo.textPrimary)
                    }
                    
                    PremiumPrimaryButton(
                        title: AppLocalization.string(.gitInitTitle, language: language),
                        systemImage: "plus.circle.fill",
                        isBusy: appState.isGitBusy
                    ) {
                        showInitDialog = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .onAppear {
            refreshGit()
            checkRepositoryState()
        }
        .onChange(of: appState.selectedSession?.id) { _ in
            refreshGit()
            checkRepositoryState()
        }
        .sheet(isPresented: $showCommitDialog) {
            CommitDialogView(
                language: language,
                autoSummary: autoSummary,
                isPresented: $showCommitDialog
            ) { message in
                Task { await appState.commitGitChanges(message: message) }
            }
        }
        .sheet(isPresented: $showInitDialog) {
            GitInitDialogView(language: language, isPresented: $showInitDialog) {
                Task { await initializeGitRepository() }
            }
        }
        .sheet(isPresented: $showPublishDialog) {
            GitHubPublishWizardView(
                language: language,
                workspaceName: appState.selectedWorkspace?.name ?? "",
                isPresented: $showPublishDialog
            ) { ghPath, repoName, isPublic in
                Task { await publishToGitHub(ghPath: ghPath, repoName: repoName, isPublic: isPublic) }
            }
        }
        .sheet(isPresented: $showAutoReviewDialog) {
            ReviewPushDialogView(
                language: language,
                autoSummary: autoSummary,
                isPresented: $showAutoReviewDialog
            ) { comment in
                Task { await reviewAndPush(comment: comment) }
            }
        }
    }
    
    private func refreshGit() {
        if let sessionID = appState.selectedSession?.id {
            appState.scheduleGitRefresh(sessionID: sessionID)
        } else {
            appState.scheduleGitRefresh()
        }
    }
    
    private func checkout(_ branch: String) {
        Task { await appState.checkoutGitBranch(branch) }
    }
    
    private func checkRepositoryState() {
        guard let path = appState.selectedWorkspace?.path else {
            isGitInitialized = false
            hasRemote = false
            return
        }
        let gitPath = (path as NSString).appendingPathComponent(".git")
        isGitInitialized = FileManager.default.fileExists(atPath: gitPath)
        guard isGitInitialized else {
            hasRemote = false
            return
        }
        Task.detached(priority: .utility) {
            let remotes = (try? GitRepository.remotes(in: path)) ?? []
            await MainActor.run {
                hasRemote = !remotes.isEmpty
            }
        }
    }
    
    private func initializeGitRepository() async {
        guard let path = appState.selectedWorkspace?.path else { return }
        
        await MainActor.run {
            appState.isGitBusy = true
            appState.gitStatusMessage = "Initializing Git repository..."
        }
        
        do {
            _ = try await Task.detached(priority: .utility) {
                try GitRepository.run(["init"], in: path)
            }.value
            await MainActor.run {
                appState.isGitBusy = false
                appState.gitStatusMessage = "Git repository initialized successfully"
                checkRepositoryState()
            }
        } catch {
            await MainActor.run {
                appState.isGitBusy = false
                appState.gitStatusMessage = "Failed to initialize Git: \(error.localizedDescription)"
            }
        }
    }
    
    private func publishToGitHub(ghPath: String, repoName: String, isPublic: Bool) async {
        await appState.publishWorkspaceToGitHub(ghPath: ghPath, repoName: repoName, isPublic: isPublic)
        checkRepositoryState()
    }
    
    private func reviewAndPush(comment: String) async {
        let message = CommitMessageComposer.compose(userComment: comment, summary: autoSummary)
        let commitSuccess = await appState.commitGitChanges(message: message)
        if commitSuccess {
            await appState.pushGitChanges()
        } else {
            await MainActor.run {
                appState.gitStatusMessage = "Commit failed — push was skipped."
            }
        }
    }
}


struct SubagentsSection: View {
    @EnvironmentObject var appState: AppState

    private var language: AppLanguage { appState.appLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: RightPanelLayout.subagentsIcon)
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.violet)
                Text(AppLocalization.string(.subagentsTitle, language: language))
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text("\(appState.subagentSessions.count)")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }
            ForEach(appState.subagentSessions) { session in
                SubagentRow(session: session) {
                    appState.selectSession(session)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SubagentRow: View {
    let session: ChatSession
    let onOpen: () -> Void
    @State private var hovering = false

    private var statusColor: Color {
        switch session.subagentStatus {
        case SubagentRunner.statusRunning: return Color.mimo.warning
        case SubagentRunner.statusFailed: return Color.mimo.error
        default: return Color.mimo.success
        }
    }

    private var statusIcon: String {
        switch session.subagentStatus {
        case SubagentRunner.statusRunning: return RightPanelLayout.subagentRunningIcon
        case SubagentRunner.statusFailed: return RightPanelLayout.subagentFailedIcon
        default: return RightPanelLayout.subagentDoneIcon
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(statusColor)
                    .frame(width: 12, alignment: .center)
                Text(session.title)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(session.durationLabel)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(hovering ? Color.mimo.brand.opacity(0.08) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { hovering = $0 }
    }
}

struct ProgressSection: View {
    @EnvironmentObject var appState: AppState
    
    private var language: AppLanguage { appState.appLanguage }
    
    var steps: [TaskStep] {
        if appState.currentSteps.isEmpty {
            return [TaskStep(title: AppLocalization.string(.noStepsYet, language: language), status: .waiting)]
        }
        return appState.currentSteps
    }
    
    var progress: TaskProgress { TaskProgress(steps: steps) }
    var hasRealSteps: Bool { !appState.currentSteps.isEmpty }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLocalization.string(.planTitle, language: language))
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                
                if hasRealSteps {
                    Text(progress.formatted)
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            
            if hasRealSteps {
                progressContent
            } else {
                placeholderRow
            }
        }
        .padding(16)
    }
    
    @ViewBuilder
    private var progressContent: some View {
        let completed = RightPanelProgressDisplay.completedSteps(steps)
        let inProgress = RightPanelProgressDisplay.inProgressSteps(steps)
        let inlineWaiting = RightPanelProgressDisplay.inlineWaitingSteps(steps)
        let collapsedWaiting = RightPanelProgressDisplay.collapsedWaitingCount(steps)
        
        if !completed.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: RightPanelLayout.completedHeaderIcon)
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Text(String(format: AppLocalization.string(.completedSteps, language: language), completed.count))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
        
        ForEach(inProgress) { step in
            progressRow(step: step, icon: RightPanelLayout.stepInProgressIcon, color: Color.mimo.warning, weight: .semibold)
        }
        
        ForEach(inlineWaiting) { step in
            progressRow(step: step, icon: RightPanelLayout.stepWaitingIcon, color: Color.mimo.textMuted, weight: .regular)
        }
        
        if collapsedWaiting > 0 {
            HStack(spacing: 6) {
                Image(systemName: RightPanelLayout.waitingHeaderIcon)
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Text(String(format: AppLocalization.string(.waitingSteps, language: language), collapsedWaiting))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .padding(.top, 2)
        }
    }
    
    private var placeholderRow: some View {
        HStack(spacing: 6) {
            Image(systemName: RightPanelLayout.stepWaitingIcon)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
            Text(AppLocalization.string(.noStepsYet, language: language))
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
        }
    }
    
    private func progressRow(step: TaskStep, icon: String, color: Color, weight: Font.Weight) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .interfaceFont(size: 10, weight: weight)
                .foregroundColor(color)
                .frame(width: 12, alignment: .center)
                .padding(.top, 1)
            
            Text(step.title)
                .interfaceFont(size: 11)
                .foregroundColor(step.status == .completed ? Color.mimo.textMuted : Color.mimo.textPrimary)
                .strikethrough(step.status == .completed)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
