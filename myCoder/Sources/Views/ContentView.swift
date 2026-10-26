import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiPendingMessage: String?

    /// Persisted, user-resizable sidebar width (plan Раздел 11 Блок 1).
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 260
    private let sidebarMinWidth: Double = 200
    private let sidebarMaxWidth: Double = 420
    private let sidebarDefaultWidth: Double = 260

    var body: some View {
        HStack(spacing: 0) {
            if appState.sidebarVisible {
                SidebarView()
                    .frame(width: sidebarWidth)

                SidebarResizeHandle(width: $sidebarWidth,
                                    minWidth: sidebarMinWidth,
                                    maxWidth: sidebarMaxWidth,
                                    defaultWidth: sidebarDefaultWidth)
            }

            VStack(spacing: 0) {
                TopBarView()

                if let wizardPath = appState.activeSpecWizardProjectPath,
                   let workspace = appState.selectedWorkspace,
                   ChatSession.normalizedPath(workspace.path) == wizardPath {
                    SpecWizardView(projectPath: wizardPath, projectName: workspace.name)
                } else {
                    ChatPanelView()
                }
                
                if appState.showTerminal {
                    Rectangle()
                        .fill(Color.mimo.border)
                        .frame(height: 1)
                    
                    BottomPanelView()
                        .frame(height: 240)
                }
                
                StatusBarView(isStreaming: appState.isStreaming, isLoading: appState.isLoading)
                    .frame(height: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if appState.showGoal {
                Rectangle()
                    .fill(Color.mimo.border)
                    .frame(width: 1)
                
                RightPanelView()
                    .frame(width: 300)
            }
        }
        .background(Color.mimo.background)
        .environment(\.interfaceFontScale, appState.settings.zoom.fontScale)
        .preferredColorScheme(appState.appTheme.preferredColorScheme)
        // RTL layout for Arabic (plan Раздел 2 Блок 2 п.15).
        .environment(\.layoutDirection, appState.appLanguage.isRTL ? .rightToLeft : .leftToRight)
        .task {
            appState.loadCustomProviders()
            await appState.connectToServer()
            async let sessions: () = appState.loadSessionsFromServer()
            async let models: () = appState.serverConnected ? appState.loadModelsFromServer() : ()
            await sessions
            await models
        }
        .overlay { settingsOverlay }
        .animation(.easeOut(duration: 0.15), value: appState.showSettings)
        .sheet(isPresented: $appState.showSearch) {
            SearchPaletteView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showRemoteConnection) {
            RemoteConnectionSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showProjectCreation) {
            NewProjectSheet()
                .environmentObject(appState)
        }
        // E08 (Раздел 5 п.13/15/16): slash commands open the real git dialogs
        // through a single app-state-driven sheet (works even when the right
        // panel is hidden).
        .sheet(item: $appState.pendingGitAction) { action in
            GitActionSheet(action: action)
                .environmentObject(appState)
        }
        // E04 (Раздел 8 п.48): a corrupted project DB detected at open time
        // offers to restore the latest auto-backup.
        .alert(
            L.t(AppLocalizationKey.locProjectDatabaseCorrupted),
            isPresented: Binding(
                get: { appState.projectIntegrityAlert != nil },
                set: { if !$0 { appState.projectIntegrityAlert = nil } }
            ),
            presenting: appState.projectIntegrityAlert
        ) { alert in
            Button(L.t(AppLocalizationKey.locRestoreFromBackup)) {
                let path = alert.projectPath
                Task {
                    do {
                        let restored = try ProjectOpenIntegrity.restoreLatestBackup(projectPath: path)
                        appState.gitStatusMessage = restored == nil
                            ? L.t(AppLocalizationKey.locNoBackupFound)
                            : L.t(AppLocalizationKey.locDatabaseRestored)
                    } catch {
                        appState.gitStatusMessage = L.t(AppLocalizationKey.locRestoreFailed, error.localizedDescription)
                    }
                }
            }
            Button(L.t(AppLocalizationKey.locIgnore), role: .cancel) {
                appState.projectIntegrityAlert = nil
            }
        } message: { alert in
            Text(L.t(AppLocalizationKey.locIntegrityCheckFailed, alert.message))
        }
    }

    /// Settings as a dismissable overlay instead of a modal sheet:
    /// clicking the dimmed backdrop (or pressing Escape) closes it.
    @ViewBuilder
    private var settingsOverlay: some View {
        if appState.showSettings {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { appState.showSettings = false }

                SettingsView()
                    .environmentObject(appState)
                    .frame(maxWidth: 960, maxHeight: 720)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.mimo.border, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 10)
                    .padding(24)

                // Invisible button so Escape keeps closing settings,
                // matching the old sheet behavior.
                Button("") { appState.showSettings = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(HandCursorButtonStyle())
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .transition(.opacity)
        }
    }
}

/// Drag handle that resizes the sidebar between min/max bounds, persists the
/// chosen width, and resets to default on double-click. Replaces the static
/// 1pt divider in ContentView (plan Раздел 11 Блок 1).
struct SidebarResizeHandle: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    let defaultWidth: Double

    @State private var isHovering = false
    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color.mimo.border)
            .frame(width: isHovering ? 3 : 1)
            .contentShape(Rectangle().inset(by: -6))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        width = SidebarResizeLogic.applyDrag(
                            current: dragStartWidth ?? width,
                            translation: value.translation.width,
                            min: minWidth,
                            max: maxWidth
                        )
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .onTapGesture(count: 2) {
                width = defaultWidth
            }
            .accessibilityLabel("Sidebar resizer")
            .accessibilityHint("Drag to resize the sidebar; double-click to reset.")
    }
}

