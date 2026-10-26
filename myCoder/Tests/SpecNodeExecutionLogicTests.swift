import Testing
import Foundation
@testable import myCoder

struct SpecNodeExecutionLogicTests {
    private let now: Int64 = 1_700_000_000

    private func node(
        _ id: String,
        key: String? = nil,
        status: String = "pending",
        order: Int64 = 0,
        criteria: String? = #"["Works"]"#
    ) -> ProjectSpecNode {
        ProjectSpecNode(
            id: id,
            projectID: "p1",
            revisionID: "r1",
            externalKey: key ?? id.uppercased(),
            title: "Task \(id)",
            description: "Implement \(id)",
            kind: "task",
            status: status,
            sortOrder: order,
            acceptanceCriteriaJSON: criteria,
            createdAt: now,
            updatedAt: now
        )
    }

    private func edge(_ from: String,
                      _ to: String,
                      kind: String = "depends_on") -> ProjectSpecEdge {
        ProjectSpecEdge(
            id: "\(from)-\(to)",
            projectID: "p1",
            fromNodeID: from,
            toNodeID: to,
            kind: kind,
            createdAt: now
        )
    }

    @Test("First pending node with satisfied dependencies wins")
    func firstRunnableNode() {
        let nodes = [node("n1"), node("n2")]
        let edges = [edge("n2", "n1")]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges)?.id == "n1")
    }

    @Test("Planner sort order decides between independent nodes")
    func sortOrderWins() {
        let nodes = [node("late", order: 5), node("early", order: 1)]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: [])?.id == "early")
    }

    @Test("A pending dependency blocks the dependent")
    func pendingDependencyBlocks() {
        let nodes = [node("n1"), node("n2", order: 1)]
        let edges = [edge("n2", "n1")]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges)?.id == "n1")
        #expect(!SpecNodeExecutionLogic.canStart(nodeID: "n2", nodes: nodes, edges: edges))
    }

    @Test("A done dependency unlocks the dependent")
    func doneDependencyUnlocks() {
        let nodes = [node("n1", status: "done"), node("n2", order: 1)]
        let edges = [edge("n2", "n1")]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges)?.id == "n2")
    }

    @Test("A skipped dependency unlocks the dependent")
    func skippedDependencyUnlocks() {
        let nodes = [node("n1", status: "skipped"), node("n2", order: 1)]
        let edges = [edge("n2", "n1")]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges)?.id == "n2")
    }

    @Test("Failed or blocked dependencies keep the dependent locked")
    func failedAndBlockedDependenciesLock() {
        for status in ["failed", "blocked"] {
            let nodes = [node("n1", status: status), node("n2", order: 1)]
            let edges = [edge("n2", "n1")]
            #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges) == nil,
                    "\(status) must not satisfy a dependency")
        }
    }

    @Test("One running task hides every other task")
    func runningTaskHidesAll() {
        let nodes = [node("n1", status: "running"), node("n2", order: 1)]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: []) == nil)
    }

    @Test("Failed and skipped nodes are not started automatically")
    func onlyPendingNodesStart() {
        let nodes = [node("n1", status: "failed"), node("n2", status: "skipped")]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: []) == nil)
    }

    @Test("Edges other than depends_on do not gate a task")
    func nonDependencyEdgesIgnored() {
        let nodes = [node("n1", status: "pending"), node("n2", order: 1)]
        let edges = [edge("n1", "n2", kind: "blocks")]
        #expect(SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges)?.id == "n1")
    }

    @Test("Coding prompt carries the task, criteria, spec and project path")
    func codingPromptContents() {
        let task = node("n1", key: "N1", criteria: #"["Build passes","Tests pass"]"#)
        let prompt = SpecNodeExecutionLogic.codingPrompt(
            node: task,
            specification: "# Approved spec\nUse Swift.",
            projectPath: "/tmp/demo"
        )
        #expect(prompt.contains("N1 · Task n1"))
        #expect(prompt.contains("Implement n1"))
        #expect(prompt.contains("- Build passes"))
        #expect(prompt.contains("- Tests pass"))
        #expect(prompt.contains("# Approved spec"))
        #expect(prompt.contains("/tmp/demo"))
        #expect(prompt.contains("Do not claim the task is complete"))
    }

    @Test("Missing criteria and spec are described honestly")
    func codingPromptWithoutCriteria() {
        let task = node("n1", criteria: nil)
        let prompt = SpecNodeExecutionLogic.codingPrompt(
            node: task,
            specification: "   ",
            projectPath: "/tmp/demo"
        )
        #expect(prompt.contains("no acceptance criteria recorded"))
        #expect(prompt.contains("specification text is unavailable"))
    }
}
