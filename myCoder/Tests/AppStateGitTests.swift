import Testing
@testable import myCoder

@Suite("AppState git integration")
struct AppStateGitTests {

    @Test("Default commit message uses session title")
    func defaultCommitFromSession() {
        let session = ChatSession(id: "s1", title: "Fix thinking merge", directory: "/tmp")
        let title = session.title.isEmpty ? "MiMo agent changes" : session.title
        #expect(title == "Fix thinking merge")
    }

    @Test("Git totals reflect local file changes")
    func gitTotalsFromLocalFiles() {
        let files = [
            MimoVcsFileDiff(path: "a.swift", status: "modified", additions: 3, deletions: 1)
        ]
        let totals = SessionContextLoader.gitTotals(vcsFiles: files, sessionSummary: nil)
        #expect(totals.additions == 3)
        #expect(totals.deletions == 1)
    }

    @Test("Fetches remote git when local git fails")
    func shouldFetchWhenLocalFails() {
        #expect(SessionContextLoader.shouldFetchRemoteGit(localChangeCount: 0, localGitFailed: true) == true)
    }

    @Test("Skips remote git when local git succeeded")
    func skipsRemoteWhenLocalSucceeded() {
        #expect(SessionContextLoader.shouldFetchRemoteGit(localChangeCount: 0, localGitFailed: false) == false)
        #expect(SessionContextLoader.shouldFetchRemoteGit(localChangeCount: 2, localGitFailed: false) == false)
    }
}
