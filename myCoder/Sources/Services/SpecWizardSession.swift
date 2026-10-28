import Foundation
import Combine

/// Owns one project's spec wizard run: the small draft gate state plus the
/// append-only interview, specification revisions and decomposition stored in
/// the project database. The SwiftUI view only renders and forwards actions;
/// every state transition here is persisted before it is published as done.
@MainActor
final class SpecWizardSession: ObservableObject {
    @Published var draft: SpecWizardDraft
    @Published private(set) var turns: [SpecPlannerTurn] = []
    @Published private(set) var currentQuestion: SpecInterviewQuestion?
    /// Whether the question card is on screen. It hides the moment an answer
    /// is sent and comes back when the planner delivers the next question.
    @Published private(set) var isQuestionCardVisible = false
    @Published private(set) var completedSummary: String?
    @Published private(set) var specification: String = ""
    @Published private(set) var latestRevision: ProjectSpecRevision?
    @Published private(set) var nodes: [ProjectSpecNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSavedAt: Date?
    @Published var errorMessage: String?

    let projectPath: String
    var projectName: String

    private let database: ProjectDatabaseManager
    private let store: ProjectSpecStore
    private let planner: SpecPlannerService
    private let providerID: String?
    private let routeProvider: (String) -> SpecPlannerRoute?
    private let languageProvider: () -> AppLanguage
    private let projectID: String
    private lazy var repositoryContext: String = SpecContextBuilder.build(projectPath: projectPath)

    init(projectPath: String,
         projectName: String,
         database: ProjectDatabaseManager,
         providerID: String?,
         planner: SpecPlannerService = SpecPlannerService(),
         routeProvider: @escaping (String) -> SpecPlannerRoute?,
         languageProvider: @escaping () -> AppLanguage = { .english }) {
        self.projectPath = projectPath
        self.projectName = projectName
        self.database = database
        self.providerID = providerID
        self.planner = planner
        self.routeProvider = routeProvider
        self.languageProvider = languageProvider
        self.projectID = ProjectIdentityLogic.projectID(for: projectPath)
        self.store = database.makeSpecStore()
        self.draft = Self.loadDraft(from: database) ?? SpecWizardDraft()
        loadPersistedState()
        // A run always has an explicit position: the furthest step reached,
        // until the user navigates somewhere else. Without it a fresh draft
        // would jump to the interview the moment the brief becomes valid —
        // mid-typing. Kept in memory here (the view's autosave persists it),
        // so opening a project never writes a wizard row just to look at it.
        if draft.activeStep == nil {
            draft.activeStep = draft.furthestStep
        }
    }

    // MARK: - Loaded state

    private static func loadDraft(from database: ProjectDatabaseManager) -> SpecWizardDraft? {
        guard let raw = try? database.metadataValue(forKey: "spec_wizard_draft"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SpecWizardDraft.self, from: data)
    }

    private func loadPersistedState() {
        if let stored = try? store.turns(projectID: projectID) {
            turns = stored.map { SpecPlannerTurn(role: $0.role, content: $0.content) }
        }
        decodeLastQuestion()

        if let revision = try? store.latestRevision(projectID: projectID) {
            latestRevision = revision
            specification = revision.contentMarkdown
            draft.specVersion = Int(revision.version)
            if let storedNodes = try? store.nodes(revisionID: revision.id) {
                nodes = storedNodes
                draft.decompositionNodeCount = storedNodes.count
            }
        }
    }

    private func decodeLastQuestion() {
        guard let lastPlannerTurn = turns.last(where: { $0.role == "planner" }),
              let data = lastPlannerTurn.content.data(using: .utf8),
              let question = try? JSONDecoder().decode(SpecInterviewQuestion.self, from: data) else {
            currentQuestion = nil
            isQuestionCardVisible = false
            completedSummary = nil
            return
        }
        if question.done {
            currentQuestion = nil
            isQuestionCardVisible = false
            completedSummary = question.summary
        } else {
            currentQuestion = question
            isQuestionCardVisible = true
            completedSummary = nil
        }
    }

    // MARK: - Draft persistence

    /// Writes the small gate draft, the settings row and the five checklist
    /// rows in one pass. Returns false and surfaces the error on the view.
    @discardableResult
    func saveDraft() -> Bool {
        var storedDraft = draft
        storedDraft.updatedAt = Date().timeIntervalSince1970
        let now = Int64(Date().timeIntervalSince1970)
        do {
            let existing = try store.settings(projectID: projectID)
            var settings = ProjectSpecSettings(
                projectID: projectID,
                plannerProviderID: providerID,
                plannerModelID: draft.plannerModel,
                coderProviderID: providerID,
                coderModelID: draft.coderModel,
                status: draft.status.rawValue,
                currentStep: draft.visibleStep.rawValue,
                briefGoal: draft.goal,
                briefStack: draft.stack,
                briefConstraints: draft.constraints,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                completedAt: draft.status == .draft ? nil : (existing?.completedAt ?? now)
            )
            settings.status = draft.status.rawValue
            try store.saveSettings(settings)
            try store.replaceChecklist(projectID: projectID, items: checklistItems(now: now))

            let data = try JSONEncoder().encode(storedDraft)
            guard let raw = String(data: data, encoding: .utf8) else {
                errorMessage = "Could not save the setup draft"
                return false
            }
            try database.setMetadataValue(raw, forKey: "spec_wizard_draft")
            lastSavedAt = Date()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func checklistItems(now: Int64) -> [ProjectSpecChecklistItem] {
        let titles: [SpecWizardChecklistLogic.ItemID: String] = [
            .models: "Planning and coding models",
            .brief: "Project description",
            .interview: "Project questions",
            .specification: "Technical specification",
            .decomposition: "Task breakdown"
        ]
        return SpecWizardChecklistLogic.items(for: draft).enumerated().map { index, item in
            ProjectSpecChecklistItem(
                id: "\(projectID):\(item.id.rawValue)",
                projectID: projectID,
                itemKey: item.id.rawValue,
                title: titles[item.id] ?? item.id.rawValue,
                state: checklistState(item.state),
                detail: nil,
                sortOrder: Int64(index),
                updatedAt: now
            )
        }
    }

    private func checklistState(_ state: SpecWizardChecklistLogic.ItemState) -> String {
        switch state {
        case .done: return "done"
        case .pending: return "pending"
        case .upcoming: return "upcoming"
        }
    }

    private func appendHistory(action: String,
                               entityType: String,
                               entityID: String,
                               payloadJSON: String? = nil) {
        let entry = ProjectSpecHistoryEntry(
            id: UUID().uuidString,
            projectID: projectID,
            entityType: entityType,
            entityID: entityID,
            action: action,
            payloadJSON: payloadJSON,
            actor: "user",
            createdAt: Int64(Date().timeIntervalSince1970)
        )
        try? store.appendHistory(entry)
    }

    // MARK: - Navigation

    /// Opens a wizard step. Any phase the data has already unlocked can be
    /// reopened — that is how the user gets back to models/stack after a
    /// restart. The furthest reached step is never skipped, and the position
    /// is written to the project database before the view shows it.
    @discardableResult
    func go(to step: SpecWizardStep) -> Bool {
        guard !isLoading else { return false }
        guard step.rank <= draft.furthestStep.rank else {
            errorMessage = "That step unlocks after the previous ones are complete"
            return false
        }
        guard draft.activeStep != step else { return true }
        let previous = draft.activeStep
        draft.activeStep = step
        guard saveDraft() else {
            draft.activeStep = previous
            return false
        }
        errorMessage = nil
        appendHistory(action: "wizard_step_opened",
                      entityType: "wizard",
                      entityID: projectID,
                      payloadJSON: "{\"step\":\"\(step.rawValue)\"}")
        return true
    }

    // MARK: - Questions

    /// Sends one answer (or an empty string to fetch the first question) and
    /// appends both turns. The planner's JSON turn is stored verbatim so the
    /// question survives a restart with the same options.
    ///
    /// The answer only reaches the transcript together with the planner's
    /// reply: a failed turn stores nothing, so retrying cannot duplicate it.
    @discardableResult
    func submitAnswer(_ answer: String) async -> Bool {
        guard !isLoading else { return false }
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let route = route(for: draft.plannerModel) else { return false }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // The answered block leaves the screen at once; the next planner
        // question puts it back.
        let cardWasVisible = isQuestionCardVisible
        if !clean.isEmpty {
            isQuestionCardVisible = false
        }

        var pendingTurns = turns
        if !clean.isEmpty {
            pendingTurns.append(SpecPlannerTurn(role: "user", content: clean))
        }

        do {
            let question = try await nextQuestion(route: route, turns: pendingTurns)
            let encoded = try JSONEncoder().encode(question)
            let raw = String(data: encoded, encoding: .utf8) ?? ""
            let suggestions = try JSONEncoder().encode(question.suggestedAnswers)
            let suggestionsRaw = String(data: suggestions, encoding: .utf8)
            if !clean.isEmpty {
                let userTurn = try store.appendTurn(
                    projectID: projectID,
                    role: "user",
                    content: clean,
                    suggestedAnswersJSON: nil,
                    createdAt: Int64(Date().timeIntervalSince1970)
                )
                turns.append(SpecPlannerTurn(role: userTurn.role, content: userTurn.content))
            }
            let turn = try store.appendTurn(
                projectID: projectID,
                role: "planner",
                content: raw,
                suggestedAnswersJSON: suggestionsRaw,
                createdAt: Int64(Date().timeIntervalSince1970)
            )
            turns.append(SpecPlannerTurn(role: turn.role, content: turn.content))
            currentQuestion = question.done ? nil : question
            isQuestionCardVisible = !question.done
            completedSummary = question.done ? question.summary : nil

            if question.done && !draft.interviewComplete {
                draft.interviewComplete = true
                appendHistory(action: "interview_completed",
                              entityType: "interview",
                              entityID: projectID)
                _ = saveDraft()
            } else {
                _ = saveDraft()
            }
            return true
        } catch {
            isQuestionCardVisible = cardWasVisible
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Starts the interview on first entry. A restart with stored turns never
    /// asks the first question twice.
    func startInterviewIfNeeded() async {
        guard turns.isEmpty, !draft.interviewComplete, draft.visibleStep == .interview else { return }
        await submitAnswer("")
    }

    /// Reopens a finished interview with the user's correction. The planner
    /// re-checks how well the task is understood and either asks the next
    /// question or returns an updated summary. A failed request restores the
    /// completed state so the summary does not vanish.
    @discardableResult
    func clarify(_ text: String) async -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isLoading else { return false }
        let wasComplete = draft.interviewComplete
        let previousSummary = completedSummary
        draft.interviewComplete = false
        draft.activeStep = .interview
        completedSummary = nil
        isQuestionCardVisible = false
        _ = saveDraft()

        let ok = await submitAnswer(clean)
        if !ok {
            draft.interviewComplete = wasComplete
            completedSummary = previousSummary
            if wasComplete {
                isQuestionCardVisible = false
            } else if currentQuestion != nil {
                isQuestionCardVisible = true
            }
            _ = saveDraft()
        }
        return ok
    }

    /// One planner turn, with the host's stop rule applied: `done` is accepted
    /// only when the planner reports uncertainty at or below the threshold.
    /// A planner that keeps answering `done` while uncertain is sent back a
    /// bounded number of times, then its answer is accepted (the user can
    /// still Clarify) — the loop can never spin forever.
    private func nextQuestion(route: SpecPlannerRoute,
                              turns: [SpecPlannerTurn]) async throws -> SpecInterviewQuestion {
        var question = try await planner.nextInterviewQuestion(
            projectName: projectName,
            brief: draft,
            turns: turns,
            route: route,
            language: languageProvider()
        )
        var retries = 0
        while SpecInterviewLogic.needsMoreQuestions(question),
              retries < SpecInterviewLogic.maxUncertaintyRetries {
            retries += 1
            question = try await planner.nextInterviewQuestion(
                projectName: projectName,
                brief: draft,
                turns: turns,
                route: route,
                language: languageProvider(),
                requireMoreQuestions: true
            )
        }
        return question
    }

    // MARK: - Specification

    func generateSpecification() async {
        guard !isLoading else { return }
        guard draft.interviewComplete else {
            errorMessage = "Answer the project questions first"
            return
        }
        guard let route = route(for: draft.plannerModel) else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let markdown = try await planner.generateSpecification(
                projectName: projectName,
                brief: draft,
                turns: turns,
                route: route,
                repositoryContext: repositoryContext,
                language: languageProvider()
            )
            let revision = try store.appendRevision(
                projectID: projectID,
                contentMarkdown: markdown,
                summary: draft.goal,
                source: "planner",
                parentRevisionID: latestRevision?.id,
                createdAt: Int64(Date().timeIntervalSince1970)
            )
            latestRevision = revision
            specification = markdown
            draft.specVersion = Int(revision.version)
            nodes = (try? store.nodes(revisionID: revision.id)) ?? []
            draft.decompositionNodeCount = nodes.count
            // A written spec means the next thing to do is the task breakdown;
            // that screen also shows the spec itself.
            draft.activeStep = .decomposition
            appendHistory(action: "spec_revision_created",
                          entityType: "spec_revision",
                          entityID: revision.id,
                          payloadJSON: "{\"version\":\(revision.version)}")
            _ = saveDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Local edits create a new immutable revision rather than mutating the
    /// one the decomposition was built from.
    func saveSpecificationEdits(_ markdown: String) {
        let clean = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            errorMessage = "The specification cannot be empty"
            return
        }
        do {
            let revision = try store.appendRevision(
                projectID: projectID,
                contentMarkdown: clean,
                summary: draft.goal,
                source: "user",
                parentRevisionID: latestRevision?.id,
                createdAt: Int64(Date().timeIntervalSince1970)
            )
            latestRevision = revision
            specification = clean
            draft.specVersion = Int(revision.version)
            nodes = (try? store.nodes(revisionID: revision.id)) ?? []
            draft.decompositionNodeCount = nodes.count
            draft.activeStep = .decomposition
            appendHistory(action: "spec_revision_edited",
                          entityType: "spec_revision",
                          entityID: revision.id,
                          payloadJSON: "{\"version\":\(revision.version)}")
            _ = saveDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Tasks

    func generateDecomposition() async {
        guard !isLoading else { return }
        guard let revision = latestRevision, draft.specVersion > 0 else {
            errorMessage = "Create the specification first"
            return
        }
        guard nodes.isEmpty else {
            errorMessage = "Tasks already exist for this revision"
            return
        }
        guard let route = route(for: draft.plannerModel) else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let decomposition = try await planner.generateDecomposition(
                projectName: projectName,
                brief: draft,
                specification: revision.contentMarkdown,
                route: route,
                repositoryContext: repositoryContext,
                language: languageProvider()
            )
            let now = Int64(Date().timeIntervalSince1970)
            var nodeByKey: [String: ProjectSpecNode] = [:]
            for (index, item) in decomposition.nodes.enumerated() {
                let acceptance = try JSONEncoder().encode(item.acceptanceCriteria)
                nodeByKey[item.key] = ProjectSpecNode(
                    id: UUID().uuidString,
                    projectID: projectID,
                    revisionID: revision.id,
                    externalKey: item.key,
                    title: item.title,
                    description: item.description,
                    kind: item.kind,
                    status: "pending",
                    sortOrder: Int64(index),
                    acceptanceCriteriaJSON: String(data: acceptance, encoding: .utf8),
                    createdAt: now,
                    updatedAt: now
                )
            }
            var edges: [ProjectSpecEdge] = []
            for item in decomposition.nodes {
                guard let node = nodeByKey[item.key] else { continue }
                for dependencyKey in item.dependsOn {
                    guard let dependency = nodeByKey[dependencyKey] else { continue }
                    edges.append(ProjectSpecEdge(
                        id: UUID().uuidString,
                        projectID: projectID,
                        fromNodeID: node.id,
                        toNodeID: dependency.id,
                        kind: "depends_on",
                        createdAt: now
                    ))
                }
            }
            try store.insertDecomposition(nodes: Array(nodeByKey.values), edges: edges)
            nodes = try store.nodes(revisionID: revision.id)
            draft.decompositionNodeCount = nodes.count
            draft.activeStep = .ready
            appendHistory(action: "decomposition_created",
                          entityType: "decomposition",
                          entityID: revision.id,
                          payloadJSON: "{\"nodes\":\(nodes.count),\"edges\":\(edges.count)}")
            _ = saveDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dependencies(of node: ProjectSpecNode) -> [ProjectSpecNode] {
        guard let revision = latestRevision,
              let storedEdges = try? store.edges(revisionID: revision.id) else { return [] }
        let ids = Set(storedEdges.filter { $0.fromNodeID == node.id }.map(\.toNodeID))
        return nodes.filter { ids.contains($0.id) }
    }

    // MARK: - Finish

    @discardableResult
    func finishWizard(forced: Bool) -> Bool {
        if !forced {
            guard SpecWizardChecklistLogic.canFinish(draft) else {
                errorMessage = "Finish the specification and task breakdown before opening chat"
                return false
            }
        }
        draft.status = forced ? .forced : .complete
        guard saveDraft() else { return false }
        appendHistory(action: forced ? "wizard_forced" : "wizard_completed",
                      entityType: "wizard",
                      entityID: projectID)
        return true
    }

    // MARK: - Node execution

    static let allowedNodeStatuses: Set<String> = [
        "pending", "running", "done", "failed", "blocked", "skipped"
    ]

    @discardableResult
    func updateNodeStatus(nodeID: String, status: String) -> Bool {
        guard Self.allowedNodeStatuses.contains(status) else {
            errorMessage = "Unknown node status \(status)"
            return false
        }
        guard let revision = latestRevision,
              nodes.contains(where: { $0.id == nodeID }) else {
            errorMessage = "Node not found in the latest revision"
            return false
        }
        if status == "running", nextRunnableNode()?.id != nodeID {
            errorMessage = "Only the next runnable task can start"
            return false
        }
        do {
            let now = Int64(Date().timeIntervalSince1970)
            guard try store.updateNodeStatus(nodeID: nodeID, status: status, updatedAt: now) else {
                errorMessage = "Node not found"
                return false
            }
            nodes = try store.nodes(revisionID: revision.id)
            appendHistory(action: "node_status_changed",
                          entityType: "node",
                          entityID: nodeID,
                          payloadJSON: "{\"status\":\"\(status)\",\"revision\":\(revision.version)}")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func nextRunnableNode() -> ProjectSpecNode? {
        guard let revision = latestRevision else { return nil }
        return try? store.nextRunnableNode(revisionID: revision.id)
    }

    func canStartCoding(nodeID: String) -> Bool {
        guard latestRevision != nil,
              let node = nodes.first(where: { $0.id == nodeID }),
              node.status == "pending" else { return false }
        return nextRunnableNode()?.id == nodeID
    }

    func codingPrompt(for nodeID: String) -> String? {
        guard let node = nodes.first(where: { $0.id == nodeID }) else {
            errorMessage = "Node not found in the latest revision"
            return nil
        }
        return SpecNodeExecutionLogic.codingPrompt(
            node: node,
            specification: specification,
            projectPath: projectPath
        )
    }

    /// Starts the next runnable task: marks it running, links the chat session
    /// and returns the coder prompt. The caller creates and sends into the chat.
    @discardableResult
    func startCoding(nodeID: String, sessionID: String) -> String? {
        guard let prompt = codingPrompt(for: nodeID) else { return nil }
        guard canStartCoding(nodeID: nodeID) else {
            errorMessage = "Only the next runnable task can start"
            return nil
        }
        guard updateNodeStatus(nodeID: nodeID, status: "running") else { return nil }
        guard linkSession(sessionID, toNode: nodeID, state: "active") else {
            _ = updateNodeStatus(nodeID: nodeID, status: "pending")
            return nil
        }
        appendHistory(
            action: "node_coding_started",
            entityType: "node",
            entityID: nodeID,
            payloadJSON: "{\"sessionId\":\"\(sessionID)\"}"
        )
        return prompt
    }

    /// Manual verification result. Done/skipped unlocks dependents; failed or
    /// blocked keeps them locked until the user retries.
    @discardableResult
    func finishNode(nodeID: String, status: String) -> Bool {
        guard ["done", "failed", "blocked", "skipped"].contains(status) else {
            errorMessage = "Unsupported completion status \(status)"
            return false
        }
        guard updateNodeStatus(nodeID: nodeID, status: status) else { return false }
        let now = Int64(Date().timeIntervalSince1970)
        for link in nodeSessions(for: nodeID) where link.state == "active" {
            _ = try? store.updateNodeSessionState(
                nodeID: nodeID,
                sessionID: link.sessionID,
                state: status,
                updatedAt: now
            )
        }
        appendHistory(
            action: "node_finished",
            entityType: "node",
            entityID: nodeID,
            payloadJSON: "{\"status\":\"\(status)\"}"
        )
        return true
    }

    @discardableResult
    func retryNode(nodeID: String) -> Bool {
        guard let node = nodes.first(where: { $0.id == nodeID }),
              ["failed", "blocked"].contains(node.status) else {
            errorMessage = "Only a failed or blocked task can be retried"
            return false
        }
        return updateNodeStatus(nodeID: nodeID, status: "pending")
    }

    @discardableResult
    func linkSession(_ sessionID: String, toNode nodeID: String, state: String = "active") -> Bool {
        guard let revision = latestRevision,
              nodes.contains(where: { $0.id == nodeID }) else {
            errorMessage = "Node not found in the latest revision"
            return false
        }
        let now = Int64(Date().timeIntervalSince1970)
        let link = ProjectSpecNodeSession(
            id: UUID().uuidString,
            projectID: projectID,
            nodeID: nodeID,
            sessionID: sessionID,
            state: state,
            createdAt: now,
            updatedAt: now
        )
        do {
            try store.linkNodeSession(link)
            appendHistory(action: "node_session_linked",
                          entityType: "node",
                          entityID: nodeID,
                          payloadJSON: "{\"sessionId\":\"\(sessionID)\",\"revision\":\(revision.version)}")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func nodeSessions(for nodeID: String) -> [ProjectSpecNodeSession] {
        (try? store.nodeSessions(nodeID: nodeID)) ?? []
    }

    func revisionHistory() -> [ProjectSpecRevision] {
        (try? store.revisions(projectID: projectID)) ?? []
    }

    // MARK: - Routing

    private func route(for model: String) -> SpecPlannerRoute? {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Choose a planning model"
            return nil
        }
        guard let route = routeProvider(model) else {
            errorMessage = SpecPlannerServiceError.unsupportedRoute.localizedDescription
            return nil
        }
        return route
    }
}
