import Foundation

struct SessionGitTotals {
    let additions: Int
    let deletions: Int

    var formatted: String { "+\(additions) -\(deletions)" }
}

enum SessionContextLoader {

    static func gitDirectoryPath(workspacePath: String?, sessionDirectory: String?) -> String? {
        let session = ChatSession.normalizedPath(sessionDirectory ?? "")
        if !session.isEmpty { return session }
        let workspace = ChatSession.normalizedPath(workspacePath ?? "")
        return workspace.isEmpty ? nil : workspace
    }

    static func shouldFetchRemoteGit(localChangeCount: Int, localGitFailed: Bool) -> Bool {
        _ = localChangeCount
        return localGitFailed
    }

    static func gitTotals(vcsFiles: [MimoVcsFileDiff], sessionSummary: MimoSessionSummary?) -> SessionGitTotals {
        let vcsAdd = vcsFiles.reduce(0) { $0 + $1.additions }
        let vcsDel = vcsFiles.reduce(0) { $0 + $1.deletions }

        if vcsAdd > 0 || vcsDel > 0 || !vcsFiles.isEmpty {
            return SessionGitTotals(additions: vcsAdd, deletions: vcsDel)
        }

        if let summary = sessionSummary {
            return SessionGitTotals(additions: summary.additions, deletions: summary.deletions)
        }

        return SessionGitTotals(additions: 0, deletions: 0)
    }
}
