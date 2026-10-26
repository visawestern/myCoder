import Testing
import Foundation
@testable import myCoder

@Suite("Project spec store")
struct ProjectSpecStoreTests {
    private let now: Int64 = 1_700_000_000

    private func withStore(_ body: (ProjectSpecStore) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-spec-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            ProjectDatabaseManager.evictProject(projectPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let manager = try ProjectDatabaseManager.manager(forProjectPath: dir.path)
        try body(manager.makeSpecStore())
    }

    private func settings(projectID: String = "p1") -> ProjectSpecSettings {
        ProjectSpecSettings(
            projectID: projectID,
            plannerProviderID: "anthropic",
            plannerModelID: "planner",
            coderProviderID: "anthropic",
            coderModelID: "coder",
            status: SpecWizardDraft.Status.draft.rawValue,
            currentStep: SpecWizardStep.setup.rawValue,
            briefGoal: "Ship",
            briefStack: "Swift",
            briefConstraints: "Offline",
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
    }

    @Test("Settings round-trip and upsert")
    func settingsRoundTrip() throws {
        try withStore { store in
            var value = settings()
            try store.saveSettings(value)
            #expect(try store.settings(projectID: "p1") == value)

            value.coderModelID = "coder-2"
            value.status = SpecWizardDraft.Status.forced.rawValue
            value.updatedAt = now + 5
            value.completedAt = now + 5
            try store.saveSettings(value)
            #expect(try store.settings(projectID: "p1") == value)
        }
    }

    @Test("Checklist replacement removes stale items and keeps order")
    func checklistReplace() throws {
        try withStore { store in
            let models = ProjectSpecChecklistItem(
                id: "c1", projectID: "p1", itemKey: "models", title: "Models",
                state: "done", detail: nil, sortOrder: 0, updatedAt: now
            )
            let brief = ProjectSpecChecklistItem(
                id: "c2", projectID: "p1", itemKey: "brief", title: "Brief",
                state: "pending", detail: "Need stack", sortOrder: 1, updatedAt: now
            )
            try store.replaceChecklist(projectID: "p1", items: [brief, models])
            #expect(try store.checklist(projectID: "p1").map(\.itemKey) == ["models", "brief"])

            try store.replaceChecklist(projectID: "p1", items: [models])
            #expect(try store.checklist(projectID: "p1").map(\.itemKey) == ["models"])
        }
    }

    @Test("Interview turns get monotonic sequence numbers")
    func turnsSequence() throws {
        try withStore { store in
            let first = try store.appendTurn(
                projectID: "p1", role: "planner", content: "Q1",
                suggestedAnswersJSON: #"["A","B"]"#, createdAt: now
            )
            let second = try store.appendTurn(
                projectID: "p1", role: "user", content: "A",
                suggestedAnswersJSON: nil, createdAt: now + 1
            )
            #expect(first.sequence == 1)
            #expect(second.sequence == 2)

            let turns = try store.turns(projectID: "p1")
            #expect(turns.map(\.role) == ["planner", "user"])
            #expect(turns[0].suggestedAnswersJSON == #"["A","B"]"#)
        }
    }

    @Test("TZ revisions are append-only with monotonic versions")
    func revisionsAppendOnly() throws {
        try withStore { store in
            let first = try store.appendRevision(
                projectID: "p1", contentMarkdown: "# V1", summary: "first",
                source: "planner", parentRevisionID: nil, createdAt: now
            )
            let second = try store.appendRevision(
                projectID: "p1", contentMarkdown: "# V2", summary: "second",
                source: "user", parentRevisionID: first.id, createdAt: now + 1
            )
            #expect(first.version == 1)
            #expect(second.version == 2)
            #expect(try store.latestRevision(projectID: "p1")?.contentMarkdown == "# V2")
            #expect(try store.revisions(projectID: "p1").map(\.contentMarkdown) == ["# V1", "# V2"])
        }
    }

    @Test("Requirements stay attached to their revision")
    func requirementsRoundTrip() throws {
        try withStore { store in
            let revision = try store.appendRevision(
                projectID: "p1", contentMarkdown: "# Spec", summary: nil,
                source: "planner", parentRevisionID: nil, createdAt: now
            )
            let requirements = [
                ProjectSpecRequirement(
                    id: "r1", projectID: "p1", revisionID: revision.id,
                    externalKey: "R1", title: "Offline", description: "Works offline",
                    priority: "must", status: "accepted",
                    acceptanceCriteriaJSON: #"["No network"]"#,
                    createdAt: now, updatedAt: now
                ),
                ProjectSpecRequirement(
                    id: "r2", projectID: "p1", revisionID: revision.id,
                    externalKey: "R2", title: "Fast", description: "Fast launch",
                    priority: "should", status: "accepted",
                    acceptanceCriteriaJSON: #"["<1s"]"#,
                    createdAt: now, updatedAt: now
                )
            ]
            try store.insertRequirements(requirements)
            #expect(try store.requirements(revisionID: revision.id).map(\.externalKey) == ["R1", "R2"])
        }
    }

    @Test("Decomposition round-trips and runs one node at a time")
    func decompositionRunsOneNode() throws {
        try withStore { store in
            let revision = try store.appendRevision(
                projectID: "p1", contentMarkdown: "# Spec", summary: nil,
                source: "planner", parentRevisionID: nil, createdAt: now
            )
            let nodes = [
                ProjectSpecNode(
                    id: "n1", projectID: "p1", revisionID: revision.id,
                    externalKey: "N1", title: "Store", description: "Persist",
                    kind: "task", status: "pending", sortOrder: 0,
                    acceptanceCriteriaJSON: #"["Survives restart"]"#,
                    createdAt: now, updatedAt: now
                ),
                ProjectSpecNode(
                    id: "n2", projectID: "p1", revisionID: revision.id,
                    externalKey: "N2", title: "UI", description: "Render",
                    kind: "task", status: "pending", sortOrder: 1,
                    acceptanceCriteriaJSON: #"["Renders"]"#,
                    createdAt: now, updatedAt: now
                )
            ]
            let edges = [
                ProjectSpecEdge(
                    id: "e1", projectID: "p1", fromNodeID: "n2", toNodeID: "n1",
                    kind: "depends_on", createdAt: now
                )
            ]
            try store.insertDecomposition(nodes: nodes, edges: edges)

            #expect(try store.nodes(revisionID: revision.id).map(\.externalKey) == ["N1", "N2"])
            #expect(try store.decomposition(revisionID: revision.id).nodes[0].acceptanceCriteria == ["Survives restart"])
            #expect(try store.nextRunnableNode(revisionID: revision.id)?.externalKey == "N1")

            try store.updateNodeStatus(nodeID: "n1", status: "done", updatedAt: now + 2)
            #expect(try store.nextRunnableNode(revisionID: revision.id)?.externalKey == "N2")

            try store.updateNodeStatus(nodeID: "n2", status: "done", updatedAt: now + 3)
            #expect(try store.nextRunnableNode(revisionID: revision.id) == nil)
        }
    }

    @Test("History and node sessions persist")
    func historyAndSessions() throws {
        try withStore { store in
            let entry = ProjectSpecHistoryEntry(
                id: "h1", projectID: "p1", entityType: "node", entityID: "n1",
                action: "status_changed", payloadJSON: #"{"to":"done"}"#,
                actor: "user", createdAt: now
            )
            try store.appendHistory(entry)
            #expect(try store.history(projectID: "p1") == [entry])

            let link = ProjectSpecNodeSession(
                id: "s1", projectID: "p1", nodeID: "n1", sessionID: "chat-1",
                state: "active", createdAt: now, updatedAt: now
            )
            try store.linkNodeSession(link)
            #expect(try store.nodeSessions(nodeID: "n1") == [link])
            #expect(try store.updateNodeSessionState(
                nodeID: "n1", sessionID: "chat-1", state: "done", updatedAt: now + 5
            ))
            #expect(try store.nodeSessions(nodeID: "n1").first?.state == "done")
            #expect(try !store.updateNodeSessionState(
                nodeID: "n1", sessionID: "missing", state: "done", updatedAt: now + 5
            ))
        }
    }
}
