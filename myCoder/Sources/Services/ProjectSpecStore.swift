import Foundation
import SQLite

// MARK: - Records

struct ProjectSpecSettings: Equatable {
    let projectID: String
    var plannerProviderID: String?
    var plannerModelID: String?
    var coderProviderID: String?
    var coderModelID: String?
    var status: String
    var currentStep: String
    var briefGoal: String?
    var briefStack: String?
    var briefConstraints: String?
    var createdAt: Int64
    var updatedAt: Int64
    var completedAt: Int64?
}

struct ProjectSpecChecklistItem: Equatable {
    let id: String
    let projectID: String
    let itemKey: String
    let title: String
    var state: String
    var detail: String?
    let sortOrder: Int64
    var updatedAt: Int64
}

struct ProjectSpecTurn: Equatable {
    let id: String
    let projectID: String
    let role: String
    let content: String
    let suggestedAnswersJSON: String?
    let sequence: Int64
    let createdAt: Int64
}

struct ProjectSpecRevision: Equatable {
    let id: String
    let projectID: String
    let version: Int64
    let contentMarkdown: String
    let summary: String?
    let source: String
    let parentRevisionID: String?
    let createdAt: Int64
}

struct ProjectSpecRequirement: Equatable {
    let id: String
    let projectID: String
    let revisionID: String
    let externalKey: String
    let title: String
    let description: String
    let priority: String
    var status: String
    let acceptanceCriteriaJSON: String?
    let createdAt: Int64
    var updatedAt: Int64
}

struct ProjectSpecNode: Equatable {
    let id: String
    let projectID: String
    let revisionID: String
    let externalKey: String
    let title: String
    let description: String
    let kind: String
    var status: String
    let sortOrder: Int64
    let acceptanceCriteriaJSON: String?
    let createdAt: Int64
    var updatedAt: Int64
}

struct ProjectSpecEdge: Equatable {
    let id: String
    let projectID: String
    let fromNodeID: String
    let toNodeID: String
    let kind: String
    let createdAt: Int64
}

struct ProjectSpecHistoryEntry: Equatable {
    let id: String
    let projectID: String
    let entityType: String
    let entityID: String
    let action: String
    let payloadJSON: String?
    let actor: String
    let createdAt: Int64
}

struct ProjectSpecNodeSession: Equatable {
    let id: String
    let projectID: String
    let nodeID: String
    let sessionID: String
    var state: String
    let createdAt: Int64
    var updatedAt: Int64
}

enum ProjectSpecStoreError: Error, Equatable, LocalizedError {
    case unknownNode(String)

    var errorDescription: String? {
        switch self {
        case .unknownNode(let id):
            return "Decomposition edge references unknown node \(id)"
        }
    }
}

// MARK: - Store

private let specSettings = Table("project_spec_settings")
private let ssProjectID = Expression<String>("project_id")
private let ssPlannerProviderID = Expression<String?>("planner_provider_id")
private let ssPlannerModelID = Expression<String?>("planner_model_id")
private let ssCoderProviderID = Expression<String?>("coder_provider_id")
private let ssCoderModelID = Expression<String?>("coder_model_id")
private let ssStatus = Expression<String>("status")
private let ssCurrentStep = Expression<String>("current_step")
private let ssBriefGoal = Expression<String?>("brief_goal")
private let ssBriefStack = Expression<String?>("brief_stack")
private let ssBriefConstraints = Expression<String?>("brief_constraints")
private let ssCreatedAt = Expression<Int64>("created_at")
private let ssUpdatedAt = Expression<Int64>("updated_at")
private let ssCompletedAt = Expression<Int64?>("completed_at")

private let specChecklist = Table("spec_checklist_items")
private let ciID = Expression<String>("id")
private let ciProjectID = Expression<String>("project_id")
private let ciItemKey = Expression<String>("item_key")
private let ciTitle = Expression<String>("title")
private let ciState = Expression<String>("state")
private let ciDetail = Expression<String?>("detail")
private let ciSortOrder = Expression<Int64>("sort_order")
private let ciUpdatedAt = Expression<Int64>("updated_at")

private let specTurns = Table("spec_wizard_turns")
private let stID = Expression<String>("id")
private let stProjectID = Expression<String>("project_id")
private let stRole = Expression<String>("role")
private let stContent = Expression<String>("content")
private let stSuggestedAnswers = Expression<String?>("suggested_answers")
private let stSequence = Expression<Int64>("sequence")
private let stCreatedAt = Expression<Int64>("created_at")

