import Foundation
import Testing
@testable import myCoder

@Suite("Detailed tool mini guide")
struct ToolInstructionGuideTests {
    @Test func includesEveryExecutableToolContractExactlyOnce() {
        let guide = ToolInstructionGuide.build()
        let headings = guide.components(separatedBy: "\n").filter { $0.hasPrefix("### ") }
        #expect(headings.count == WebEmulatedTool.allCases.count)
        for tool in WebEmulatedTool.allCases {
            #expect(headings.filter { $0 == "### \(tool.rawValue)" }.count == 1)
            #expect(guide.contains(tool.description), "Missing tool purpose: \(tool.rawValue)")
            #expect(guide.contains(tool.argumentSchema), "Missing argument contract: \(tool.rawValue)")
        }
    }

    @Test func teachesInvocationResultsAndRealPermissionBoundary() {
        let guide = ToolInstructionGuide.build()
        #expect(guide.contains("```tool"))
        #expect(guide.contains("\"name\": \"read_file\""))
        #expect(guide.contains("\"args\""))
        #expect(guide.contains("tool_result"))
        #expect(guide.contains("Never report success before"))
        #expect(guide.contains("askBeforeChanges"))
        #expect(guide.contains("fullAccess"))
        #expect(guide.contains("availability"))
        #expect(!guide.contains("every tool is guaranteed"))
    }

    @Test func explainsBrowserFetchParameterInteractions() {
        let guide = ToolInstructionGuide.build()
        #expect(guide.contains("selector and script are mutually exclusive"))
        #expect(guide.contains("click runs before reading"))
        #expect(guide.contains("limit bounds returned text"))
        #expect(guide.contains("ATTACHED_IMAGE:image/png"))
        #expect(guide.contains("http/https"))
    }

    @Test func teachesCanonicalTodoWorkflowForEveryModel() {
        let guide = ToolInstructionGuide.build()
        // Любая модель (web/OpenAI-совместимая) получает не только схемы
        // аргументов, но и порядок работы с планом.
        for name in ["todo_read", "todo_write", "task_create", "task_list", "task_update"] {
            #expect(guide.contains(name), "руководство должно называть \(name)")
        }
        let lower = guide.lowercased()
        #expect(lower.contains("atomic"))
        #expect(lower.contains("in_progress"))
        #expect(lower.contains("completed"))
        #expect(lower.contains("blocked"))
        #expect(lower.contains("before declaring"))
    }

    @Test func teachesExactEditsLineWindowsAndGraphFollowup() {
        let guide = ToolInstructionGuide.build()
        #expect(guide.contains("offset is 1-based"))
        #expect(guide.contains("old must match exactly once"))
        #expect(guide.contains("read_symbol"))
        #expect(guide.contains("id returned by code_search"))
        #expect(guide.contains("heuristic"))
    }
}
