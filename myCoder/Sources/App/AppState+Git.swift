import Foundation
import SwiftUI
import AppKit

/// Обновление Git, коммиты, push и запросы на слияние.
extension AppState {
    func scheduleGitRefresh(sessionID explicitSessionID: String? = nil) {
        Task { [weak self] in
            guard let self else { return }
            let sessionID = await MainActor.run {
                GitRefreshScheduler.resolvedSessionID(
                    explicit: explicitSessionID,
                    selected: self.selectedSession?.id
                )
            }
            if let sessionID {
                await self.loadSessionContext(sessionID: sessionID)
            } else {
                _ = await self.refreshGitFromLocal()
            }
        }
    }

    struct GitRefreshResult {
        let changeCount: Int
        let failed: Bool
    }

    @discardableResult
    func refreshGitFromLocal(directory: String? = nil) async -> GitRefreshResult {
        let key = directory ?? "__default__"
        return await gitRefreshCoalescer.run(key: key) {
            await self.performRefreshGitFromLocal(directory: directory)
        }
    }

    private func performRefreshGitFromLocal(directory: String?) async -> GitRefreshResult {
        let resolvedDirectory = await MainActor.run { () -> String? in
            if let directory {
                return directory
            }
            return SessionContextLoader.gitDirectoryPath(
                workspacePath: self.selectedWorkspace?.path,
                sessionDirectory: self.selectedSession?.directory
            )
        }

        guard let workspacePath = resolvedDirectory else {
            await MainActor.run {
                gitRepositoryPath = nil
            }
            return GitRefreshResult(changeCount: 0, failed: true)
        }

        await beginGitBusy()
        defer { Task { await self.endGitBusy() } }

        let snapshot = await Task.detached(priority: .utility) { () -> (result: GitRefreshResult, payload: GitRefreshPayload?) in
            do {
                let root = try GitRepository.repositoryRoot(for: workspacePath)
                let branch = GitRepository.currentBranch(in: root)
                let branches = try GitRepository.branches(in: root)
                let localChanges = try GitRepository.workingTreeChanges(in: root)
                let vcs = GitRepository.toVcsFileDiffs(localChanges)
                return (
                    GitRefreshResult(changeCount: vcs.count, failed: false),
                    GitRefreshPayload(
                        root: root,
                        branch: branch,
                        branches: branches,
                        vcs: vcs,
                        errorMessage: nil
                    )
                )
            } catch {
                return (
                    GitRefreshResult(changeCount: 0, failed: true),
                    GitRefreshPayload(
                        root: nil,
                        branch: nil,
                        branches: nil,
                        vcs: nil,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }.value

        await MainActor.run {
            if let payload = snapshot.payload, let root = payload.root, let branch = payload.branch,
               let branches = payload.branches, let vcs = payload.vcs {
                self.gitRepositoryPath = root
                self.gitBranch = branch
                self.gitBranches = branches
                self.vcsChanges = vcs
                self.sessionGitTotals = SessionContextLoader.gitTotals(vcsFiles: vcs, sessionSummary: nil)
                self.gitStatusMessage = nil
                self.updateWorkspaceBranch(branch)
            } else if let message = snapshot.payload?.errorMessage {
                self.gitStatusMessage = message
            }
        }

        return snapshot.result
    }

    private struct GitRefreshPayload {
        let root: String?
        let branch: String?
        let branches: [String]?
        let vcs: [MimoVcsFileDiff]?
        let errorMessage: String?
    }

    private func beginGitBusy() async {
        await MainActor.run {
            gitBusyCount += 1
            isGitBusy = true
        }
    }

    private func endGitBusy() async {
        await MainActor.run {
            gitBusyCount = max(0, gitBusyCount - 1)
            isGitBusy = gitBusyCount > 0
        }
    }

    @discardableResult
    func commitGitChanges(message: String) async -> Bool {
        guard let repoPath = gitRepositoryPath ?? selectedWorkspace.flatMap({ try? GitRepository.repositoryRoot(for: $0.path) }) else {
            await MainActor.run { gitStatusMessage = "No git repository for this workspace" }
            return false
        }

        await beginGitBusy()
        await MainActor.run { gitStatusMessage = nil }
        defer { Task { await self.endGitBusy() } }

        do {
            let result = try await Task.detached(priority: .utility) {
                try GitRepository.commitAll(in: repoPath, message: message)
            }.value
            await MainActor.run {
                gitStatusMessage = result.output.isEmpty ? "Committed successfully" : result.output
                notificationService.gitOperationComplete(operation: "Commit", details: message.prefix(80).description)
            }
            await refreshGitFromLocal()
            return true
        } catch {
            await MainActor.run {
                gitStatusMessage = error.localizedDescription
            }
            return false
        }
    }

    func pushGitChanges() async {
        guard let repoPath = gitRepositoryPath else {
            await MainActor.run { gitStatusMessage = "No git repository for this workspace" }
            return
        }

        await beginGitBusy()
        await MainActor.run { gitStatusMessage = nil }
        defer { Task { await self.endGitBusy() } }

        do {
            let result = try await Task.detached(priority: .utility) {
                try GitRepository.push(in: repoPath)
            }.value
            await MainActor.run {
                gitStatusMessage = result.output.isEmpty ? "Pushed successfully" : result.output
                notificationService.gitOperationComplete(operation: "Push", details: result.output.isEmpty ? "Changes pushed to remote" : result.output)
            }
        } catch {
            await MainActor.run {
                gitStatusMessage = error.localizedDescription
            }
        }
    }

    func checkoutGitBranch(_ branch: String) async {
        guard let repoPath = gitRepositoryPath else { return }

        await beginGitBusy()
        defer { Task { await self.endGitBusy() } }

        do {
            _ = try await Task.detached(priority: .utility) {
                try GitRepository.checkout(branch: branch, in: repoPath)
            }.value
            await refreshGitFromLocal()
            await MainActor.run {
                gitStatusMessage = "Switched to \(branch)"
            }
        } catch {
            await MainActor.run {
                gitStatusMessage = error.localizedDescription
            }
        }
    }

    /// Publishes the current workspace as a new GitHub repository via `gh`
    /// (shared by the publish wizard and the `/pr` slash command — E08).
    func publishWorkspaceToGitHub(ghPath: String, repoName: String, isPublic: Bool) async {
        guard let path = selectedWorkspace?.path else { return }
        guard GitPublishFlowLogic.isValidRepoName(repoName) else { return }

        await MainActor.run {
            isGitBusy = true
            gitStatusMessage = "Publishing to GitHub..."
        }

        do {
            let output = try await GitHubCLIService.createRepository(
                ghPath: ghPath,
                repoName: repoName,
                isPublic: isPublic,
                workspacePath: path
            )
            await MainActor.run {
                isGitBusy = false
                gitStatusMessage = output.isEmpty ? "Published to GitHub successfully!" : output
            }
            await refreshGitFromLocal()
        } catch {
            await MainActor.run {
                isGitBusy = false
                gitStatusMessage = "Failed to publish: \(error.localizedDescription)"
            }
        }
    }

    /// Creates a pull request for the current branch via `gh pr create`
    /// (Раздел 5 п.16 — real action for `/pr`).
    @discardableResult
    func createGitHubPullRequest(title: String, body: String) async -> Bool {
        guard let path = selectedWorkspace?.path,
              let ghPath = GitPublishFlowLogic.ghExecutablePath() else {
            await MainActor.run { gitStatusMessage = "GitHub CLI is not available — use the publish wizard." }
            return false
        }

        await MainActor.run {
            isGitBusy = true
            gitStatusMessage = "Creating pull request..."
        }
        defer { Task { await self.endGitBusy() } }

        do {
            let output = try await GitHubCLIService.createPullRequest(
                ghPath: ghPath,
                title: title,
                body: body,
                workspacePath: path
            )
            await MainActor.run {
                gitStatusMessage = output.isEmpty ? "Pull request created" : output
                notificationService.gitOperationComplete(operation: "PR", details: title)
            }
            return true
        } catch {
            await MainActor.run {
                gitStatusMessage = "Failed to create PR: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func updateWorkspaceBranch(_ branch: String) {
        guard var workspace = selectedWorkspace else { return }
        workspace.branch = branch
        selectedWorkspace = workspace
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index].branch = branch
        }
        if var session = selectedSession {
            session.branch = branch
            selectedSession = session
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index].branch = branch
            }
        }
    }
}
