import SwiftUI

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