private let specRevisions = Table("spec_tz_revisions")
private let srID = Expression<String>("id")
private let srProjectID = Expression<String>("project_id")
private let srVersion = Expression<Int64>("version")
private let srContentMarkdown = Expression<String>("content_markdown")
private let srSummary = Expression<String?>("summary")
private let srSource = Expression<String>("source")
private let srParentRevisionID = Expression<String?>("parent_revision_id")
private let srCreatedAt = Expression<Int64>("created_at")

private let specRequirements = Table("spec_requirements")
private let sreqID = Expression<String>("id")
private let sreqProjectID = Expression<String>("project_id")
private let sreqRevisionID = Expression<String>("revision_id")
private let sreqExternalKey = Expression<String>("external_key")
private let sreqTitle = Expression<String>("title")
private let sreqDescription = Expression<String>("description")
private let sreqPriority = Expression<String>("priority")
private let sreqStatus = Expression<String>("status")
private let sreqAcceptance = Expression<String?>("acceptance_criteria")
private let sreqCreatedAt = Expression<Int64>("created_at")
private let sreqUpdatedAt = Expression<Int64>("updated_at")

private let specNodes = Table("spec_nodes")
private let snID = Expression<String>("id")
private let snProjectID = Expression<String>("project_id")
private let snRevisionID = Expression<String>("revision_id")
private let snExternalKey = Expression<String>("external_key")
private let snTitle = Expression<String>("title")
private let snDescription = Expression<String>("description")
private let snKind = Expression<String>("kind")
private let snStatus = Expression<String>("status")
private let snSortOrder = Expression<Int64>("sort_order")
private let snAcceptance = Expression<String?>("acceptance_criteria")
private let snCreatedAt = Expression<Int64>("created_at")
private let snUpdatedAt = Expression<Int64>("updated_at")

private let specEdges = Table("spec_edges")
private let seID = Expression<String>("id")
private let seProjectID = Expression<String>("project_id")
private let seFromNodeID = Expression<String>("from_node_id")
private let seToNodeID = Expression<String>("to_node_id")
private let seKind = Expression<String>("kind")
private let seCreatedAt = Expression<Int64>("created_at")

private let specHistory = Table("spec_history")
private let shID = Expression<String>("id")
private let shProjectID = Expression<String>("project_id")
private let shEntityType = Expression<String>("entity_type")
private let shEntityID = Expression<String>("entity_id")
private let shAction = Expression<String>("action")
private let shPayload = Expression<String?>("payload")
private let shActor = Expression<String>("actor")
private let shCreatedAt = Expression<Int64>("created_at")

private let specNodeSessions = Table("spec_node_sessions")
private let snsID = Expression<String>("id")
private let snsProjectID = Expression<String>("project_id")
private let snsNodeID = Expression<String>("node_id")
private let snsSessionID = Expression<String>("session_id")
private let snsState = Expression<String>("state")
private let snsCreatedAt = Expression<Int64>("created_at")
private let snsUpdatedAt = Expression<Int64>("updated_at")

/// CRUD boundary for the spec wizard tables. The store never updates a TZ
/// revision or deletes history: those are append-only by contract. The only
/// mutable rows are node status, checklist snapshots and session links.
final class ProjectSpecStore {
    private let db: Connection

    init(db: Connection) {
        self.db = db
    }

    // MARK: Settings

    func saveSettings(_ value: ProjectSpecSettings) throws {
        try db.run(specSettings.insert(or: .replace,
            ssProjectID <- value.projectID,
            ssPlannerProviderID <- value.plannerProviderID,
            ssPlannerModelID <- value.plannerModelID,
            ssCoderProviderID <- value.coderProviderID,
            ssCoderModelID <- value.coderModelID,
            ssStatus <- value.status,
            ssCurrentStep <- value.currentStep,
            ssBriefGoal <- value.briefGoal,
            ssBriefStack <- value.briefStack,
            ssBriefConstraints <- value.briefConstraints,
            ssCreatedAt <- value.createdAt,
            ssUpdatedAt <- value.updatedAt,
            ssCompletedAt <- value.completedAt
        ))
    }

    func settings(projectID: String) throws -> ProjectSpecSettings? {
        guard let row = try db.pluck(specSettings.filter(ssProjectID == projectID)) else {
            return nil
        }
        return ProjectSpecSettings(
            projectID: row[ssProjectID],
            plannerProviderID: row[ssPlannerProviderID],
            plannerModelID: row[ssPlannerModelID],
            coderProviderID: row[ssCoderProviderID],
            coderModelID: row[ssCoderModelID],
            status: row[ssStatus],
            currentStep: row[ssCurrentStep],
            briefGoal: row[ssBriefGoal],
            briefStack: row[ssBriefStack],
            briefConstraints: row[ssBriefConstraints],
            createdAt: row[ssCreatedAt],
            updatedAt: row[ssUpdatedAt],
            completedAt: row[ssCompletedAt]
        )
    }

