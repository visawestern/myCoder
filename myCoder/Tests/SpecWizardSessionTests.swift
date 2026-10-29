import Testing
import Foundation
@testable import myCoder

private final class SessionFakeProvider: SpecCompletionProviding {
    var responses: [Result<String, Error>]
    private(set) var requests: [SpecCompletionRequest] = []
    /// Runs before each response is returned so a test can pause a request in
    /// flight and inspect the published state while the planner is working.
    var beforeResponse: (() async -> Void)?

    init(responses: [Result<String, Error>]) {
        self.responses = responses
    }

    func complete(_ request: SpecCompletionRequest) async throws -> String {
        requests.append(request)
        if let beforeResponse {
            await beforeResponse()
        }
        guard !responses.isEmpty else { throw SpecPlannerServiceError.emptyResponse }
        return try responses.removeFirst().get()
    }
}

/// Holds a planner request open until the test opens it.
private final class PlannerGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isBlocked = false
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        isBlocked = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// Records the model/provider pairs the session asks the host to route.
private final class ProviderCallRecorder {
    private(set) var calls: [(model: String, providerID: String?)] = []

    func record(model: String, providerID: String?) {
        calls.append((model, providerID))
    }
}

@Suite("Spec wizard session")
struct SpecWizardSessionTests {

