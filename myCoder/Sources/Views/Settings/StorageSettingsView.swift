import SwiftUI

struct StorageSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats = StorageStats(databaseSize: 0, snapshotSize: 0, messageCount: 0, sessionCountsByProject: [])
    // Round 12: two distinct confirmations — one for "delete older than N days"
    // and one for "delete all archived chats". They used to share the same
    // alert, which crashed / ran the wrong action (P2).
    @State private var showDeleteOlderConfirmation = false
    @State private var showDeleteArchivedConfirmation = false
    @State private var showRemoveOrphansConfirmation = false
    @State private var showResetConfirmation = false
    @State private var pendingResetScope: StorageResetScope = .appCacheOnly
    @State private var archiveDays: Double = 7
    @State private var deleteDays: Double = 30
    @State private var projectEntries: [ProjectRegistryEntry] = []
    // Delete-project guard (plan Раздел 8 п.24/п.54): destructive action requires
    // typing the project name — GitHub "type repo name to delete" pattern.
    @State private var pendingDeleteEntry: ProjectRegistryEntry?
    @State private var deleteConfirmName = ""
    // Quota status (plan Раздел 8 п.50): informative warning when the sum of all
    // per-project DBs crosses the threshold — never blocks, always suggests.
    @State private var quota = ProjectStorageAdmin.StorageQuotaStatus(
        totalBytes: 0, thresholdBytes: 0, archivableBytes: 0, archivedBytes: 0
    )
    @State private var deletionInProgress = false
    @State private var deletionProgress = 0.0
    @State private var deletionProgressLabel = ""
    @State private var deletionCancelRequested = false
    @State private var deletionCancellation: ProjectDeletionCancellation?
    @State private var deletionTask: Task<Void, Never>?
    @State private var deletionNotice: ProjectDeletionOutcomeLogic.Notice?
    @State private var pendingAppConfigurationImportURL: URL?
    @State private var appConfigurationNotice: AppConfigurationTransferLogic.Notice?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locStorageDatabase))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)

            // Per-project administration (plan Раздел 8 Блок 3 п.21-24)
            projectsAdminSection

            // Statistics card
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t(AppLocalizationKey.locUsage))
                        .interfaceFont(size: 13, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    
                    HStack(spacing: 16) {
                        StorageStatView(title: L.t(AppLocalizationKey.locDatabase), value: stats.databaseSizeFormatted, icon: "externaldrive")
                        StorageStatView(title: L.t(AppLocalizationKey.locSnapshots), value: stats.snapshotSizeFormatted, icon: "clock.arrow.circlepath")
                        StorageStatView(title: L.t(AppLocalizationKey.locTotal), value: stats.totalSizeFormatted, icon: "externaldrive.fill")
                    }
                    
                    Divider()
                    
                    HStack(spacing: 16) {
                        StorageStatView(title: L.t(AppLocalizationKey.locMessages), value: "\(stats.messageCount)", icon: "message")
                        StorageStatView(title: L.t(AppLocalizationKey.locActiveChats), value: "\(stats.totalActiveSessions)", icon: "bubble.left")
                        StorageStatView(title: L.t(AppLocalizationKey.locArchived), value: "\(stats.totalArchivedSessions)", icon: "archivebox")
                    }
                    
                    if !stats.sessionCountsByProject.isEmpty {
                        Divider()
                        Text(L.t(AppLocalizationKey.locPerProject))
                            .interfaceFont(size: 11, weight: .medium)
                            .foregroundColor(Color.mimo.textMuted)
                        
                        ForEach(stats.sessionCountsByProject, id: \.projectId) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .interfaceFont(size: 10)
                                    .foregroundColor(Color.mimo.textMuted)
                                Text(item.projectId)
                                    .interfaceFont(size: 11, design: .monospaced)
                                    .lineLimit(1)
                                    .foregroundColor(Color.mimo.textSecondary)
                                Spacer()
                                Text(L.t(AppLocalizationKey.locActiveCount, item.active))
                                    .interfaceFont(size: 10)
                                    .foregroundColor(Color.mimo.success)
                                Text(L.t(AppLocalizationKey.locArchivedCount, item.archived))
                                    .interfaceFont(size: 10)
                                    .foregroundColor(Color.mimo.textMuted)
                            }
                        }
                    }
                }
                .padding(4)
            }
            
            // Auto-archive card
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t(AppLocalizationKey.locAutoarchive))
                        .interfaceFont(size: 13, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    
                    Text(L.t(AppLocalizationKey.locInactiveChatsAreAutomaticallyArchivedAfterTheSe))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                    
                    HStack(spacing: 8) {
                        Text(L.t(AppLocalizationKey.locArchiveAfter))
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textSecondary)
                        Picker("", selection: $archiveDays) {
                            Text(L.t(AppLocalizationKey.locDays1)).tag(3.0)
                            Text(L.t(AppLocalizationKey.locDays3)).tag(7.0)
                            Text(L.t(AppLocalizationKey.locDays)).tag(14.0)
                            Text(L.t(AppLocalizationKey.locDays2)).tag(30.0)
                            Text(L.t(AppLocalizationKey.locDays4)).tag(90.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        
                        Button(L.t(AppLocalizationKey.locArchiveNow)) {
                            appState.archiveOldSessions(days: Int(archiveDays))
                            refreshStats()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(L.t(AppLocalizationKey.locArchiveNow))
                    }
                }
                .padding(4)
            }
            
            // Cleanup card
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t(AppLocalizationKey.locCleanup))
                        .interfaceFont(size: 13, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    
                    HStack(spacing: 8) {
                        Text(L.t(AppLocalizationKey.locDeleteChatsOlderThan))
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textSecondary)
                        Picker("", selection: $deleteDays) {
                            Text(L.t(AppLocalizationKey.locDays3)).tag(7.0)
                            Text(L.t(AppLocalizationKey.locDays2)).tag(30.0)
                            Text(L.t(AppLocalizationKey.locDays4)).tag(90.0)
                            Text(L.t(AppLocalizationKey.loc180Days)).tag(180.0)
                            Text(L.t(AppLocalizationKey.locYear)).tag(365.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        
                        Button(L.t(AppLocalizationKey.locDelete), role: .destructive) {
                            showDeleteOlderConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(L.t(AppLocalizationKey.locDeleteChatsOlderThan))
                    }

                    Divider()

                    Button(L.t(AppLocalizationKey.deleteAllArchivedChats)) {
                        showDeleteArchivedConfirmation = true
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.error)
                    .interfaceFont(size: 12)
                    .help(L.t(AppLocalizationKey.deleteAllArchivedChats))

                    Divider()

                    Button(L.t(AppLocalizationKey.compressDatabase)) {
                        appState.vacuumDatabase()
                        refreshStats()
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.brand)
                    .interfaceFont(size: 12)
                    .help(L.t(AppLocalizationKey.compressDatabase))
                    
                    Divider()
                    
                    // Explicit reset scenario (plan Раздел 8 Блок 1 п.10):
                    // clear the app database. No CLI-history options — the
                    // app is HTTP-only (clean slate).
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string(.resetStorageTitle, language: appState.appLanguage))
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Button(AppLocalization.string(.resetAppCache, language: appState.appLanguage)) {
                        pendingResetScope = .appCacheOnly; showResetConfirmation = true
                    }
                    .buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.error).interfaceFont(size: 12)
                    .help(AppLocalization.string(.resetAppCacheWarning, language: appState.appLanguage))

                    Button {
                        pendingResetScope = .fullDatabase; showResetConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(AppLocalization.string(.resetFullDatabase, language: appState.appLanguage))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.mimo.error)
                    .controlSize(.small)
                    .help(AppLocalization.string(.resetFullDatabaseWarning, language: appState.appLanguage))
                }
            }
                }
                .padding(4)
            }
            .alert(L.t(AppLocalizationKey.locAlertDeleteOldChats), isPresented: $showDeleteOlderConfirmation) {
                Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
                Button(L.t(AppLocalizationKey.locDelete), role: .destructive) {
                    _ = appState.deleteSessionsOlderThan(days: Int(deleteDays))
                    refreshStats()
                }
            } message: {
                Text(L.t(AppLocalizationKey.locDeleteChatsConfirmMessage).replacingOccurrences(of: "%d", with: "\(Int(deleteDays))"))
            }
            .alert(L.t(AppLocalizationKey.locAlertDeleteArchivedChats), isPresented: $showDeleteArchivedConfirmation) {
                Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
                Button(L.t(AppLocalizationKey.locDelete), role: .destructive) {
                    _ = appState.deleteArchivedSessions()
                    refreshStats()
                }
            } message: {
                Text(L.t(AppLocalizationKey.locThisWillPermanentlyDeleteAllArchivedChatsAndThe))
            }
            .alert(L.t(AppLocalizationKey.locAlertRemoveOrphanedRecords), isPresented: $showRemoveOrphansConfirmation) {
                Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
                Button(L.t(AppLocalizationKey.locRemoveOrphanedRecords), role: .destructive) {
                    mutateProjects { ProjectRegistryLogic.removingOrphaned($0) }
                    refreshStats()
                }
            } message: {
                Text(L.t(AppLocalizationKey.locRemoveOrphanedRecordsMessage)
                    .replacingOccurrences(of: "{0}", with: "\(orphanedCount)"))
            }
            .alert(resetAlertTitle, isPresented: $showResetConfirmation) {
                Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {}
                Button(L.t(AppLocalizationKey.locResetButton), role: .destructive) {
                    appState.resetStorage(
                        scope: pendingResetScope,
                        projectPaths: projectEntries.map(\.path)
                    )
                    refreshStats()
                }
            } message: {
                Text(resetAlertMessage)
            }
            .alert(
                L.t(AppLocalizationKey.locReplaceAppConfiguration),
                isPresented: Binding(
                    get: { pendingAppConfigurationImportURL != nil },
                    set: { if !$0 { pendingAppConfigurationImportURL = nil } }
                )
            ) {
                Button(L.t(AppLocalizationKey.locCancel), role: .cancel) {
                    pendingAppConfigurationImportURL = nil
                }
                Button(L.t(AppLocalizationKey.locStorageImportReplace), role: .destructive) {
                    guard let url = pendingAppConfigurationImportURL else { return }
                    pendingAppConfigurationImportURL = nil
                    performAppConfigurationImport(from: url)
                }
            } message: {
                Text(L.t(AppLocalizationKey.locStorageImportWarning))
            }
            .alert(
                L.t(AppLocalizationKey.locAlertDeleteProject),
                isPresented: Binding(
                    get: { pendingDeleteEntry != nil },
                    set: { if !$0 { pendingDeleteEntry = nil } }
                )
            ) {
                TextField(L.t(AppLocalizationKey.locTypeToConfirm).replacingOccurrences(of: "{0}", with: pendingDeleteEntry?.name ?? ""), text: $deleteConfirmName)
                Button(L.t(AppLocalizationKey.locCancel), role: .cancel) { pendingDeleteEntry = nil }
                Button(L.t(AppLocalizationKey.locDelete), role: .destructive) {
                    if let entry = pendingDeleteEntry { deleteProject(entry) }
                    pendingDeleteEntry = nil
                }
                .disabled(!ProjectDeleteConfirmation.isConfirmed(
                    projectName: pendingDeleteEntry?.name ?? "",
                    typed: deleteConfirmName
                ))
            } message: {
                Text(ProjectDeleteConfirmation.deletionDescription(
                    projectPath: pendingDeleteEntry?.path ?? ""
                ))
            }
            .alert(
                appConfigurationNotice?.title ?? "",
                isPresented: Binding(
                    get: { appConfigurationNotice != nil },
                    set: { if !$0 { appConfigurationNotice = nil } }
                )
            ) {
                Button(L.t(AppLocalizationKey.locOK)) {
                    appConfigurationNotice = nil
                }
            } message: {
                Text(appConfigurationNotice?.message ?? "")
            }
            .alert(
                deletionNotice?.title ?? "",
                isPresented: Binding(
                    get: { deletionNotice != nil },
                    set: { if !$0 { deletionNotice = nil } }
                )
            ) {
                Button(L.t(AppLocalizationKey.locOK)) {
                    deletionNotice = nil
                }
            } message: {
                Text(deletionNotice?.message ?? "")
            }
        }
        .onAppear(perform: refreshStats)
        .onDisappear {
            deletionCancellation?.cancel()
            deletionTask?.cancel()
        }
    }

    private var resetAlertTitle: String {
        switch pendingResetScope {
        case .appCacheOnly:
            return AppLocalization.string(.resetAppCacheConfirmTitle, language: appState.appLanguage)
        case .fullDatabase:
            return AppLocalization.string(.resetFullDatabaseConfirmTitle, language: appState.appLanguage)
        }
    }

    private var resetAlertMessage: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plan = StorageResetLogic.plan(
            for: pendingResetScope,
            homeDirectory: home,
            projectPaths: projectEntries.map(\.path)
        )
        let warning = pendingResetScope == .fullDatabase
            ? AppLocalization.string(.resetFullDatabaseWarning, language: appState.appLanguage)
            : AppLocalization.string(.resetAppCacheWarning, language: appState.appLanguage)
        let heading = AppLocalization.string(.resetPlanPathsTitle, language: appState.appLanguage)
        return warning + "\n\n" + heading + "\n" + StorageResetLogic.summary(for: plan)
    }
    
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var orphanedCount: Int {
        ProjectRegistryLogic.orphaned(projectEntries).count
    }

    private var projectsAdminSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t(AppLocalizationKey.locProjects))
                    .interfaceFont(size: 16, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                Button(L.t(AppLocalizationKey.locStorageExportConfiguration)) {
                    exportAppConfiguration()
                }
                .interfaceFont(size: 11).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand)
                .help(L.t(AppLocalizationKey.locStorageExportConfiguration))
                Button(L.t(AppLocalizationKey.locStorageImportConfiguration)) {
                    importAppConfiguration()
                }
                .interfaceFont(size: 11).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand)
                .help(L.t(AppLocalizationKey.locStorageImportConfiguration))
                Button(L.t(AppLocalizationKey.locArchiveInactiveDays).replacingOccurrences(of: "{0}", with: "\(Int(archiveDays))")) {
                    mutateProjects { ProjectStorageAdmin.archiveAllInactive(days: Int(archiveDays), in: $0) }
                }
                .interfaceFont(size: 11).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand)
                .help(L.t(AppLocalizationKey.locBulkArchiveHelp))
                if orphanedCount > 0 {
                    Button(L.t(AppLocalizationKey.locRemoveOrphanedRecords)) {
                        showRemoveOrphansConfirmation = true
                    }
                    .interfaceFont(size: 11).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.warning)
                    .help(L.t(AppLocalizationKey.locRemoveOrphanedRecordsHelp))
                }
            }
            // Quota warning (plan Раздел 8 п.50): inform, never block.
            if deletionInProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView(value: deletionProgress)
                            .progressViewStyle(.linear)
                        Text(deletionProgressLabel.isEmpty ? L.t(AppLocalizationKey.locDeletingProjectData) : deletionProgressLabel)
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                            .lineLimit(1)
                        Button(L.t(AppLocalizationKey.locCancelDeletion)) {
                            deletionCancelRequested = true
                            deletionCancellation?.cancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(deletionCancelRequested)
                        .help(L.t(AppLocalizationKey.locCancelDeletion))
                    }
                    Text(L.t(AppLocalizationKey.locProjectRegistryDeletionWarning))
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .padding(10)
                .background(Color.mimo.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if quota.isOverQuota {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t(AppLocalizationKey.locStorageQuotaExceeded))
                            .interfaceFont(size: 12, weight: .semibold)
                            .foregroundColor(Color.mimo.textPrimary)
                        Text(L.t(AppLocalizationKey.locQuotaWarning)
                            .replacingOccurrences(of: "{0}", with: quota.totalBytes.formatted(.byteCount(style: .file)))
                            .replacingOccurrences(of: "{1}", with: quota.thresholdBytes.formatted(.byteCount(style: .file)))
                            .replacingOccurrences(of: "{2}", with: quota.archivableBytes.formatted(.byteCount(style: .file))))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(L.t(AppLocalizationKey.locArchiveInactive)) {
                        mutateProjects { ProjectStorageAdmin.archiveAllInactive(days: Int(archiveDays), in: $0) }
                    }
                    .interfaceFont(size: 11)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.mimo.warning)
                    .help(L.t(AppLocalizationKey.locArchiveInactive))
                }
                .padding(10)
                .background(Color.mimo.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            let active = ProjectRegistryLogic.active(projectEntries)
            let archived = ProjectRegistryLogic.archived(projectEntries)
            let orphans = ProjectRegistryLogic.orphaned(projectEntries)
            if active.isEmpty && archived.isEmpty && orphans.isEmpty {
                Text(L.t(AppLocalizationKey.locProjectsRegisteredYet))
                    .interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
            }
            ForEach(active) { entry in
                projectRow(entry, archived: false)
            }
            if !archived.isEmpty {
                Text(L.t(AppLocalizationKey.locArchived))
                    .interfaceFont(size: 11, weight: .semibold).foregroundColor(Color.mimo.textMuted)
                ForEach(archived) { entry in
                    projectRow(entry, archived: true)
                }
            }
            if !orphans.isEmpty {
                // Plan Раздел 8 п.31: registry entries whose path no longer exists
                // are shown explicitly, with "Find new path" (relink) or "Delete record".
                Text(L.t(AppLocalizationKey.locOrphanedPathMissing))
                    .interfaceFont(size: 11, weight: .semibold).foregroundColor(Color.mimo.warning)
                ForEach(orphans) { entry in
                    orphanRow(entry)
                }
            }
        }
    }

    private func orphanRow(_ entry: ProjectRegistryEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .interfaceFont(size: 11).foregroundColor(Color.mimo.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).interfaceFont(size: 12, weight: .medium).foregroundColor(Color.mimo.textPrimary)
                Text(entry.path).interfaceFont(size: 10).foregroundColor(Color.mimo.warning).lineLimit(1)
            }
            Spacer()
            Button(L.t(AppLocalizationKey.locFindNewPath2)) { relinkProject(entry) }
                .interfaceFont(size: 11).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand)
                .help(L.t(AppLocalizationKey.locFindNewPath2))
            Button(action: {
                deleteConfirmName = ""
                pendingDeleteEntry = entry
            }) {
                Image(systemName: "trash").interfaceFont(size: 11).foregroundColor(Color.mimo.error)
            }
            .disabled(deletionInProgress)
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locDeleteRecord))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.warning.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func relinkProject(_ entry: ProjectRegistryEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L.t(AppLocalizationKey.locFindProjectFolder)
        panel.prompt = L.t(AppLocalizationKey.locRelink)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectRegistryStore.relink(id: entry.id, toNewPath: url.path)
            appState.refreshProjectRegistry()
            refreshStats()
        } catch {
            deletionNotice = ProjectDeletionOutcomeLogic.notice(
                .failed("The project could not be re-linked: \(error.localizedDescription)")
            )
        }
    }

    private func projectRow(_ entry: ProjectRegistryEntry, archived: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: archived ? "archivebox" : "folder")
                .interfaceFont(size: 11).foregroundColor(Color.mimo.textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).interfaceFont(size: 12, weight: .medium).foregroundColor(Color.mimo.textPrimary)
                Text(entry.path).interfaceFont(size: 10).foregroundColor(Color.mimo.textMuted).lineLimit(1)
            }
            Spacer()
            if archived {
                Button(L.t(AppLocalizationKey.locRestore)) { mutateProjects { ProjectRegistryLogic.restore(id: entry.id, in: $0) } }
                    .interfaceFont(size: 11).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.brand)
                    .help(L.t(AppLocalizationKey.locRestore))
            } else {
                Button(L.t(AppLocalizationKey.locArchive)) { mutateProjects { ProjectRegistryLogic.archive(id: entry.id, at: Date(), in: $0) } }
                    .interfaceFont(size: 11).buttonStyle(HandCursorButtonStyle()).foregroundColor(Color.mimo.textSecondary)
                    .help(L.t(AppLocalizationKey.locArchive))
            }
            Button(action: {
                deleteConfirmName = ""
                pendingDeleteEntry = entry
            }) {
                Image(systemName: "trash").interfaceFont(size: 11).foregroundColor(Color.mimo.error)
            }
            .disabled(deletionInProgress)
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locDeleteProjectHelp2))

            Button(action: {
                if appState.vacuumProject(path: entry.path) { refreshStats() }
            }) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .interfaceFont(size: 11).foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locCompressProjectHelp))

            Button(action: { exportProjectBackup(entry) }) {
                Image(systemName: "square.and.arrow.up")
                    .interfaceFont(size: 11).foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locExportBackupHelp))

            Button(action: { importProjectBackup(entry) }) {
                Image(systemName: "square.and.arrow.down")
                    .interfaceFont(size: 11).foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locRestoreBackupHelp))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.mimo.surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func exportProjectBackup(_ entry: ProjectRegistryEntry) {
        let plan = ProjectBackupLogic.plan(projectPath: entry.path)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = plan.archiveName
        panel.canCreateDirectories = true
        panel.prompt = L.t(AppLocalizationKey.locExportBackupPrompt)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if ProjectBackupLogic.export(projectPath: entry.path, to: url) {
            refreshStats()
        }
    }

    private func exportAppConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mycoder-app-configuration.json"
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let succeeded = AppConfigurationBackupStore.export(
            defaults: appState.defaults,
            to: url
        )
        appConfigurationNotice = AppConfigurationTransferLogic.notice(
            operation: .export,
            succeeded: succeeded
        )
    }

    private func importAppConfiguration() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard AppConfigurationTransferLogic.importRequiresConfirmation else {
            performAppConfigurationImport(from: url)
            return
        }
        pendingAppConfigurationImportURL = url
    }

    private func performAppConfigurationImport(from url: URL) {
        let succeeded = AppConfigurationBackupStore.import(
            from: url,
            defaults: appState.defaults
        )
        appConfigurationNotice = AppConfigurationTransferLogic.notice(
            operation: .import,
            succeeded: succeeded
        )
        guard succeeded else { return }
        appState.settings = AppSettings.load(from: appState.defaults)
        appState.refreshProjectRegistry()
        refreshStats()
    }

    private func importProjectBackup(_ entry: ProjectRegistryEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        panel.prompt = L.t(AppLocalizationKey.locRestoreBackupPrompt)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if ProjectBackupLogic.importBackup(from: url, projectPath: entry.path) {
            refreshStats()
        }
    }

    private func loadProjectEntries() {
        projectEntries = ProjectRegistryStore.load()
    }

    private func mutateProjects(_ transform: ([ProjectRegistryEntry]) -> [ProjectRegistryEntry]) {
        let before = ProjectRegistryStore.load()
        let updated = transform(before)
        // Audit every registry mutation (plan Раздел 8 п.46) so destructive
        // operations are reconstructable later.
        if updated != before {
            let added = updated.filter { e in !before.contains { $0.id == e.id } }
            let removed = before.filter { e in !updated.contains { $0.id == e.id } }
            if !added.isEmpty {
                try? StorageAuditLog.append(action: "registry.add", detail: added.map(\.path).joined(separator: ", "), homeDirectory: home)
            }
            if !removed.isEmpty {
                try? StorageAuditLog.append(action: "registry.remove", detail: removed.map(\.path).joined(separator: ", "), homeDirectory: home)
            }
        }
        do {
            try ProjectRegistryStore.replace(updated)
        } catch {
            deletionNotice = ProjectDeletionOutcomeLogic.notice(
                .failed("The project list could not be saved: \(error.localizedDescription)")
            )
            return
        }
        loadProjectEntries()
        appState.refreshProjectRegistry()
    }

    private func deleteProject(_ entry: ProjectRegistryEntry) {
        guard !deletionInProgress else { return }
        deletionInProgress = true
        deletionProgress = 0
        deletionProgressLabel = "Preparing deletion…"
        deletionCancelRequested = false
        let cancellation = ProjectDeletionCancellation()
        let progress = ProjectDeletionProgress()
        deletionCancellation = cancellation
        let projectPath = entry.path
        let projectID = entry.id
        let homeDirectory = home

        deletionTask = Task { @MainActor in
            let worker = Task.detached(priority: .utility) {
                Self.executeProjectDeletion(
                    projectPath: projectPath,
                    homeDirectory: homeDirectory,
                    cancellation: cancellation,
                    progress: progress
                )
            }
            while !progress.snapshot.finished {
                self.publishDeletionProgress(progress.snapshot)
                do {
                    try await Task.sleep(nanoseconds: 75_000_000)
                } catch {
                    cancellation.cancel()
                    break
                }
            }
            if Task.isCancelled { cancellation.cancel() }
            let outcome = await worker.value
            self.publishDeletionProgress(progress.snapshot)
            self.finishProjectDeletion(
                projectID: projectID,
                projectPath: projectPath,
                outcome: outcome
            )
        }
    }

    nonisolated private static func executeProjectDeletion(
        projectPath: String,
        homeDirectory: URL,
        cancellation: ProjectDeletionCancellation,
        progress: ProjectDeletionProgress
    ) -> ProjectDeletionOutcomeLogic.Outcome {
        defer { progress.finish() }
        let databaseExists = FileManager.default.fileExists(
            atPath: ProjectDatabaseLocator.databaseURL(projectPath: projectPath).path
        )
        do {
            let backupURL = try ProjectAutoBackupLogic.createBackup(projectPath: projectPath)
            let preservedURL: URL? = backupURL == nil
                ? nil
                : try ProjectAutoBackupLogic.preserveForDeletion(
                    projectPath: projectPath,
                    homeDirectory: homeDirectory
                )
            guard ProjectDeletionBackupPolicy.canProceed(
                databaseExists: databaseExists,
                backupCreated: backupURL != nil,
                backupPreserved: preservedURL != nil
            ) else {
                return .failed("A recovery backup could not be created and preserved.")
            }

            try? StorageAuditLog.append(
                action: "project.delete",
                detail: "path=\(projectPath)",
                homeDirectory: homeDirectory
            )
            return ProjectDeletionExecutor.execute(
                projectPath: projectPath,
                shouldCancel: { cancellation.isCancelled },
                onProgress: { completed, total in
                    progress.update(completed: completed, total: total)
                }
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func publishDeletionProgress(_ snapshot: ProjectDeletionProgress.Snapshot) {
        let fraction = snapshot.total > 0
            ? min(1, max(0, Double(snapshot.completed) / Double(snapshot.total)))
            : 0
        deletionProgress = fraction
        deletionProgressLabel = snapshot.total > 0
            ? "\(snapshot.completed)/\(snapshot.total) items"
            : "Preparing deletion…"
    }

    private func finishProjectDeletion(
        projectID: String,
        projectPath: String,
        outcome: ProjectDeletionOutcomeLogic.Outcome
    ) {
        deletionInProgress = false
        deletionCancellation = nil
        deletionTask = nil
        guard ProjectDeletionOutcomeLogic.shouldRemoveRegistryEntry(outcome) else {
            deletionNotice = ProjectDeletionOutcomeLogic.notice(outcome)
            return
        }

        let before = ProjectRegistryStore.load()
        let updated = ProjectRegistryLogic.remove(id: projectID, in: before)
        do {
            try ProjectRegistryStore.replace(updated)
        } catch {
            deletionNotice = ProjectDeletionOutcomeLogic.notice(
                .failed("Project data was deleted, but the project row could not be removed: \(error.localizedDescription)")
            )
            return
        }
        loadProjectEntries()
        appState.refreshProjectRegistry()

        let selectedPath = appState.selectedWorkspace.map { workspace in
            URL(fileURLWithPath: workspace.path).standardizedFileURL.path
        }
        let deletedPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        if selectedPath == deletedPath {
            appState.clearNavigationHistory()
            appState.selectedWorkspace = nil
        }
        refreshStats()
    }

    private func refreshStats() {
        stats = appState.loadStorageStats()
        loadProjectEntries()
        // Recompute the quota against the 2GB informational threshold (п.50).
        quota = ProjectStorageAdmin.quotaStatus(
            projects: projectEntries,
            thresholdBytes: 2_000_000_000,
            inactiveDays: Int(archiveDays)
        )
    }
}

struct StorageStatView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(title)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
