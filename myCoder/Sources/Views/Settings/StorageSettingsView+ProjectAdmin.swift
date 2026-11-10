import SwiftUI
import AppKit

extension StorageSettingsView {
    var projectsAdminSection: some View {
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

    func orphanRow(_ entry: ProjectRegistryEntry) -> some View {
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

    func relinkProject(_ entry: ProjectRegistryEntry) {
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

    func projectRow(_ entry: ProjectRegistryEntry, archived: Bool) -> some View {
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

    func exportProjectBackup(_ entry: ProjectRegistryEntry) {
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

    func exportAppConfiguration() {
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

    func importAppConfiguration() {
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

    func performAppConfigurationImport(from url: URL) {
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

    func importProjectBackup(_ entry: ProjectRegistryEntry) {
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

    func loadProjectEntries() {
        projectEntries = ProjectRegistryStore.load()
    }

    func mutateProjects(_ transform: ([ProjectRegistryEntry]) -> [ProjectRegistryEntry]) {
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

    func deleteProject(_ entry: ProjectRegistryEntry) {
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

    func publishDeletionProgress(_ snapshot: ProjectDeletionProgress.Snapshot) {
        let fraction = snapshot.total > 0
            ? min(1, max(0, Double(snapshot.completed) / Double(snapshot.total)))
            : 0
        deletionProgress = fraction
        deletionProgressLabel = snapshot.total > 0
            ? "\(snapshot.completed)/\(snapshot.total) items"
            : "Preparing deletion…"
    }

    func finishProjectDeletion(
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

    func refreshStats() {
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
