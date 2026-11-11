import SwiftUI
import AppKit
struct WorkspacesOverviewSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    private var filtered: [Workspace] {
        SidebarWorkspaceLogic.filtered(appState.workspaces, query: query)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t(AppLocalizationKey.locOverview))
                    .interfaceFont(size: 18, weight: .semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.mimo.textMuted)
                TextField(L.t(AppLocalizationKey.locSearchWorkspaces), text: $query)
                    .zcodeTextFieldStyle()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // The "no project" entry of the project picker.
                    Button(action: {
                        appState.selectNoProject()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundColor(Color.mimo.brand)
                            Text(L.t("No project"))
                                .foregroundColor(Color.mimo.textPrimary)
                            Spacer()
                            if appState.isProjectlessMode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color.mimo.brand)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(HandCursorButtonStyle())

                    Divider()
                        .padding(.vertical, 4)

                    ForEach(filtered) { workspace in
                        Button(action: {
                            appState.selectWorkspace(workspace)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(Color.mimo.textMuted)
                                Text(workspace.name)
                                    .foregroundColor(Color.mimo.textPrimary)
                                Spacer()
                                if appState.selectedWorkspace?.id == workspace.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color.mimo.brand)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(HandCursorButtonStyle())
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 420)
        .background(Color.mimo.background)
    }
}

struct SearchPaletteView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    private var matchingSessions: [ChatSession] {
        SearchPaletteLogic.matchingSessions(appState.sessions, query: query)
    }

    private var matchingFiles: [FileIndexRecord] {
        appState.searchProjectFiles(query: query)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t(AppLocalizationKey.locSearch))
                    .interfaceFont(size: 20, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t("Close (Esc)"))
            }

            TextField(L.t(AppLocalizationKey.locSearchTasks), text: $query)
                .zcodeTextFieldStyle()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(matchingSessions) { session in
                        Button(action: {
                            appState.selectSession(session)
                            dismiss()
                        }) {
                            HStack {
                                Text(session.title)
                                    .interfaceFont(size: 13)
                                    .foregroundColor(Color.mimo.textPrimary)
                                Spacer()
                                Text(session.durationLabel)
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textMuted)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HandCursorButtonStyle())
                    }

                    if !matchingFiles.isEmpty {
                        Text(L.t(AppLocalizationKey.locProjectFiles))
                            .interfaceFont(size: 11, weight: .semibold)
                            .foregroundColor(Color.mimo.textMuted)
                            .padding(.top, 8)
                        ForEach(matchingFiles, id: \.path) { file in
                            Button(action: {
                                guard let root = appState.selectedWorkspace?.path else { return }
                                let url = URL(fileURLWithPath: root).appendingPathComponent(file.path)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(Color.mimo.textMuted)
                                    Text(file.path)
                                        .interfaceFont(size: 12)
                                        .foregroundColor(Color.mimo.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(file.language)
                                        .interfaceFont(size: 10)
                                        .foregroundColor(Color.mimo.textMuted)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(HandCursorButtonStyle())
                        }
                    }
                }
            }

            Text(L.t(AppLocalizationKey.locEscClose))
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
        }
        .padding(24)
        .frame(width: 480, height: 400)
        .background(Color.mimo.background)
        .onExitCommand {
            dismiss()
        }
    }
}

// MARK: - Archived projects popover (plan Раздел 11 Блок 2 п.16 + Раздел 8)

struct ArchivedProjectsPopover: View {
    @EnvironmentObject var appState: AppState
    @State private var archived: [ProjectRegistryEntry] = ProjectRegistryLogic.archived(
        ProjectRegistryStore.load()
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(AppLocalizationKey.locArchivedProjects))
                .interfaceFont(size: 13, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)

            if archived.isEmpty {
                Text(L.t(AppLocalizationKey.locArchivedProjects1))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            } else {
                ForEach(archived) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .interfaceFont(size: 12, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                            Text(entry.path)
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(L.t(AppLocalizationKey.locRestore)) { restore(entry) }
                            .interfaceFont(size: 11)
                            .buttonStyle(HandCursorButtonStyle())
                            .foregroundColor(Color.mimo.brand)
                    }
                }
            }

            Divider()
            Button(action: {
                appState.showArchivePopover = false
                appState.showSettings = true
                appState.settingsTab = .storage
            }) {
                Text(L.t(AppLocalizationKey.locOpenFullStoragePanel))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .padding(14)
        .frame(width: 320)
    }

    private func restore(_ entry: ProjectRegistryEntry) {
        try? ProjectRegistryStore.restore(id: entry.id)
        appState.refreshProjectRegistry()
        archived = ProjectRegistryLogic.archived(ProjectRegistryStore.load())
    }
}
