import Testing
@testable import myCoder

@Suite("Tool call presentation")
struct ToolCallPresentationLogicTests {

    @Test("Parses escaped source content into real lines")
    func parsesEscapedSourceContent() {
        let args = #"{"content":"first line\nsecond line","path":"/tmp/Store.swift"}"#

        let sections = ToolCallPresentationLogic.argumentSections(from: args)

        #expect(sections.first(where: { $0.key == "content" })?.value == "first line\nsecond line")
        #expect(sections.first(where: { $0.key == "path" })?.value == "/tmp/Store.swift")
    }

    @Test("Builds a concise one-line title from tool arguments")
    func buildsConciseTitle() {
        let args = #"{"path":"/Users/test/Sources/Store.swift","content":"final class Store {}"}"#

        #expect(
            ToolCallPresentationLogic.title(name: "write", args: args)
                == "Writing Store.swift"
        )
    }

    @Test("Pretty prints nested JSON argument values")
    func prettyPrintsNestedJSON() {
        let args = #"{"query":{"limit":20,"role":"assistant"}}"#

        let sections = ToolCallPresentationLogic.argumentSections(from: args)

        #expect(sections.first?.value.contains("\"limit\" : 20") == true)
        #expect(sections.first?.value.contains("\"role\" : \"assistant\"") == true)
    }

    @Test("Split inspector summarizes repeated tools as numbered steps")
    func splitInspectorSummary() {
        let steps = [
            ToolCallInspectorStep(id: "1", name: "write", args: #"{"path":"src/userStore.ts"}"#, result: "ok"),
            ToolCallInspectorStep(id: "2", name: "write", args: #"{"path":"src/session.ts"}"#, result: "ok"),
            ToolCallInspectorStep(id: "3", name: "write", args: #"{"path":"src/preferences.ts"}"#, result: "ok"),
        ]

        #expect(ToolCallInspectorLogic.headerTitle(for: steps) == "Writing userStore.ts · 3 steps")
        #expect(ToolCallInspectorLogic.isComplete(steps))
    }

    @Test("Split inspector remains active while any step is unfinished")
    func splitInspectorActiveState() {
        let steps = [
            ToolCallInspectorStep(id: "1", name: "write", args: "{}", result: "ok"),
            ToolCallInspectorStep(id: "2", name: "write", args: "{}", result: nil),
        ]

        #expect(!ToolCallInspectorLogic.isComplete(steps))
    }

    @Test("Single tool call keeps the compact mockup title")
    func splitInspectorSingleStepTitle() {
        let steps = [
            ToolCallInspectorStep(
                id: "1",
                name: "task",
                args: #"{"description":"✨ Доработать верстку"}"#,
                result: "ok"
            ),
        ]

        #expect(ToolCallInspectorLogic.headerTitle(for: steps) == "✨ Доработать верстку")
    }
}