    // MARK: Checklist

    func replaceChecklist(projectID: String, items: [ProjectSpecChecklistItem]) throws {
        try db.transaction {
            try db.run(specChecklist.filter(ciProjectID == projectID).delete())
            for item in items {
                try db.run(specChecklist.insert(
                    ciID <- item.id,
                    ciProjectID <- item.projectID,
                    ciItemKey <- item.itemKey,
                    ciTitle <- item.title,
                    ciState <- item.state,
                    ciDetail <- item.detail,
                    ciSortOrder <- item.sortOrder,
                    ciUpdatedAt <- item.updatedAt
                ))
            }
        }
    }

    func checklist(projectID: String) throws -> [ProjectSpecChecklistItem] {
        let query = specChecklist
            .filter(ciProjectID == projectID)
            .order(ciSortOrder, ciItemKey)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectSpecChecklistItem(
                id: row[ciID],
                projectID: row[ciProjectID],
                itemKey: row[ciItemKey],
                title: row[ciTitle],
                state: row[ciState],
                detail: row[ciDetail],
                sortOrder: row[ciSortOrder],
                updatedAt: row[ciUpdatedAt]
            )
        }
    }

    // MARK: Interview turns

    @discardableResult
    func appendTurn(projectID: String,
                    role: String,
                    content: String,
                    suggestedAnswersJSON: String?,
                    createdAt: Int64) throws -> ProjectSpecTurn {
        let maxSequence: Int64 = try db.scalar(
            specTurns.filter(stProjectID == projectID).select(stSequence.max)
        ) ?? 0
        let turn = ProjectSpecTurn(
            id: UUID().uuidString,
            projectID: projectID,
            role: role,
            content: content,
            suggestedAnswersJSON: suggestedAnswersJSON,
            sequence: maxSequence + 1,
            createdAt: createdAt
        )
        try db.run(specTurns.insert(
            stID <- turn.id,
            stProjectID <- turn.projectID,
            stRole <- turn.role,
            stContent <- turn.content,
            stSuggestedAnswers <- turn.suggestedAnswersJSON,
            stSequence <- turn.sequence,
            stCreatedAt <- turn.createdAt
        ))
        return turn
    }

    func turns(projectID: String) throws -> [ProjectSpecTurn] {
        let query = specTurns
            .filter(stProjectID == projectID)
            .order(stSequence)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectSpecTurn(
                id: row[stID],
                projectID: row[stProjectID],
                role: row[stRole],
                content: row[stContent],
                suggestedAnswersJSON: row[stSuggestedAnswers],
                sequence: row[stSequence],
                createdAt: row[stCreatedAt]
            )
        }
    }

    // MARK: TZ revisions

    /// Appends a new immutable revision. Version numbers are assigned by the
    /// store, never by the caller, so two planner answers cannot reuse one.
    @discardableResult
    func appendRevision(projectID: String,
                        contentMarkdown: String,
                        summary: String?,
                        source: String,
                        parentRevisionID: String?,
                        createdAt: Int64) throws -> ProjectSpecRevision {
        let maxVersion: Int64 = try db.scalar(
            specRevisions.filter(srProjectID == projectID).select(srVersion.max)
        ) ?? 0
        let revision = ProjectSpecRevision(
            id: UUID().uuidString,
            projectID: projectID,
            version: maxVersion + 1,
            contentMarkdown: contentMarkdown,
            summary: summary,
            source: source,
            parentRevisionID: parentRevisionID,
            createdAt: createdAt
        )
        try db.run(specRevisions.insert(
            srID <- revision.id,
            srProjectID <- revision.projectID,
            srVersion <- revision.version,
            srContentMarkdown <- revision.contentMarkdown,
            srSummary <- revision.summary,
            srSource <- revision.source,
            srParentRevisionID <- revision.parentRevisionID,
            srCreatedAt <- revision.createdAt
        ))
        return revision
    }

    func revisions(projectID: String) throws -> [ProjectSpecRevision] {
        let query = specRevisions
            .filter(srProjectID == projectID)
            .order(srVersion)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectSpecRevision(
                id: row[srID],
                projectID: row[srProjectID],
                version: row[srVersion],
                contentMarkdown: row[srContentMarkdown],
                summary: row[srSummary],
                source: row[srSource],
                parentRevisionID: row[srParentRevisionID],
                createdAt: row[srCreatedAt]
            )
        }
    }

    func latestRevision(projectID: String) throws -> ProjectSpecRevision? {
        try revisions(projectID: projectID).last
    }

    // MARK: Requirements

    func insertRequirements(_ requirements: [ProjectSpecRequirement]) throws {
        try db.transaction {
            for requirement in requirements {
                try db.run(specRequirements.insert(
                    sreqID <- requirement.id,
                    sreqProjectID <- requirement.projectID,
                    sreqRevisionID <- requirement.revisionID,
                    sreqExternalKey <- requirement.externalKey,
                    sreqTitle <- requirement.title,
                    sreqDescription <- requirement.description,
                    sreqPriority <- requirement.priority,
                    sreqStatus <- requirement.status,
                    sreqAcceptance <- requirement.acceptanceCriteriaJSON,
                    sreqCreatedAt <- requirement.createdAt,
                    sreqUpdatedAt <- requirement.updatedAt
                ))
            }
        }
    }

    func requirements(revisionID: String) throws -> [ProjectSpecRequirement] {
        let query = specRequirements
            .filter(sreqRevisionID == revisionID)
            .order(sreqExternalKey)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectSpecRequirement(
                id: row[sreqID],
                projectID: row[sreqProjectID],
                revisionID: row[sreqRevisionID],
                externalKey: row[sreqExternalKey],
                title: row[sreqTitle],
                description: row[sreqDescription],
                priority: row[sreqPriority],
                status: row[sreqStatus],
                acceptanceCriteriaJSON: row[sreqAcceptance],
                createdAt: row[sreqCreatedAt],
                updatedAt: row[sreqUpdatedAt]
            )
        }
    }

    // MARK: Decomposition

    func insertDecomposition(nodes: [ProjectSpecNode], edges: [ProjectSpecEdge]) throws {
        let nodeIDs = Set(nodes.map(\.id))
        for edge in edges {
            guard nodeIDs.contains(edge.fromNodeID) else {
                throw ProjectSpecStoreError.unknownNode(edge.fromNodeID)
            }
            guard nodeIDs.contains(edge.toNodeID) else {
                throw ProjectSpecStoreError.unknownNode(edge.toNodeID)
            }
        }
        try db.transaction {
            for node in nodes {
                try db.run(specNodes.insert(
                    snID <- node.id,
                    snProjectID <- node.projectID,
                    snRevisionID <- node.revisionID,
                    snExternalKey <- node.externalKey,
                    snTitle <- node.title,
                    snDescription <- node.description,
                    snKind <- node.kind,
                    snStatus <- node.status,
                    snSortOrder <- node.sortOrder,
                    snAcceptance <- node.acceptanceCriteriaJSON,
                    snCreatedAt <- node.createdAt,
                    snUpdatedAt <- node.updatedAt
                ))
            }
            for edge in edges {
                try db.run(specEdges.insert(
                    seID <- edge.id,
                    seProjectID <- edge.projectID,
                    seFromNodeID <- edge.fromNodeID,
                    seToNodeID <- edge.toNodeID,
                    seKind <- edge.kind,
                    seCreatedAt <- edge.createdAt
                ))
            }
        }
    }

    func nodes(revisionID: String) throws -> [ProjectSpecNode] {
        let query = specNodes
            .filter(snRevisionID == revisionID)
            .order(snSortOrder, snExternalKey)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectSpecNode(
                id: row[snID],
                projectID: row[snProjectID],
                revisionID: row[snRevisionID],
                externalKey: row[snExternalKey],
                title: row[snTitle],
                description: row[snDescription],
                kind: row[snKind],
                status: row[snStatus],
                sortOrder: row[snSortOrder],
                acceptanceCriteriaJSON: row[snAcceptance],
                createdAt: row[snCreatedAt],
                updatedAt: row[snUpdatedAt]
            )
        }
    }

    func edges(revisionID: String) throws -> [ProjectSpecEdge] {
        let nodes = try nodes(revisionID: revisionID)
        guard let projectID = nodes.first?.projectID else { return [] }
        let nodeIDs = Set(nodes.map(\.id))
        let query = specEdges
            .filter(seProjectID == projectID)
            .order(seCreatedAt, seID)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query))
            .map { row in
                ProjectSpecEdge(
                    id: row[seID],
                    projectID: row[seProjectID],
                    fromNodeID: row[seFromNodeID],
                    toNodeID: row[seToNodeID],
                    kind: row[seKind],
                    createdAt: row[seCreatedAt]
                )
            }
            .filter { nodeIDs.contains($0.fromNodeID) && nodeIDs.contains($0.toNodeID) }
    }

    /// Rebuilds the pure-logic view of a revision, including dependencies from
    /// the edge table.
    func decomposition(revisionID: String) throws -> SpecDecomposition {
        let nodes = try nodes(revisionID: revisionID)
        guard !nodes.isEmpty else { return SpecDecomposition(nodes: []) }

        let keyByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.externalKey) })
        var dependencies: [String: [String]] = [:]
        for edge in try edges(revisionID: revisionID) where edge.kind == "depends_on" {
            guard let from = keyByID[edge.fromNodeID],
                  let to = keyByID[edge.toNodeID] else { continue }
            dependencies[from, default: []].append(to)
        }

        let mapped = nodes.map { node in
            SpecDecompositionNode(
                key: node.externalKey,
                title: node.title,
                description: node.description,
                kind: node.kind,
                acceptanceCriteria: Self.decodeStringArray(node.acceptanceCriteriaJSON),
                dependsOn: dependencies[node.externalKey, default: []],
                order: Int(node.sortOrder)
            )
        }
        return SpecDecomposition(nodes: mapped)
    }

    private static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    /// One node at a time: the first pending node whose dependencies are done
    /// or deliberately skipped. A running node hides the rest.
    func nextRunnableNode(revisionID: String) throws -> ProjectSpecNode? {
        let nodes = try nodes(revisionID: revisionID)
        guard !nodes.isEmpty else { return nil }
        let edges = try edges(revisionID: revisionID)
        return SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges)
    }

    @discardableResult
    func updateNodeStatus(nodeID: String, status: String, updatedAt: Int64) throws -> Bool {
        let changes = try db.run(
            specNodes.filter(snID == nodeID).update(
                snStatus <- status,
                snUpdatedAt <- updatedAt
            )
        )
        return changes > 0
    }

    // MARK: History and node sessions

    func appendHistory(_ entry: ProjectSpecHistoryEntry) throws {
        try db.run(specHistory.insert(
            shID <- entry.id,
            shProjectID <- entry.projectID,
            shEntityType <- entry.entityType,
            shEntityID <- entry.entityID,
            shAction <- entry.action,
            shPayload <- entry.payloadJSON,
            shActor <- entry.actor,
            shCreatedAt <- entry.createdAt
        ))
    }

    func history(projectID: String) throws -> [ProjectSpecHistoryEntry] {
        let query = specHistory
            .filter(shProjectID == projectID)
            .order(shCreatedAt, shID)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectSpecHistoryEntry(
                id: row[shID],
                projectID: row[shProjectID],
                entityType: row[shEntityType],
                entityID: row[shEntityID],
                action: row[shAction],
                payloadJSON: row[shPayload],
                actor: row[shActor],
                createdAt: row[shCreatedAt]
            )
        }
    }

    func linkNodeSession(_ link: ProjectSpecNodeSession) throws {
        if let existing = try db.pluck(
            specNodeSessions.filter(snsNodeID == link.nodeID && snsSessionID == link.sessionID)
        ) {
            try db.run(specNodeSessions.filter(snsID == existing[snsID]).update(
                snsState <- link.state,
                snsUpdatedAt <- link.updatedAt
            ))
        } else {
            try db.run(specNodeSessions.insert(
                snsID <- link.id,
                snsProjectID <- link.projectID,
                snsNodeID <- link.nodeID,
                snsSessionID <- link.sessionID,
                snsState <- link.state,
                snsCreatedAt <- link.createdAt,
                snsUpdatedAt <- link.updatedAt
            ))
        }
    }

    @discardableResult
    func updateNodeSessionState(nodeID: String,
                                sessionID: String,
                                state: String,
                                updatedAt: Int64) throws -> Bool {
        let changes = try db.run(
            specNodeSessions
                .filter(snsNodeID == nodeID && snsSessionID == sessionID)
                .update(snsState <- state, snsUpdatedAt <- updatedAt)
        )
        return changes > 0
    }

    func nodeSessions(nodeID: String) throws -> [ProjectSpecNodeSession] {
        let query = specNodeSessions
            .filter(snsNodeID == nodeID)
            .order(snsCreatedAt, snsID)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectSpecNodeSession(
                id: row[snsID],
                projectID: row[snsProjectID],
                nodeID: row[snsNodeID],
                sessionID: row[snsSessionID],
                state: row[snsState],
                createdAt: row[snsCreatedAt],
                updatedAt: row[snsUpdatedAt]
            )
        }
    }
}
