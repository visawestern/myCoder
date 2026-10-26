import Testing
import Foundation
@testable import myCoder

@Suite("Plan ↔ todo bridge (alias of the current plan into todo_read)")
struct PlanTodoBridgeTests {

    private let now: Int64 = 1_700_000_000

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-plantodo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seedPlan(root: URL) throws -> String {
        let manager = try ProjectDatabaseManager.manager(forProjectPath: root.path)
        let store = manager.makeSpecStore()
        let projectID = ProjectIdentityLogic.projectID(for: root.path)
        let revision = try store.appendRevision(
            projectID: projectID, contentMarkdown: "# Spec", summary: nil,
            source: "planner", parentRevisionID: nil, createdAt: now
        )
        let nodes = [
            ProjectSpecNode(
                id: "n1", projectID: projectID, revisionID: revision.id,
                externalKey: "T1", title: "Build index", description: "Index the code",
                kind: "task", status: "done", sortOrder: 0,
                acceptanceCriteriaJSON: #"["Index builds"]"#,
                createdAt: now, updatedAt: now
            ),
            ProjectSpecNode(
                id: "n2", projectID: projectID, revisionID: revision.id,
                externalKey: "T2", title: "Wire assistant", description: "Use the index",
                kind: "task", status: "running", sortOrder: 1,
                acceptanceCriteriaJSON: #"["Assistant answers"]"#,
                createdAt: now, updatedAt: now
            ),
            ProjectSpecNode(
                id: "n3", projectID: projectID, revisionID: revision.id,
                externalKey: "T3", title: "Ship", description: "Release",
                kind: "task", status: "pending", sortOrder: 2,
                acceptanceCriteriaJSON: nil,
                createdAt: now, updatedAt: now
            )
        ]
        let edges = [
            ProjectSpecEdge(
                id: "e1", projectID: projectID, fromNodeID: "n2", toNodeID: "n1",
                kind: "depends_on", createdAt: now
            ),
            ProjectSpecEdge(
                id: "e2", projectID: projectID, fromNodeID: "n3", toNodeID: "n2",
                kind: "depends_on", createdAt: now
            )
        ]
        try store.insertDecomposition(nodes: nodes, edges: edges)
        return projectID
    }

    @Test("Plan status maps onto the todo vocabulary")
    func statusMapping() {
        #expect(PlanTodoBridge.todoStatus(for: "done") == "completed")
        #expect(PlanTodoBridge.todoStatus(for: "running") == "in_progress")
        #expect(PlanTodoBridge.todoStatus(for: "pending") == "pending")
        #expect(PlanTodoBridge.todoStatus(for: "skipped") == "completed")
    }

    @Test("todo status maps onto the plan vocabulary")
    func planStatusMapping() {
        #expect(ProjectWebToolExecutor.planStatus(for: "completed") == "done")
        #expect(ProjectWebToolExecutor.planStatus(for: "in_progress") == "running")
        #expect(ProjectWebToolExecutor.planStatus(for: "pending") == "pending")
    }

    @Test("Merged text shows the plan and the session checklist")
    func mergedText() {
        let plan = [
            PlanTodoItem(id: "T1", title: "Build index", status: "done", todoStatus: "completed",
                         dependsOn: [], acceptanceCriteria: ["Index builds"], isActive: false),
            PlanTodoItem(id: "T2", title: "Wire assistant", status: "running", todoStatus: "in_progress",
                         dependsOn: ["T1"], acceptanceCriteria: [], isActive: true)
        ]
        let todos: [[String: Any]] = [["id": "s1", "content": "Check logs", "status": "pending"]]
        let text = PlanTodoBridge.mergedText(sessionTodos: todos, planItems: plan)
        #expect(text.contains("## Execution plan"))
        #expect(text.contains("## Session checklist"))
        #expect(text.contains("T2: Wire assistant"))
        #expect(text.contains("depends on: T1"))
        #expect(text.contains("active"))
        #expect(text.contains("Check logs"))
    }

