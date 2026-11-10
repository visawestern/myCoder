import Testing
import Foundation
@testable import myCoder

@Suite("Conditional role graph and execution journal")
struct TurnRouteGraphTests {
    private let primary = ModelAssignment(providerID: "alpha", modelID: "one")

    @Test func buildGraphHasOrderedStagesAndVisionPrecedesTextModels() {
        let graph = TurnRouteGraph.build(
            agentMode: .build,
            hasImages: true,
            mainSupportsVision: false,
            maxReviewCycles: 2
        )
        #expect(graph.initialRoles == [.vision, .dispatch, .planning, .research, .execution, .review, .finalResponse])
        #expect(graph.maxReviewCycles == 2)
        #expect(graph.requiresVisionFallback)
    }

    @Test func planAndComposeDoNotRunCodeExecutionOrUnrequestedReview() {
        #expect(TurnRouteGraph.build(agentMode: .plan).initialRoles == [.planning, .finalResponse])
        #expect(TurnRouteGraph.build(agentMode: .compose).initialRoles == [.dispatch, .execution, .finalResponse])
        #expect(!TurnRouteGraph.build(agentMode: .build, hasImages: true, mainSupportsVision: true).requiresVisionFallback)
    }

    @Test func runnerExecutesDifferentModelsAndRecordsRealArtifactsAndUsage() async throws {
        let assignments: [ModelRole: ModelAssignment] = [
            .dispatch: ModelAssignment(providerID: "a", modelID: "dispatch"),
            .planning: ModelAssignment(providerID: "b", modelID: "plan"),
            .research: ModelAssignment(providerID: "a", modelID: "research"),
            .execution: ModelAssignment(providerID: "c", modelID: "execute"),
            .review: ModelAssignment(providerID: "d", modelID: "review"),
            .finalResponse: ModelAssignment(providerID: "e", modelID: "final")
        ]
        let runner = TurnRouteRunner(
            configuration: ModelRoutingConfiguration(mode: .perRole, assignments: assignments),
            primary: primary,
            graph: TurnRouteGraph.build(agentMode: .build)
        )
        let report = try await runner.run(sessionID: "chat", request: "Implement") { role, assignment, input in
            #expect(input.contains("Implement"))
            return ModelRoleResult(
                text: role == .review ? #"{"issues":[]}"# : "\(role.rawValue) result",
                usage: ModelRoleUsage(inputTokens: 10, outputTokens: 2)
            )
        }
        #expect(report.outcome == .completed)
        #expect(report.entries.map(\.role) == [.dispatch, .planning, .research, .execution, .review, .finalResponse])
        #expect(report.entries.map(\.assignment.modelID) == ["dispatch", "plan", "research", "execute", "review", "final"])
        #expect(report.entries.allSatisfy { $0.sessionID == "chat" && $0.error == nil && $0.result?.isEmpty == false })
        #expect(report.entries.map(\.usage?.inputTokens) == Array(repeating: 10, count: 6))
        #expect(report.finalText == "finalResponse result")
    }

