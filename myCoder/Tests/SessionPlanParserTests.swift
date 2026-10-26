import Testing
import Foundation
@testable import myCoder

@Suite("Session Plan Parser")
struct SessionPlanParserTests {

    @Test("Parses TodoWrite tool invocation into task steps")
    func todoWriteSteps() throws {
        let json = """
        {
            "info": {"role": "assistant", "id": "msg_1"},
            "parts": [
                {
                    "type": "tool-invocation",
                    "toolName": "TodoWrite",
                    "input": "{\\"merge\\":true,\\"todos\\":[{\\"id\\":\\"a\\",\\"content\\":\\"Этап 1: Domain plugins\\",\\"status\\":\\"completed\\"},{\\"id\\":\\"b\\",\\"content\\":\\"Этап 2: API layer\\",\\"status\\":\\"in_progress\\"},{\\"id\\":\\"c\\",\\"content\\":\\"Этап 3: Tests\\",\\"status\\":\\"pending\\"}]}"
                }
            ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoMessageResponse.self, from: json)
        let steps = SessionPlanParser.steps(from: [response])

        #expect(steps.count == 3)
        #expect(steps[0].title == "Этап 1: Domain plugins")
        #expect(steps[0].status == .completed)
        #expect(steps[1].status == .inProgress)
        #expect(steps[2].status == .waiting)
    }

    @Test("Uses latest TodoWrite when multiple exist")
    func latestTodoWriteWins() throws {
        let oldJSON = """
        {"info":{"role":"assistant"},"parts":[{"type":"tool-invocation","toolName":"TodoWrite","input":"{\\"merge\\":false,\\"todos\\":[{\\"id\\":\\"1\\",\\"content\\":\\"Old step\\",\\"status\\":\\"pending\\"}]}"}]}
        """.data(using: .utf8)!
        let newJSON = """
        {"info":{"role":"assistant"},"parts":[{"type":"tool-invocation","toolName":"TodoWrite","input":"{\\"merge\\":true,\\"todos\\":[{\\"id\\":\\"2\\",\\"content\\":\\"New step\\",\\"status\\":\\"in_progress\\"}]}"}]}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(MimoMessageResponse.self, from: oldJSON)
        let new = try JSONDecoder().decode(MimoMessageResponse.self, from: newJSON)
        let steps = SessionPlanParser.steps(from: [old, new])

        #expect(steps.count == 1)
        #expect(steps[0].title == "New step")
        #expect(steps[0].status == .inProgress)
    }

    @Test("Parses markdown checklist from assistant text")
    func markdownChecklist() {
        let text = """
        Plan:
        - [x] Setup project
        - [ ] Write tests
        - [ ] Ship feature
        """
        let steps = SessionPlanParser.steps(fromMarkdown: text)
        #expect(steps.count == 3)
        #expect(steps[0].status == .completed)
        #expect(steps[1].status == .waiting)
    }

    @Test("Falls back to step-start and step-finish markers")
    func stepMarkersFallback() throws {
        let json = """
        {"info":{"role":"assistant"},"parts":[{"type":"step-start"},{"type":"text","text":"Working"},{"type":"step-finish"}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoMessageResponse.self, from: json)
        let steps = SessionPlanParser.steps(from: [response])
        #expect(steps.count == 1)
        #expect(steps[0].status == .completed)
    }

    @Test("TaskProgress reports waiting count")
    func waitingCount() {
        let steps = [
            TaskStep(title: "Done", status: .completed),
            TaskStep(title: "Active", status: .inProgress),
            TaskStep(title: "Wait 1", status: .waiting),
            TaskStep(title: "Wait 2", status: .waiting)
        ]
        let progress = TaskProgress(steps: steps)
        #expect(progress.waitingCount == 2)
        #expect(progress.completedCount == 1)
        #expect(progress.formatted == "1/4")
    }
}

@Suite("Session Context Loader")
struct SessionContextLoaderTests {

    @Test("Git totals prefer VCS files over session summary")
    func gitTotalsFromVCS() {
        let files = [
            MimoVcsFileDiff(path: "a.swift", status: "modified", additions: 10, deletions: 2),
            MimoVcsFileDiff(path: "b.swift", status: "added", additions: 5, deletions: 0)
        ]
        let summary = MimoSessionSummary(additions: 999, deletions: 999, files: 99)
        let totals = SessionContextLoader.gitTotals(vcsFiles: files, sessionSummary: summary)
        #expect(totals.additions == 15)
        #expect(totals.deletions == 2)
    }

    @Test("Git totals fall back to session summary when VCS empty")
    func gitTotalsFallback() {
        let summary = MimoSessionSummary(additions: 736, deletions: 130, files: 12)
        let totals = SessionContextLoader.gitTotals(vcsFiles: [], sessionSummary: summary)
        #expect(totals.additions == 736)
        #expect(totals.deletions == 130)
    }
}