    @Test("Merged text is empty when there is neither plan nor checklist")
    func mergedTextEmpty() {
        #expect(PlanTodoBridge.mergedText(sessionTodos: [], planItems: []) == "[]")
    }

    @Test("todo_read exposes the active plan of the project")
    func todoReadShowsPlan() async throws {
        let root = try makeRoot()
        defer { ProjectDatabaseManager.evictProject(projectPath: root.path) }
        _ = try seedPlan(root: root)

        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(result.contains("## Execution plan"), "got: \(result)")
        #expect(result.contains("T1: Build index"), "got: \(result)")
        #expect(result.contains("T2: Wire assistant"), "got: \(result)")
        #expect(result.contains("depends on: T1"), "got: \(result)")
    }

    @Test("todo_read lists the session checklist next to the plan")
    func todoReadShowsChecklist() async throws {
        let root = try makeRoot()
        defer { ProjectDatabaseManager.evictProject(projectPath: root.path) }
        _ = try seedPlan(root: root)

        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        _ = await exec.execute(WebToolCall(name: "todo_write", arguments: [
            "todos": #"[{"id": "s1", "content": "Check logs", "status": "pending"}]"#
        ]))
        let result = await exec.execute(WebToolCall(name: "todo_read", arguments: [:]))
        #expect(result.contains("## Execution plan"), "got: \(result)")
        #expect(result.contains("## Session checklist"), "got: \(result)")
        #expect(result.contains("Check logs"), "got: \(result)")
    }

    @Test("todo_update on a plan id moves the plan task")
    func todoUpdateMovesPlanTask() async throws {
        let root = try makeRoot()
        defer { ProjectDatabaseManager.evictProject(projectPath: root.path) }
        let projectID = try seedPlan(root: root)

        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await exec.execute(WebToolCall(name: "todo_update", arguments: [
            "id": "T3", "status": "completed"
        ]))
        #expect(result.contains("ok"), "got: \(result)")
        #expect(result.contains("T3"), "got: \(result)")

        let store = try ProjectDatabaseManager.manager(forProjectPath: root.path).makeSpecStore()
        let revision = try store.latestRevision(projectID: projectID)
        #expect(revision != nil)
        if let revision {
            let nodes = try store.nodes(revisionID: revision.id)
            #expect(nodes.first(where: { $0.externalKey == "T3" })?.status == "done")
        }
    }

    @Test("todo_update may not start a task out of order")
    func todoUpdateRespectsPlanOrder() async throws {
        let root = try makeRoot()
        defer { ProjectDatabaseManager.evictProject(projectPath: root.path) }
        _ = try seedPlan(root: root)

        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await exec.execute(WebToolCall(name: "todo_update", arguments: [
            "id": "T3", "status": "in_progress"
        ]))
        #expect(result.contains("error"), "got: \(result)")
        #expect(result.contains("not the next runnable task"), "got: \(result)")
    }

    @Test("Todo aliases resolve to the right tools")
    func aliases() {
        #expect(WebToolProtocolEmulator.canonicalToolName("todo_read") == "todo_read")
        #expect(WebToolProtocolEmulator.canonicalToolName("todowrite") == "todo_write")
        #expect(WebToolProtocolEmulator.canonicalToolName("todo_write") == "todo_write")
        #expect(WebToolProtocolEmulator.canonicalToolName("todo_update") == "task_update")
        #expect(WebToolProtocolEmulator.canonicalToolName("todo_edit") == "task_update")
        #expect(WebToolProtocolEmulator.canonicalToolName("todo_add") == "task_create")
        #expect(WebToolProtocolEmulator.canonicalToolName("todo_create") == "task_create")
        #expect(WebToolProtocolEmulator.canonicalToolName("todo_list") == "task_list")
        #expect(WebToolProtocolEmulator.canonicalToolName("plan") == "todo_read")
    }
}
