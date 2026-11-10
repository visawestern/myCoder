import SwiftUI

struct StorageSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State var stats = StorageStats(databaseSize: 0, snapshotSize: 0, messageCount: 0, sessionCountsByProject: [])
    // Round 12: two distinct confirmations — one for "delete older than N days"
    // and one for "delete all archived chats". They used to share the same
    // alert, which crashed / ran the wrong action (P2).
    @State var showDeleteOlderConfirmation = false
    @State var showDeleteArchivedConfirmation = false
    @State var showRemoveOrphansConfirmation = false
    @State var showResetConfirmation = false
    @State var pendingResetScope: StorageResetScope = .appCacheOnly
    @State var archiveDays: Double = 7
    @State var deleteDays: Double = 30
    @State var projectEntries: [ProjectRegistryEntry] = []
    // Delete-project guard (plan Раздел 8 п.24/п.54): destructive action requires
    // typing the project name — GitHub "type repo name to delete" pattern.
    @State var pendingDeleteEntry: ProjectRegistryEntry?
    @State var deleteConfirmName = ""
    // Quota status (plan Раздел 8 п.50): informative warning when the sum of all
    // per-project DBs crosses the threshold — never blocks, always suggests.
    @State var quota = ProjectStorageAdmin.StorageQuotaStatus(
        totalBytes: 0, thresholdBytes: 0, archivableBytes: 0, archivedBytes: 0
    )
    @State var deletionInProgress = false
    @State var deletionProgress = 0.0
    @State var deletionProgressLabel = ""
    @State var deletionCancelRequested = false
    @State var deletionCancellation: ProjectDeletionCancellation?
    @State var deletionTask: Task<Void, Never>?
    @State var deletionNotice: ProjectDeletionOutcomeLogic.Notice?
    @State var pendingAppConfigurationImportURL: URL?
    @State var appConfigurationNotice: AppConfigurationTransferLogic.Notice?
    
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

    var resetAlertTitle: String {
        switch pendingResetScope {
        case .appCacheOnly:
            return AppLocalization.string(.resetAppCacheConfirmTitle, language: appState.appLanguage)
        case .fullDatabase:
            return AppLocalization.string(.resetFullDatabaseConfirmTitle, language: appState.appLanguage)
        }
    }

    var resetAlertMessage: String {
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
    
    var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    var orphanedCount: Int {
        ProjectRegistryLogic.orphaned(projectEntries).count
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