    @MainActor
    private func withSession(
        responses: [Result<String, Error>],
        projectFiles: [String: String] = [:],
        languageProvider: @escaping () -> AppLanguage = { .english },
        routeProvider: @escaping (String, String?) -> SpecPlannerRoute? = { model, _ in
            .autoFree(model: model)
        },
        body: (SpecWizardSession, ProjectSpecStore, SessionFakeProvider) async throws -> Void
    ) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-spec-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (path, content) in projectFiles {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        defer {
            ProjectDatabaseManager.evictProject(projectPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let manager = try ProjectDatabaseManager.manager(forProjectPath: dir.path)
        let provider = SessionFakeProvider(responses: responses)
        let session = SpecWizardSession(
            projectPath: dir.path,
            projectName: "Notes",
            database: manager,
            providerID: "test-provider",
            planner: SpecPlannerService(provider: provider),
            routeProvider: routeProvider,
            languageProvider: languageProvider
        )
        try await body(session, manager.makeSpecStore(), provider)
    }

    @MainActor
    private func prepare(_ session: SpecWizardSession) {
        session.draft.goal = "Offline notes app"
        session.draft.stack = "SwiftUI"
        session.draft.constraints = "No network"
        session.draft.plannerModel = "free"
        session.draft.coderModel = "free"
        #expect(session.saveDraft())
    }

    @Test("The planner route uses the provider stored in the draft")
    @MainActor
    func usesDraftProviderForRouting() async throws {
        let question = #"{"id":"q1","question":"Target OS?","suggested_answers":["macOS"],"done":false}"#
        let recorder = ProviderCallRecorder()
        try await withSession(
            responses: [.success(question)],
            routeProvider: { model, providerID in
                recorder.record(model: model, providerID: providerID)
                return .autoFree(model: model)
            }
        ) { session, _, _ in
            session.draft.plannerModel = "free"
            session.draft.coderModel = "free"
            session.draft.plannerProviderID = "custom-provider"
            _ = await session.submitAnswer("")
            #expect(recorder.calls.count == 1)
            #expect(recorder.calls.first?.model == "free")
            #expect(recorder.calls.first?.providerID == "custom-provider")
            #expect(session.currentQuestion?.question == "Target OS?")
        }
    }

    @Test("Interview turns persist and completion is derived from the planner")
    @MainActor
    func interviewPersists() async throws {
        let question = #"{"id":"q1","question":"Target OS?","suggested_answers":["macOS"],"done":false}"#
        let final = #"{"id":"final","done":true,"summary":"A macOS notes app"}"#
        try await withSession(responses: [.success(question), .success(final)]) { session, store, _ in
            prepare(session)
            await session.submitAnswer("")
            #expect(session.currentQuestion?.question == "Target OS?")
            #expect(session.draft.step == .interview)
            #expect(session.turns.count == 1)

            await session.submitAnswer("macOS")
            #expect(session.draft.interviewComplete)
            #expect(session.completedSummary == "A macOS notes app")
            #expect(session.currentQuestion == nil)
            #expect(session.draft.step == .specification)
            let storedTurns = try store.turns(projectID: ProjectIdentityLogic.projectID(for: session.projectPath))
            #expect(storedTurns.count == 3)

            let second = SpecWizardSession(
                projectPath: session.projectPath,
                projectName: "Notes",
                database: try ProjectDatabaseManager.manager(forProjectPath: session.projectPath),
                providerID: "test-provider",
                planner: SpecPlannerService(provider: SessionFakeProvider(responses: [])),
                routeProvider: { model, _ in .autoFree(model: model) }
            )
            #expect(second.draft.interviewComplete)
            #expect(second.turns.count == 3)
            #expect(second.completedSummary == "A macOS notes app")
        }
    }

    @Test("The answered question card hides while the planner works and returns with the next question")
    @MainActor
    func answeredQuestionCardHidesUntilNextQuestion() async throws {
        let first = #"{"id":"q1","question":"Target OS?","suggested_answers":["macOS"],"done":false}"#
        let second = #"{"id":"q2","question":"Which storage?","suggested_answers":["SQLite"],"done":false}"#
        try await withSession(responses: [.success(first), .success(second)]) { session, _, provider in
            prepare(session)
            await session.submitAnswer("")
            #expect(session.currentQuestion?.question == "Target OS?")
            #expect(session.isQuestionCardVisible)

            let gate = PlannerGate()
            provider.beforeResponse = { await gate.wait() }
            let answer = Task { await session.submitAnswer("macOS") }
            while !gate.isBlocked {
                await Task.yield()
            }
            #expect(!session.isQuestionCardVisible)
            gate.open()
            await answer.value
            #expect(session.currentQuestion?.question == "Which storage?")
            #expect(session.isQuestionCardVisible)
        }
    }

    @Test("A failed answer puts the question card back and stores no duplicate answer")
    @MainActor
    func failedAnswerKeepsQuestionCardVisible() async throws {
        let first = #"{"id":"q1","question":"Target OS?","suggested_answers":["macOS"],"done":false}"#
        let second = #"{"id":"q2","question":"Which storage?","suggested_answers":["SQLite"],"done":false}"#
        try await withSession(responses: [.success(first), .failure(SpecPlannerServiceError.emptyResponse), .success(second)]) { session, _, _ in
            prepare(session)
            await session.submitAnswer("")
            #expect(session.isQuestionCardVisible)

            await session.submitAnswer("macOS")
            #expect(session.errorMessage != nil)
            #expect(session.currentQuestion?.question == "Target OS?")
            #expect(session.isQuestionCardVisible)
            // The failed turn stored nothing: retrying must not leave two
            // identical answers in the transcript.
            #expect(session.turns.count == 1)

            session.errorMessage = nil
            await session.submitAnswer("macOS")
            #expect(session.turns.map(\.content).filter { $0 == "macOS" }.count == 1)
            #expect(session.currentQuestion?.question == "Which storage?")
            #expect(session.turns.count == 3)
        }
    }

    @Test("A clarification that fails keeps the summary on screen")
    @MainActor
    func failedClarificationKeepsSummary() async throws {
        try await withSession(responses: [.failure(SpecPlannerServiceError.emptyResponse)]) { session, _, _ in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())

            let ok = await session.clarify("It must run on Windows too")

            #expect(ok == false)
            #expect(session.errorMessage != nil)
            #expect(session.draft.interviewComplete)
            #expect(session.draft.visibleStep == .interview)
            // No orphan correction turn is left behind for a retry to duplicate.
            #expect(session.turns.isEmpty)
        }
    }

    @Test("A planner that stays uncertain is asked again, within a bounded budget")
    @MainActor
    func uncertainPlannerIsBounded() async throws {
        let first = #"{"id":"q1","question":"Target OS?","done":false}"#
        let premature1 = #"{"id":"final","done":true,"uncertainty":0.6,"summary":"An app"}"#
        let premature2 = #"{"id":"final","done":true,"uncertainty":0.5,"summary":"An app"}"#
        let premature3 = #"{"id":"final","done":true,"uncertainty":0.4,"summary":"An app"}"#
        let question = #"{"id":"q2","question":"Which storage?","done":false}"#
        try await withSession(responses: [.success(first), .success(premature1), .success(premature2), .success(question)]) { session, _, provider in
            prepare(session)
            await session.submitAnswer("")

            await session.submitAnswer("macOS")

            // One initial ask + two bounded re-asks.
            #expect(provider.requests.count == 4)
            #expect(!session.draft.interviewComplete)
            #expect(session.currentQuestion?.question == "Which storage?")
        }

        let stubborn = [
            Result<String, Error>.success(first),
            .success(premature1),
            .success(premature2),
            .success(premature3)
        ]
        try await withSession(responses: stubborn) { session, _, provider in
            prepare(session)
            await session.submitAnswer("")

            await session.submitAnswer("macOS")

            // The budget is exhausted rather than spinning forever: one
            // initial ask + exactly two re-asks.
            #expect(provider.requests.count == 4)
            #expect(session.draft.interviewComplete)
        }
    }

    @Test("A finished interview above the uncertainty threshold asks one more question")
    @MainActor
    func doneAboveThresholdKeepsInterviewing() async throws {
        let first = #"{"id":"q1","question":"Target OS?","suggested_answers":["macOS"],"uncertainty":0.6,"done":false}"#
        let premature = #"{"id":"final","done":true,"uncertainty":0.4,"summary":"An app"}"#
        let followUp = #"{"id":"q2","question":"Which storage?","suggested_answers":["SQLite"],"uncertainty":0.3,"done":false}"#
        try await withSession(responses: [.success(first), .success(premature), .success(followUp)]) { session, _, provider in
            prepare(session)
            await session.submitAnswer("")
            await session.submitAnswer("macOS")

            #expect(!session.draft.interviewComplete)
            #expect(session.completedSummary == nil)
            #expect(session.currentQuestion?.question == "Which storage?")
            #expect(session.isQuestionCardVisible)
            #expect(provider.requests.count == 3)
        }
    }

    @Test("A finished interview at or below the threshold completes")
    @MainActor
    func doneBelowThresholdCompletes() async throws {
        let first = #"{"id":"q1","question":"Target OS?","suggested_answers":["macOS"],"uncertainty":0.4,"done":false}"#
        let done = #"{"id":"final","done":true,"uncertainty":0.05,"summary":"A macOS notes app"}"#
        try await withSession(responses: [.success(first), .success(done)]) { session, _, provider in
            prepare(session)
            await session.submitAnswer("")
            await session.submitAnswer("macOS")

            #expect(session.draft.interviewComplete)
            #expect(session.completedSummary == "A macOS notes app")
            #expect(!session.isQuestionCardVisible)
            #expect(provider.requests.count == 2)
        }
    }

    @Test("A clarification reopens the interview and can ask again")
    @MainActor
    func clarificationReopensInterview() async throws {
        let first = #"{"id":"q1","question":"Target OS?","suggested_answers":["macOS"],"uncertainty":0.4,"done":false}"#
        let done = #"{"id":"final","done":true,"uncertainty":0.05,"summary":"A macOS notes app"}"#
        let followUp = #"{"id":"q2","question":"Windows too?","suggested_answers":["Yes","No"],"uncertainty":0.3,"done":false}"#
        try await withSession(responses: [.success(first), .success(done), .success(followUp)]) { session, _, _ in
            prepare(session)
            await session.submitAnswer("")
            await session.submitAnswer("macOS")
            #expect(session.draft.interviewComplete)

            await session.clarify("It must run on Windows as well")

            #expect(!session.draft.interviewComplete)
            #expect(session.completedSummary == nil)
            #expect(session.currentQuestion?.question == "Windows too?")
            #expect(session.turns.suffix(2).first?.content == "It must run on Windows as well")
        }
    }

    @Test("A fresh wizard opens on setup and keeps the user there while typing")
    @MainActor
    func freshWizardStaysOnSetupWhileTyping() async throws {
        try await withSession(responses: []) { session, _, _ in
            #expect(session.draft.visibleStep == .setup)
            session.draft.goal = "Offline notes app"
            session.draft.stack = "SwiftUI"
            session.draft.plannerModel = "free"
            session.draft.coderModel = "free"
            #expect(session.draft.step == .interview)
            #expect(session.draft.visibleStep == .setup)
        }
    }

    @Test("Going back to setup survives a restart and keeps the data")
    @MainActor
    func goingBackToSetupSurvivesRestart() async throws {
        try await withSession(responses: []) { session, _, _ in
            prepare(session)
            session.draft.interviewComplete = true
            session.draft.specVersion = 1
            #expect(session.saveDraft())
            #expect(session.go(to: .specification))
            #expect(session.draft.visibleStep == .specification)

            #expect(session.go(to: .setup))
            #expect(session.draft.visibleStep == .setup)
            #expect(session.draft.step == .decomposition)

            let second = SpecWizardSession(
                projectPath: session.projectPath,
                projectName: "Notes",
                database: try ProjectDatabaseManager.manager(forProjectPath: session.projectPath),
                providerID: "test-provider",
                planner: SpecPlannerService(provider: SessionFakeProvider(responses: [])),
                routeProvider: { model, _ in .autoFree(model: model) }
            )
            #expect(second.draft.visibleStep == .setup)
            #expect(second.draft.goal == "Offline notes app")
            #expect(second.draft.plannerModel == "free")
        }
    }

    @Test("A step the data has not unlocked cannot be opened")
    @MainActor
    func unreachedStepIsRefused() async throws {
        try await withSession(responses: []) { session, _, _ in
            prepare(session)
            #expect(session.draft.visibleStep == .setup)
            #expect(session.draft.step == .interview)

            #expect(session.go(to: .decomposition) == false)
            #expect(session.errorMessage != nil)
            #expect(session.draft.visibleStep == .setup)
        }
    }

    @Test("The specification step opens the tasks step when the spec is written")
    @MainActor
    func specificationMovesToTasksStep() async throws {
        try await withSession(responses: [.success("# Spec")]) { session, _, _ in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())
            #expect(session.go(to: .specification))

            await session.generateSpecification()

            #expect(session.errorMessage == nil)
            #expect(session.draft.visibleStep == .decomposition)
            #expect(session.go(to: .specification))
            #expect(session.draft.visibleStep == .specification)
        }
    }

