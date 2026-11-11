import SwiftUI
import AppKit
struct ProjectlessChatRow: View {
    let node: SidebarProjectlessChatNode
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var needsAttentionNow = false

    private func refreshAttention() {
        needsAttentionNow = SidebarAttentionLogic.chatNeedsAttention(
            sessionID: node.id,
            pendingApprovalCount: ToolApprovalCenter.shared.pendingCount(in: node.id),
            pendingQuestionSessionID: appState.pendingQuestionRequest?.sessionID
        )
    }

    private var isSelected: Bool {
        SidebarSelectionLogic.isSelected(sessionID: node.id, selectedSessionID: appState.selectedSession?.id)
    }

    private var timeBadge: String {
        let interval = Date().timeIntervalSince(node.session.updatedAt)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.mimo.cyan.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "bubble.left")
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.cyan)
            }

            Button(action: { appState.selectSession(node.session) }) {
                HStack(spacing: 6) {
                    if appState.streamingSessionIDs.contains(node.id) {
                        BackgroundActivityIndicator()
                    }
                    if needsAttentionNow {
                        AttentionBlinkDot()
                    }
                    Text(node.title)
                        .interfaceFont(size: 12, weight: .medium)
                        .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(isSelected ? L.t(AppLocalizationKey.locNow) : timeBadge)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .accessibilityIdentifier("sidebar.projectlessChat")

            if node.isPinned || isHovered {
                Button(action: { appState.toggleSidebarPin(id: SidebarPinID.chat(node.id)) }) {
                    Image(systemName: node.isPinned ? "pin.fill" : "pin")
                        .interfaceFont(size: 11)
                        .foregroundColor(node.isPinned ? Color.mimo.brand : Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(node.isPinned ? "Unpin chat" : "Pin chat to top")
                .accessibilityIdentifier("sidebar.pinChat")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? Color.mimo.textPrimary.opacity(0.06)
                : Color.clear
        )
        .cornerRadius(6)
        .onAppear(perform: refreshAttention)
        .onReceive(NotificationCenter.default.publisher(for: SidebarAttentionNotification.changed)) { _ in
            refreshAttention()
        }
        .onReceive(appState.$pendingQuestionRequest) { _ in
            refreshAttention()
        }
        .onHover { hovering in isHovered = hovering }
    }
}

struct SessionTaskRow: View {
    let session: ChatSession
    let workspace: Workspace
    let groupColor: Color
    var isHovered: Bool = false
    @EnvironmentObject var appState: AppState
    @State private var isRenaming = false
    @FocusState private var isRenameFocused: Bool
    @State private var showingDeleteConfirm = false
    @State private var renameText = ""
    @State private var needsAttentionNow = false

    /// «Звоночек»: чат ждёт решения пользователя (одобрение инструмента или
    /// вопрос) — строка моргает подсветкой.
    private func refreshAttention() {
        needsAttentionNow = SidebarAttentionLogic.chatNeedsAttention(
            sessionID: session.id,
            pendingApprovalCount: ToolApprovalCenter.shared.pendingCount(in: session.id),
            pendingQuestionSessionID: appState.pendingQuestionRequest?.sessionID
        )
    }

    private func commitRename() {
        isRenaming = false
        appState.renameSessionInDatabaseUI(id: session.id, title: renameText)
    }
    
    var isSelected: Bool {
        SidebarSelectionLogic.isSelected(sessionID: session.id, selectedSessionID: appState.selectedSession?.id)
    }
    
    private var timeBadge: String {
        let interval = Date().timeIntervalSince(session.updatedAt)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Color indicator strip (only for selected)
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(groupColor)
                    .frame(width: 2)
            } else {
                Color.clear
                    .frame(width: 2)
            }
            
            // Session content
            if isRenaming {
                HStack(spacing: 6) {
                    TextField(L.t("Chat title"), text: $renameText)
                        .textFieldStyle(.plain)
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textPrimary)
                        .focused($isRenameFocused)
                        .onAppear { isRenameFocused = true }
                        .onSubmit(commitRename)
                        .onChange(of: isRenameFocused) { focused in
                            if !focused, isRenaming { commitRename() }
                        }
                        .onExitCommand { isRenaming = false }

                    Button(action: commitRename) {
                        Image(systemName: "checkmark")
                            .interfaceFont(size: 10, weight: .semibold)
                            .foregroundColor(Color.mimo.cyan)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t("Save title"))

                    Button(action: { isRenaming = false }) {
                        Image(systemName: "xmark")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t("Cancel rename"))
                }
            } else {
                Button(action: { appState.selectSession(session) }) {
                    HStack(spacing: 6) {
                        if appState.streamingSessionIDs.contains(session.id) {
                            BackgroundActivityIndicator()
                        }
                        if needsAttentionNow {
                            AttentionBlinkDot()
                        }
                        Text(session.title)
                            .interfaceFont(size: 12)
                            .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelected {
                            // "now" badge
                            Text(L.t(AppLocalizationKey.locNow))
                                .interfaceFont(size: 9, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.mimo.textPrimary.opacity(0.12))
                                .cornerRadius(4)
                        } else {
                            // Time badge
                            Text(timeBadge)
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.textMuted)
                        }
                    }
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: { appState.startNewTask(in: workspace) }) {
                        Image(systemName: "plus")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    
                    Menu {
                        Button(L.t("Rename…")) {
                            renameText = session.title
                            isRenaming = true
                        }
                        ShareLink(item: appState.sessionTranscriptMarkdown(sessionId: session.id) ?? session.title) {
                            Text(L.t("Share transcript"))
                        }
                        Button(L.t("Export transcript…")) {
                            appState.exportSessionTranscript(sessionId: session.id)
                        }
                        Divider()
                        if SessionRowActions.showInFinderURL(session: session, workspace: workspace) != nil {
                            Button(L.t(AppLocalizationKey.locShowInFinder)) {
                                appState.openFolderInFinder(session.directory.isEmpty ? workspace.path : session.directory)
                            }
                        }
                        Button(L.t(AppLocalizationKey.locNewTaskSidebar)) {
                            appState.startNewTask(in: workspace)
                        }
                        Button(L.t(AppLocalizationKey.locArchive)) {
                            appState.archiveSessionInDatabaseUI(id: session.id)
                        }
                        Divider()
                        Button(L.t("Delete…"), role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.vertical")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.leading, 50)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? Color.mimo.textPrimary.opacity(0.06)
                : Color.clear
        )
        .cornerRadius(6)
        .onAppear(perform: refreshAttention)
        .onReceive(NotificationCenter.default.publisher(for: SidebarAttentionNotification.changed)) { _ in
            refreshAttention()
        }
        .onReceive(appState.$pendingQuestionRequest) { _ in
            refreshAttention()
        }
        .alert(L.t("Delete this chat?"), isPresented: $showingDeleteConfirm) {
            Button(L.t(AppLocalizationKey.locDelete), role: .destructive) {
                appState.deleteSessionInDatabaseUI(id: session.id)
            }
            Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
        } message: {
            Text(L.t("This permanently removes the chat and its messages from the local database. It cannot be undone."))
        }
    }
}

/// Sidebar group for standalone chats — conversations that do not belong to
/// any project (audit 2026-09-08, user directive: such chats used to disappear
/// because nothing listed them). Persisted in the global DB; synthetic
/// workspace keeps SessionTaskRow happy.
