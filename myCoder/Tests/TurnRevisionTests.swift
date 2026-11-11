import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("Per-turn context revision")
struct TurnRevisionTests {
    @Test func everyPayloadHasSystemThenContextThenRequest() {
        let payload = TurnPresentation.payload(system: "rules", context: "facts", request: "do it")
        #expect(payload == "## Системная инструкция\nrules\n\n## Точечный контекст\nfacts\n\n## Запрос пользователя\ndo it")
    }
    @Test func sendWiringUsesInternalPlannerAndProgress() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("TurnContextPlanningService.plan("))
        #expect(source.contains("contextPreparationStage"))
        #expect(!source.contains("let needsContextPrep = !priorTurnsForContext.isEmpty"))
    }
    @Test func rawSpoilerIsReplaced() throws {
        let source = try RepoRoot.messageRowSourceText
        #expect(!source.contains("RawResponseSpoilerView(rawEvents:"))
        #expect(source.contains("TurnPresentation.rawText("))
        #expect(source.contains("TabView"))
    }
    @Test func rawModeUsesWireEvents() {
        #expect(TurnPresentation.rawText(events: ["{\"delta\":1}", "[DONE]"], fallback: "rendered") == "{\"delta\":1}\n\n[DONE]")
        #expect(TurnPresentation.rawText(events: nil, fallback: "answer") == "answer")
    }
    @Test func contextTabsPreserveSections() {
        let sections = TurnPresentation.sections("## Память проекта\nfact\n\n## Запрос\nquestion")
        #expect(sections.map(\.title) == ["Память проекта", "Запрос"])
        #expect(sections.last?.body == "question")
    }
    @Test func internalPlannerValidatesModelOutput() async {
        let context = LocalPlannerContext(entities: [.init(kind: .file, path: "Real.swift", name: "Real")], memoryTags: [])
        let result = await InternalContextPlanner.plan(message: "fix", context: context) { messages in
            #expect(messages.count == 2)
            return "{\"files\":[\"Real.swift\",\"invented.swift\"]}"
        }
        #expect(result.plan?.files == ["Real.swift"])
        #expect(result.dropped == ["file:invented.swift"])
    }
    @Test func internalFailureIsVisible() async {
        let result = await InternalContextPlanner.plan(message: "fix", context: .init(entities: [], memoryTags: [])) { _ in
            throw InternalModelRunner.NoModelError()
        }
        // The reason is user-facing (Russian UI): it names the setup fact,
        // not a transport error.
        if case .fallback(let reason) = result.status {
            #expect(reason.contains("внутренняя модель") && reason.contains("не назначена"))
        }
        else { Issue.record("Missing internal model must be visible") }
    }
}
