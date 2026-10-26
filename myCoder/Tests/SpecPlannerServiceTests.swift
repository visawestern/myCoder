import Testing
import Foundation
@testable import myCoder

private final class FakeSpecCompletionProvider: SpecCompletionProviding {
    var responses: [Result<String, Error>]
    private(set) var requests: [SpecCompletionRequest] = []

    init(responses: [Result<String, Error>]) {
        self.responses = responses
    }

    func complete(_ request: SpecCompletionRequest) async throws -> String {
        requests.append(request)
        guard !responses.isEmpty else { throw SpecPlannerServiceError.emptyResponse }
        return try responses.removeFirst().get()
    }
}

private struct FakeSpecError: Error {}

@Suite("Spec planner service")
struct SpecPlannerServiceTests {

    private let brief = SpecWizardDraft(
        status: .draft,
        goal: "Offline notes app",
        stack: "SwiftUI",
        constraints: "No network",
        plannerModel: "planner",
        coderModel: "coder"
    )

    @Test("Supported send routes map to planner routes")
    func routeMapping() {
        #expect(SpecPlannerRoute(sendRoute: .openAICompatible(
            baseURL: "http://localhost:11434/v1", apiKey: nil, model: "llama"
        ), model: "") == .openAICompatible(baseURL: "http://localhost:11434/v1", apiKey: nil, model: "llama"))

        #expect(SpecPlannerRoute(sendRoute: .autoFree, model: "free") == .autoFree(model: "free"))
        #expect(SpecPlannerRoute(sendRoute: .openCodeServe(
            baseURL: "http://localhost:4096", headers: [:], providerID: "ollama", model: "m"
        ), model: "") == .openCodeServe(
            baseURL: "http://localhost:4096", headers: [:], providerID: "ollama", model: "m"
        ))
        #expect(SpecPlannerRoute(sendRoute: .web(configID: "w"), model: "m") == nil)
        #expect(SpecPlannerRoute(sendRoute: .none, model: "m") == nil)
    }

    @Test("Interview question is requested with the brief and history")
    func interviewQuestion() async throws {
        let provider = FakeSpecCompletionProvider(responses: [
            .success(#"{"id":"scope","question":"Which platforms?","suggested_answers":["macOS"],"done":false}"#)
        ])
        let service = SpecPlannerService(provider: provider)

        let question = try await service.nextInterviewQuestion(
            projectName: "Notes",
            brief: brief,
            turns: [SpecPlannerTurn(role: "user", content: "macOS only")],
            route: .autoFree(model: "free")
        )
        #expect(question.id == "scope")
        #expect(provider.requests.count == 1)
        #expect(provider.requests[0].messages.first?.role == "system")
        let userText = provider.requests[0].messages.last?.content ?? ""
        #expect(userText.contains("Offline notes app"))
        #expect(userText.contains("macOS only"))
    }

    @Test("Planner prompts follow the selected app language")
    func promptLanguage() async throws {
        let provider = FakeSpecCompletionProvider(responses: [
            .success(#"{"id":"scope","question":"Какие платформы?","suggested_answers":["macOS"],"done":false}"#)
        ])
        let service = SpecPlannerService(provider: provider)
        _ = try await service.nextInterviewQuestion(
            projectName: "Notes",
            brief: brief,
            turns: [],
            route: .autoFree(model: "free"),
            language: .russian
        )
        let system = provider.requests[0].messages.first?.content ?? ""
        #expect(system.contains("Russian"))
        #expect(system.contains("JSON keys"))
    }

    @Test("A done interview turn is passed through")
    func interviewDone() async throws {
        let provider = FakeSpecCompletionProvider(responses: [
            .success(#"{"id":"final","done":true,"summary":"Ready"}"#)
        ])
        let service = SpecPlannerService(provider: provider)
        let question = try await service.nextInterviewQuestion(
            projectName: "N", brief: brief, turns: [], route: .autoFree(model: "free")
        )
        #expect(question.done)
        #expect(question.summary == "Ready")
    }

    @Test("Malformed interview JSON surfaces a parse error")
    func interviewMalformed() async {
        let provider = FakeSpecCompletionProvider(responses: [.success("not json")])
        let service = SpecPlannerService(provider: provider)
        await #expect(throws: SpecPlannerParseError.self) {
            _ = try await service.nextInterviewQuestion(
                projectName: "N", brief: brief, turns: [], route: .autoFree(model: "free")
            )
        }
    }

    @Test("Specification generation rejects empty output")
    func specificationEmpty() async {
        let provider = FakeSpecCompletionProvider(responses: [.success("   ")])
        let service = SpecPlannerService(provider: provider)
        await #expect(throws: SpecPlannerServiceError.self) {
            _ = try await service.generateSpecification(
                projectName: "N", brief: brief, turns: [], route: .autoFree(model: "free")
            )
        }
    }

    @Test("Specification generation returns markdown and includes the brief")
    func specificationMarkdown() async throws {
        let provider = FakeSpecCompletionProvider(responses: [.success("# Spec\n\nBody")])
        let service = SpecPlannerService(provider: provider)
        let spec = try await service.generateSpecification(
            projectName: "Notes", brief: brief, turns: [], route: .autoFree(model: "free")
        )
        #expect(spec == "# Spec\n\nBody")
        #expect(provider.requests[0].messages.last?.content.contains("Offline notes app") == true)
    }

    @Test("Decomposition uses the validated parser")
    func decompositionParsed() async throws {
        let provider = FakeSpecCompletionProvider(responses: [
            .success("""
            {"nodes":[
              {"key":"N1","title":"Store","description":"Persist notes","kind":"task",
               "acceptance_criteria":["Survives restart"],"depends_on":[]}
            ]}
            """)
        ])
        let service = SpecPlannerService(provider: provider)
        let decomposition = try await service.generateDecomposition(
            projectName: "Notes", brief: brief, specification: "# Spec",
            route: .autoFree(model: "free")
        )
        #expect(decomposition.nodes.count == 1)
        #expect(decomposition.nextNode(completed: [])?.key == "N1")
    }

    @Test("Decomposition parse errors are not swallowed")
    func decompositionMalformed() async {
        let provider = FakeSpecCompletionProvider(responses: [.success("{}")])
        let service = SpecPlannerService(provider: provider)
        await #expect(throws: SpecPlannerParseError.self) {
            _ = try await service.generateDecomposition(
                projectName: "N", brief: brief, specification: "# S",
                route: .autoFree(model: "free")
            )
        }

        let emptyProvider = FakeSpecCompletionProvider(responses: [.success(#"{"nodes":[]}"#)])
        let emptyService = SpecPlannerService(provider: emptyProvider)
        await #expect(throws: SpecDecompositionError.self) {
            _ = try await emptyService.generateDecomposition(
                projectName: "N", brief: brief, specification: "# S",
                route: .autoFree(model: "free")
            )
        }
    }
}
