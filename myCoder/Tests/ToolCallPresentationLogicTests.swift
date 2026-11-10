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

    // MARK: - T1: plan tools keep their real name (user directive 2026-11-10)

    @Test("T1: todo_read shows its real name, not 'Reading file'")
    func todoReadKeepsRealName() {
        #expect(
            ToolCallPresentationLogic.title(name: "todo_read", args: "{}")
                == "todo_read · reads checklist + plan"
        )
    }

    @Test("T1: todo_read aliases (todoread/TodoRead/read_todos) show the same real header")
    func todoReadAliasesKeepRealName() {
        for alias in ["todoread", "TodoRead", "read_todos", "todo-read"] {
            #expect(
                ToolCallPresentationLogic.title(name: alias, args: "{}")
                    == "todo_read · reads checklist + plan"
            )
        }
    }

    @Test("T1: task_list shows its real name, not 'Running task'")
    func taskListKeepsRealName() {
        #expect(
            ToolCallPresentationLogic.title(name: "task_list", args: "{}")
                == "task_list · reads the step list"
        )
    }

    @Test("T1: todo_write names the tool and summarizes what it writes on one line")
    func todoWriteSummarizesChecklist() {
        let args = #"{"todos":[{"id":"1","content":"сделать X","status":"pending"},{"id":"2","content":"сделать Y","status":"pending"}]}"#
        #expect(
            ToolCallPresentationLogic.title(name: "todo_write", args: args)
                == "todo_write · writes checklist (2): сделать X"
        )
    }

    @Test("T1: todo_write without parsable items still shows its real name")
    func todoWriteWithoutItems() {
        #expect(
            ToolCallPresentationLogic.title(name: "todo_write", args: "not json")
                == "todo_write · writes the checklist"
        )
    }

    @Test("T1: task_create names the tool and shows the added step")
    func taskCreateShowsAddedStep() {
        #expect(
            ToolCallPresentationLogic.title(name: "task_create", args: #"{"content":"Шаг A","status":"pending"}"#)
                == "task_create · adds step: Шаг A"
        )
    }

    @Test("T1: task_update names the tool and shows step id and new status")
    func taskUpdateShowsStepAndStatus() {
        #expect(
            ToolCallPresentationLogic.title(name: "task_update", args: #"{"id":"3","status":"completed"}"#)
                == "task_update · step 3 → completed"
        )
        #expect(
            ToolCallPresentationLogic.title(name: "task_update", args: #"{"id":"7"}"#)
                == "task_update · step 7"
        )
    }

    @Test("T1: long multiline plan content is truncated to one line")
    func planContentTruncatedToOneLine() {
        let long = String(repeating: "очень длинный текст шага ", count: 20)
        let args = #"{"content":"первая строка\nвторая строка — "# + long + #""}"#
        let title = ToolCallPresentationLogic.title(name: "task_create", args: args)
        #expect(title.hasPrefix("task_create · adds step: первая строка"))
        #expect(!title.contains("\n"))
        #expect(title.hasSuffix("…"))
        #expect(title.count <= ToolCallPresentationLogic.planSummaryMaxWidth + "task_create · adds step: ".count + 1)
    }

    @Test("T1: non-plan tools keep their existing headers")
    func nonPlanToolsUnchanged() {
        #expect(ToolCallPresentationLogic.title(name: "read_file", args: #"{"path":"/a/README.md"}"#) == "Reading README.md")
        #expect(ToolCallPresentationLogic.title(name: "write", args: #"{"path":"/a/main.swift"}"#) == "Writing main.swift")
        #expect(ToolCallPresentationLogic.title(name: "task", args: #"{"description":"✨ Доработать верстку"}"#) == "✨ Доработать верстку")
    }
}