    @Test("Clarifying reopens the interview step")
    @MainActor
    func clarifyOpensInterviewStep() async throws {
        let followUp = #"{"id":"q2","question":"Windows too?","done":false}"#
        try await withSession(responses: [.success(followUp)]) { session, _, _ in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())
            #expect(session.go(to: .specification))
            #expect(session.draft.visibleStep == .specification)

            await session.clarify("It must run on Windows as well")

            #expect(session.draft.visibleStep == .interview)
            #expect(session.currentQuestion?.question == "Windows too?")
        }
    }

    @Test("Interview requests use the language from settings")
    @MainActor
    func interviewUsesSettingsLanguage() async throws {
        let question = #"{"id":"q1","question":"Какая платформа?","suggested_answers":["macOS"],"done":false}"#
        try await withSession(
            responses: [.success(question)],
            languageProvider: { .russian }
        ) { session, _, provider in
            prepare(session)
            await session.submitAnswer("")
            let system = provider.requests[0].messages.first?.content ?? ""
            #expect(system.contains("Russian"))
        }
    }

    @Test("Specification and decomposition are stored as immutable rows")
    @MainActor
    func specificationAndDecomposition() async throws {
        let spec = "# Notes\n\nBuild an offline notes app."
        let decomposition = """
        {"nodes":[
          {"key":"N1","title":"Storage","description":"Local store","kind":"task",
           "acceptance_criteria":["Survives restart"],"depends_on":[]},
          {"key":"N2","title":"Editor","description":"Text editor","kind":"task",
           "acceptance_criteria":["Edits text"],"depends_on":["N1"]}
        ]}
        """
        try await withSession(responses: [.success(spec), .success(decomposition)]) { session, store, provider in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())

            await session.generateSpecification()
            #expect(session.errorMessage == nil)
            #expect(session.draft.specVersion == 1)
            #expect(session.latestRevision?.contentMarkdown == spec)
            #expect(provider.requests.count == 1)

            await session.generateDecomposition()
            #expect(session.errorMessage == nil)
            #expect(session.nodes.count == 2)
            #expect(session.draft.decompositionNodeCount == 2)
            #expect(session.draft.step == .ready)
            let revisionID = try #require(session.latestRevision?.id)
            #expect(try store.edges(revisionID: revisionID).count == 1)
            let editor = try #require(session.nodes.first { $0.externalKey == "N2" })
            #expect(session.dependencies(of: editor).map(\.externalKey) == ["N1"])
            #expect(session.finishWizard(forced: false))
            #expect(session.draft.status == .complete)
        }
    }

    @Test("A new specification revision starts a fresh decomposition")
    @MainActor
    func newRevisionResetsDecomposition() async throws {
        let first = "# Version one"
        let second = "# Version two"
        let decomposition = """
        {"nodes":[{"key":"N1","title":"One","description":"Do it","kind":"task",
        "acceptance_criteria":["Works"],"depends_on":[]}]}
        """
        try await withSession(responses: [.success(first), .success(decomposition), .success(second)]) { session, store, _ in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())

            await session.generateSpecification()
            await session.generateDecomposition()
            let firstRevisionID = try #require(session.latestRevision?.id)
            #expect(session.nodes.count == 1)

            await session.generateSpecification()
            #expect(session.draft.specVersion == 2)
            #expect(session.nodes.isEmpty)
            #expect(session.draft.decompositionNodeCount == 0)
            #expect(session.draft.step == .decomposition)
            #expect(try store.nodes(revisionID: firstRevisionID).count == 1)
        }
    }

    @Test("Saving the draft does not mutate the published draft")
    @MainActor
    func saveDoesNotLoop() async throws {
        try await withSession(responses: []) { session, _, _ in
            prepare(session)
            let before = session.draft.updatedAt
            #expect(session.saveDraft())
            #expect(session.draft.updatedAt == before)
        }
    }

    @Test("Existing project context reaches the specification prompt")
    @MainActor
    func repositoryContextReachesPlanner() async throws {
        try await withSession(
            responses: [.success("# Spec")],
            projectFiles: ["README.md": "# Existing app\n\nPostgres storage."]
        ) { session, _, provider in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())

            await session.generateSpecification()
            #expect(provider.requests.count == 1)
            let prompt = provider.requests[0].messages.map(\.content).joined(separator: "\n")
            #expect(prompt.contains("Postgres storage."))
            #expect(prompt.contains("Repository context"))
        }
    }

    @Test("Node status changes persist and revision history keeps every version")
    @MainActor
    func nodeStatusAndRevisionHistory() async throws {
        let first = "# Version one"
        let second = "# Version two"
        let decomposition = """
        {"nodes":[{"key":"N1","title":"One","description":"Do it","kind":"task",
        "acceptance_criteria":["Works"],"depends_on":[]}]}
        """
        try await withSession(responses: [.success(first), .success(decomposition), .success(second)]) { session, _, _ in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())

            await session.generateSpecification()
            await session.generateDecomposition()
            let node = try #require(session.nodes.first)
            #expect(session.updateNodeStatus(nodeID: node.id, status: "running"))
            #expect(session.nodes.first?.status == "running")
            #expect(!session.updateNodeStatus(nodeID: node.id, status: "not-a-status"))
            #expect(session.nodes.first?.status == "running")

            await session.generateSpecification()
            let versions = session.revisionHistory().map(\.version)
            #expect(versions == [1, 2])
        }
    }

    @Test("Node coding starts one task, links the chat and unlocks dependents when done")
    @MainActor
    func nodeCodingLifecycle() async throws {
        let spec = "# Approved spec"
        let decomposition = """
        {"nodes":[{"key":"N1","title":"One","description":"Do one","kind":"task",
        "acceptance_criteria":["One works"],"depends_on":[]},
        {"key":"N2","title":"Two","description":"Do two","kind":"task",
        "acceptance_criteria":["Two works"],"depends_on":["N1"]}]}
        """
        try await withSession(responses: [.success(spec), .success(decomposition)]) { session, _, _ in
            prepare(session)
            session.draft.interviewComplete = true
            #expect(session.saveDraft())
            await session.generateSpecification()
            await session.generateDecomposition()

            let n1 = try #require(session.nodes.first(where: { $0.externalKey == "N1" }))
            let n2 = try #require(session.nodes.first(where: { $0.externalKey == "N2" }))

            #expect(session.canStartCoding(nodeID: n1.id))
            #expect(!session.canStartCoding(nodeID: n2.id))
            let prompt = try #require(session.startCoding(nodeID: n1.id, sessionID: "chat-1"))
            #expect(prompt.contains("N1"))
            #expect(prompt.contains("One works"))
            #expect(session.nodes.first(where: { $0.id == n1.id })?.status == "running")
            #expect(session.nodeSessions(for: n1.id).first?.state == "active")
            #expect(!session.canStartCoding(nodeID: n2.id))
            #expect(session.startCoding(nodeID: n2.id, sessionID: "chat-2") == nil)

            #expect(session.finishNode(nodeID: n1.id, status: "done"))
            #expect(session.nodeSessions(for: n1.id).first?.state == "done")
            #expect(session.canStartCoding(nodeID: n2.id))
            #expect(session.startCoding(nodeID: n2.id, sessionID: "chat-2") != nil)

            #expect(session.finishNode(nodeID: n2.id, status: "failed"))
            #expect(!session.retryNode(nodeID: n1.id))
            #expect(session.retryNode(nodeID: n2.id))
            #expect(session.nodes.first(where: { $0.id == n2.id })?.status == "pending")
            #expect(session.canStartCoding(nodeID: n2.id))
            #expect(!session.finishNode(nodeID: n2.id, status: "not-a-status"))
        }
    }

    @Test("Forced finish persists without faking a decomposition")
    @MainActor
    func forcedFinish() async throws {
        try await withSession(responses: []) { session, _, _ in
            prepare(session)
            #expect(!session.finishWizard(forced: false))
            #expect(session.errorMessage != nil)
            #expect(session.finishWizard(forced: true))
            #expect(session.draft.status == .forced)

            let raw = try #require(try session.databaseValueForTesting(key: "spec_wizard_draft"))
            let decoded = try JSONDecoder().decode(SpecWizardDraft.self, from: Data(raw.utf8))
            #expect(decoded.status == .forced)
            #expect(decoded.interviewComplete == false)
            #expect(decoded.decompositionNodeCount == 0)
        }
    }
}

private extension SpecWizardSession {
    func databaseValueForTesting(key: String) throws -> String? {
        try ProjectDatabaseManager.manager(forProjectPath: projectPath).metadataValue(forKey: key)
    }
}
