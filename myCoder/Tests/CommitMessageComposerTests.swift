import Testing
@testable import myCoder

@Suite("Commit Message Composer")
struct CommitMessageComposerTests {

    private let sampleDiffStat = """
     myCoder/Sources/Views/RightPanelView.swift | 120 ++++++++++++----
     myCoder/Sources/Services/GitPublishFlowLogic.swift | 80 ++++++++
     myCoder/Tests/GitPublishFlowLogicTests.swift | 60 ++++++
     docs/FEATURE_REGISTRY.md | 4 +-
     4 files changed, 240 insertions(+), 24 deletions(-)
    """

    @Test("Summary lists changed files and totals")
    func summaryListsFilesAndTotals() {
        let summary = CommitMessageComposer.summary(fromDiffStat: sampleDiffStat)
        #expect(summary.contains("RightPanelView.swift"))
        #expect(summary.contains("GitPublishFlowLogic.swift"))
        #expect(summary.contains("+240"))
        #expect(summary.contains("-24"))
    }

    @Test("Summary truncates long file lists")
    func summaryTruncatesLongFileLists() {
        let summary = CommitMessageComposer.summary(fromDiffStat: sampleDiffStat)
        #expect(summary.contains("1 more file"))
        #expect(!summary.contains("FEATURE_REGISTRY.md"))
    }

    @Test("Summary of empty diff is empty")
    func summaryOfEmptyDiffIsEmpty() {
        #expect(CommitMessageComposer.summary(fromDiffStat: "") == "")
        #expect(CommitMessageComposer.summary(fromDiffStat: "   \n ") == "")
    }

    @Test("Compose puts user comment first and summary as body")
    func composeCommentPlusSummary() {
        let message = CommitMessageComposer.compose(userComment: "Fix git panel", diffStat: sampleDiffStat)
        #expect(message.hasPrefix("Fix git panel"))
        #expect(message.contains("\n\n"))
        #expect(message.contains("+240 -24"))
    }

    @Test("Compose with empty comment uses summary as subject")
    func composeEmptyCommentUsesSummary() {
        let message = CommitMessageComposer.compose(userComment: "   ", diffStat: sampleDiffStat)
        #expect(!message.hasPrefix("\n"))
        #expect(message.contains("RightPanelView.swift"))
    }

    @Test("Compose with empty diff uses comment only")
    func composeEmptyDiffUsesCommentOnly() {
        let message = CommitMessageComposer.compose(userComment: "Quick fix", diffStat: "")
        #expect(message == "Quick fix")
    }

    @Test("Compose with everything empty falls back to generic message")
    func composeEverythingEmptyFallsBack() {
        let message = CommitMessageComposer.compose(userComment: "", diffStat: "")
        #expect(message == "Update project files")
    }

    @Test("Compose trims whitespace around the user comment")
    func composeTrimsComment() {
        let message = CommitMessageComposer.compose(userComment: "  Tidy up  ", diffStat: "")
        #expect(message == "Tidy up")
    }

    @Test("Summary from file changes lists names and totals")
    func summaryFromFileChanges() {
        let summary = CommitMessageComposer.summary(
            fileNames: ["A.swift", "B.swift", "C.swift", "D.swift", "E.swift"],
            insertions: 10,
            deletions: 2
        )
        #expect(summary.contains("A.swift, B.swift, C.swift"))
        #expect(summary.contains("2 more files"))
        #expect(summary.contains("(+10 -2)"))
    }

    @Test("Summary from empty file changes is empty")
    func summaryFromEmptyFileChanges() {
        #expect(CommitMessageComposer.summary(fileNames: [], insertions: 5, deletions: 5) == "")
    }

    @Test("Compose with ready-made summary keeps it verbatim as the body")
    func composeWithReadyMadeSummary() {
        let message = CommitMessageComposer.compose(
            userComment: "Polish git panel",
            summary: "Update A.swift (+1 -0)"
        )
        #expect(message == "Polish git panel\n\nUpdate A.swift (+1 -0)")
    }

    @Test("Compose with ready-made summary and empty comment uses summary")
    func composeWithSummaryOnly() {
        let message = CommitMessageComposer.compose(userComment: " ", summary: "Update A.swift (+1 -0)")
        #expect(message == "Update A.swift (+1 -0)")
    }

    @Test("Compose with ready-made summary falls back when both empty")
    func composeWithSummaryFallback() {
        #expect(CommitMessageComposer.compose(userComment: "", summary: "") == "Update project files")
    }
}