/// The dialog presented for `AppState.pendingGitAction` (E08, Раздел 5
/// п.13/15/16). Each case opens the REAL existing flow; dismissing the dialog
/// clears the trigger.
struct GitActionSheet: View {
    @EnvironmentObject var appState: AppState
    let action: GitUIAction

    private var language: AppLanguage { appState.appLanguage }

    private var autoSummary: String {
        CommitMessageComposer.summary(
            fileNames: appState.vcsChanges.map { ($0.path as NSString).lastPathComponent },
            insertions: appState.sessionGitTotals.additions,
            deletions: appState.sessionGitTotals.deletions
        )
    }

    private var dismissBinding: Binding<Bool> {
        Binding(
            get: { appState.pendingGitAction != nil },
            set: { if !$0 { appState.pendingGitAction = nil } }
        )
    }

    var body: some View {
        switch action {
        case .openCommitComposer:
            CommitDialogView(language: language, autoSummary: autoSummary, isPresented: dismissBinding) { message in
                Task { await appState.commitGitChanges(message: message) }
            }
        case .openReviewDialog:
            ReviewPushDialogView(language: language, autoSummary: autoSummary, isPresented: dismissBinding) { comment in
                Task {
                    let message = CommitMessageComposer.compose(userComment: comment, summary: autoSummary)
                    let committed = await appState.commitGitChanges(message: message)
                    if committed { await appState.pushGitChanges() }
                }
            }
        case .openPublishWizard:
            GitHubPublishWizardView(
                language: language,
                workspaceName: appState.selectedWorkspace?.name ?? "",
                isPresented: dismissBinding
            ) { ghPath, repoName, isPublic in
                Task { await appState.publishWorkspaceToGitHub(ghPath: ghPath, repoName: repoName, isPublic: isPublic) }
            }
        case .createPullRequest:
            PullRequestDialogView(
                language: language,
                workspacePath: appState.selectedWorkspace?.path ?? "",
                isPresented: dismissBinding
            ) { title, body in
                Task { await appState.createGitHubPullRequest(title: title, body: body) }
            }
        }
    }
}