    @Test func reviewFindingsRunCorrectionAndBoundedSecondReview() async throws {
        let runner = TurnRouteRunner(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: primary,
            graph: TurnRouteGraph.build(agentMode: .build, maxReviewCycles: 2)
        )
        actor Calls {
            var roles: [ModelRole] = []
            var reviewCount = 0
            func add(_ role: ModelRole) { roles.append(role) }
            func nextReview() -> Int { reviewCount += 1; return reviewCount }
        }
        let calls = Calls()
        let report = try await runner.run(sessionID: "chat", request: "Implement") { role, _, _ in
            await calls.add(role)
            if role == .review {
                let count = await calls.nextReview()
                return ModelRoleResult(text: count == 1 ? #"{"issues":["test fails"]}"# : #"{"issues":[]}"#)
            }
            return ModelRoleResult(text: "\(role.rawValue) result")
        }
        #expect(report.outcome == .completed)
        #expect(await calls.roles == [.dispatch, .planning, .research, .execution, .review, .correction, .review, .finalResponse])
        #expect(report.entries.filter { $0.role == .correction }.count == 1)
    }

    @Test func endlessReviewFindingsStopAtConfiguredLimitWithoutInventingSuccess() async throws {
        let runner = TurnRouteRunner(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: primary,
            graph: TurnRouteGraph.build(agentMode: .build, maxReviewCycles: 1)
        )
        let report = try await runner.run(sessionID: "chat", request: "Implement") { role, _, _ in
            ModelRoleResult(text: role == .review ? #"{"issues":["still broken"]}"# : role.rawValue)
        }
        #expect(report.outcome == .reviewLimitReached)
        #expect(report.finalText == nil)
        #expect(report.entries.last?.role == .review)
    }

    @Test func cancellationStopsChildrenAndIsLogged() async {
        let runner = TurnRouteRunner(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: primary,
            graph: TurnRouteGraph.build(agentMode: .build)
        )
        actor ExecutedRoles { var roles: [ModelRole] = []; func add(_ role: ModelRole) { roles.append(role) } }
        let executed = ExecutedRoles()
        let task = Task {
            try await runner.run(sessionID: "chat", request: "Implement") { role, _, _ in
                await executed.add(role)
                return ModelRoleResult(text: role.rawValue)
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancellation must stop the graph")
        } catch is CancellationError {
            let roles = await executed.roles
            #expect(roles.isEmpty || roles == [.dispatch])
        } catch {
            Issue.record("Expected cancellation, got \(error)")
        }
    }

    @Test func transportErrorIsLoggedAndNeverFallsBackToPrimary() async {
        let runner = TurnRouteRunner(
            configuration: ModelRoutingConfiguration(
                mode: .perRole,
                assignments: [.planning: ModelAssignment(providerID: "beta", modelID: "planner")]
            ),
            primary: primary,
            graph: TurnRouteGraph.build(agentMode: .plan)
        )
        do {
            _ = try await runner.run(sessionID: "chat", request: "Plan") { _, _, _ in
                throw DirectChatError.emptyResponse
            }
            Issue.record("The failed role must fail its graph")
        } catch {
            #expect(error is DirectChatError)
        }
    }

    @Test func runCollectingKeepsTheJournalOfAFailedGraph() async {
        let runner = TurnRouteRunner(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: primary,
            graph: TurnRouteGraph.build(agentMode: .compose)
        )
        let outcome = await runner.runCollecting(sessionID: "chat", request: "Do") { role, _, _ in
            if role == .execution { throw DirectChatError.emptyResponse }
            return ModelRoleResult(text: role.rawValue)
        }
        #expect(outcome.error != nil)
        #expect(outcome.report.outcome == .failed)
        #expect(outcome.report.finalText == nil)
        // Both nodes are journaled: the completed dispatch and the failed execution.
        #expect(outcome.report.entries.map(\.role) == [.dispatch, .execution])
        #expect(outcome.report.entries[0].error == nil)
        #expect(outcome.report.entries[0].result == "dispatch")
        #expect(outcome.report.entries[1].error != nil)
        #expect(outcome.report.entries[1].result == nil)
    }

    @Test func runCollectingKeepsTheJournalOnCancellation() async {
        let runner = TurnRouteRunner(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: primary,
            graph: TurnRouteGraph.build(agentMode: .build)
        )
        let task = Task {
            await runner.runCollecting(sessionID: "chat", request: "Do") { role, _, _ in
                ModelRoleResult(text: role.rawValue)
            }
        }
        task.cancel()
        let outcome = await task.value
        if outcome.error != nil {
            #expect(outcome.report.outcome == .failed)
            // Whatever ran before the cancellation is still journaled.
            #expect(outcome.report.entries.allSatisfy { $0.sessionID == "chat" })
        }
    }
}
