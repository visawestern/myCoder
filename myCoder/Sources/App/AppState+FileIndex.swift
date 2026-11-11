import Foundation
import SwiftUI
import AppKit

/// Индекс файлов проекта и поиск по нему.
extension AppState {
    func updateProjectFileIndexWatcher(for workspace: Workspace?) {
        projectFileIndexGeneration &+= 1
        projectFileIndexWatcher?.stop()
        projectFileIndexWatcher = nil
        guard let workspace, !workspace.path.isEmpty else { return }

        let path = workspace.path
        let generation = projectFileIndexGeneration
        let watcher = ProjectFileIndexWatcher(
            projectPath: path,
            generation: generation
        ) { [weak self] eventPath, eventGeneration, changedPaths in
            DispatchQueue.main.async {
                guard let self,
                      ProjectFileIndexWatcherLogic.shouldApply(
                          eventProjectPath: eventPath,
                          activeProjectPath: self.selectedWorkspace?.path ?? "",
                          eventGeneration: eventGeneration,
                          activeGeneration: self.projectFileIndexGeneration
                      ) else { return }
                self.reindexProjectFileChanges(paths: changedPaths, generation: eventGeneration)
            }
        }
        projectFileIndexWatcher = watcher
        watcher.start()

        // Baseline: build the project file index once (and only when it is
        // missing) in the background. Every later change is handled
        // event-by-event by `reindexProjectFileChanges` — no repeated full
        // scans. The scan is bounded (400 MB read, 30k records, 5 MB/file)
        // and skips the generated/media directories in `defaultExcludes`.
        // The serial queue guarantees the baseline lands before any event
        // batch applies on top of it.
        projectIndexUpdateQueue.async {
            _ = PointContextIndexLogic.records(projectPath: path)
        }
    }

    /// Event-driven incremental re-index: FSEvents reported files/directories
    /// that changed; update only those in the stored index and persist the
    /// result. Runs off the main actor (disk I/O + hashing).
    private func reindexProjectFileChanges(paths: [String], generation: UInt64) {
        let path = selectedWorkspace?.path ?? ""
        guard !path.isEmpty, !paths.isEmpty else { return }
        if StreamDiagnostics.isEnabled {
            StreamDiagnostics.log(
                "[REINDEX] start paths=\(paths.joined(separator: ","))",
                file: "/tmp/mycoder_agent.log"
            )
        }
        projectIndexUpdateQueue.async {
            let stored = ProjectFileIndexStore.load(projectPath: path)
            let updated = ProjectFileIndexEventUpdater.apply(
                changedPaths: paths,
                stored: stored,
                projectPath: path
            )
            if updated != stored {
                ProjectFileIndexStore.save(projectPath: path, records: updated)
                if StreamDiagnostics.isEnabled {
                    StreamDiagnostics.log(
                        "[REINDEX] saved stored=\(stored.count) updated=\(updated.count)",
                        file: "/tmp/mycoder_agent.log"
                    )
                }
            } else if StreamDiagnostics.isEnabled {
                StreamDiagnostics.log(
                    "[REINDEX] no-change stored=\(stored.count)",
                    file: "/tmp/mycoder_agent.log"
                )
            }
        }
    }

    @MainActor
    func searchProjectFiles(query: String) -> [FileIndexRecord] {
        let path = selectedWorkspace?.path ?? ""
        guard !path.isEmpty else { return [] }
        // Read the maintained index. Scanning here ran synchronously on the
        // main thread on every search-palette redraw (and rewrote the whole
        // index), freezing the UI on large repos.
        return ProjectFileSearchLogic.search(
            query: query,
            records: ProjectFileIndexStore.load(projectPath: path)
        )
    }

    func inputDropdownContext() -> InputDropdownDataSource.Context {
        let skills = AgentResourcesLoader.loadSkills().map { $0.name }
        let mcpServers = AgentResourcesLoader.loadMCPServers().map { $0.name }
        let sessionTitles = sessions.map { $0.title }
        let path = selectedWorkspace?.path ?? ""
        // Real project files for `@` from the maintained index. The old
        // main-thread scan blocked the dropdown for seconds on a large repo.
        let fileNames = path.isEmpty
            ? []
            : ProjectFileIndexStore.load(projectPath: path).map(\.path)
        return InputDropdownDataSource.Context(
            commands: SlashCommandRegistry.allCommands(),
            installedSkills: skills,
            fileNames: fileNames,
            sessionTitles: sessionTitles,
            mcpServers: mcpServers
        )
    }
}
