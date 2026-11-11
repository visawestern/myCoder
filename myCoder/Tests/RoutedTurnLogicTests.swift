import Testing
import Foundation
@testable import myCoder

/// TEST-ONLY MOCK: scripted HTTP transport for the routed-turn executor tests.
/// Replays a fixed (status, body) queue and records every call. Never used in
/// production code. (Separate copy: ScriptedRoleTransport is private to
/// RoleModelTransportTests.swift.)
private actor RoutedTurnScriptedTransport: DirectChatTransport {
    private let responses: [(status: Int, body: String)]
    private var next = 0
    private(set) var postedBodies: [String] = []

    init(responses: [(Int, String)]) {
        self.responses = responses.map { (status: $0.0, body: $0.1) }
    }

    func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? {
        postedBodies.append(String(data: body, encoding: .utf8) ?? "")
        guard next < responses.count else { return nil }
        let response = responses[next]
        next += 1
        return (response.status, Data(response.body.utf8))
    }

    func get(url: String, headers: [String: String]) async -> (Int, Data)? { nil }
}

/// Builds a minimal catalog snapshot with one enabled local Ollama provider.
private func routedTestContext(models: [String] = ["gemma4", "speakeasy-gemma4-e2b-cpu"]) -> RoleTransportContext {
    RoleTransportContext(
        customProviders: [],
        localProviders: [LocalProviderConfig(id: "routed-ollama", kind: .ollama, port: 11434, models: models)],
        serverProviders: [],
        serverConnected: false,
        webProviderIDs: [],
        serverPort: 4096,
        agentMode: .compose
    )
}

private func openAIResponse(_ content: String, prompt: Int = 10, completion: Int = 5) -> (Int, String) {
    (200, #"{"choices":[{"message":{"role":"assistant","content":"\#(content)"}}],"usage":{"prompt_tokens":\#(prompt),"completion_tokens":\#(completion)}}"#)
}

private func makeEntry(
    role: ModelRole,
    providerID: String = "routed-ollama",
    modelID: String = "gemma4",
    error: String? = nil,
    input: Int? = nil,
    output: Int? = nil,
    result: String? = "ok"
) -> TurnRouteJournalEntry {
    TurnRouteJournalEntry(
        id: UUID().uuidString,
        sessionID: "s1",
        role: role,
        assignment: ModelAssignment(providerID: providerID, modelID: modelID),
        startedAt: Date(),
        finishedAt: error == nil ? Date() : nil,
        inputArtifacts: [],
        result: error == nil ? result : nil,
        usage: error == nil ? ModelRoleUsage(inputTokens: input, outputTokens: output) : nil,
        rawResponses: nil,
        error: error
    )
}

@MainActor
@Suite("Routed turn pure logic (M1)")
struct RoutedTurnLogicTests {

    @Test("aggregateUsage sums node tokens and names every routed node")
    func aggregateUsageSums() {
        let entries = [
            makeEntry(role: .dispatch, input: 10, output: 5),
            makeEntry(role: .execution, providerID: "routed-ollama", modelID: "kimi", input: 1, output: 2),
        ]
        let usage = RoutedTurnLogic.aggregateUsage(entries: entries)
        #expect(usage?.promptTokens == 11)
        #expect(usage?.completionTokens == 7)
        #expect(usage?.costUSD == nil)
        #expect(usage?.modelID == "routed:2 nodes")
        #expect(usage?.providerID == "routed-ollama")
    }

    @Test("aggregateUsage joins multiple providers sorted with +")
    func aggregateUsageMultipleProviders() {
        let entries = [
            makeEntry(role: .planning, providerID: "zeta", input: 1, output: 1),
            makeEntry(role: .review, providerID: "alpha", input: 2, output: 2),
        ]
        #expect(RoutedTurnLogic.aggregateUsage(entries: entries)?.providerID == "alpha+zeta")
    }

    @Test("aggregateUsage is nil when nothing was reported")
    func aggregateUsageNilOnZeros() {
        #expect(RoutedTurnLogic.aggregateUsage(entries: []) == nil)
        #expect(RoutedTurnLogic.aggregateUsage(entries: [makeEntry(role: .dispatch, input: 0, output: 0)]) == nil)
    }

    @Test("chips name role and real provider/model, warning marks unfinished nodes")
    func chipsFormat() {
        let entries = [
            makeEntry(role: .execution, modelID: "gemma4"),
            makeEntry(role: .review, modelID: "kimi", error: "boom", result: nil),
        ]
        let chips = RoutedTurnLogic.chips(entries: entries)
        #expect(chips == ["Execution → routed-ollama/gemma4", "⚠️ Review → routed-ollama/kimi"])
    }

    @Test("failureMessage names the failed node and states no fallback was used")
    func failureMessageIsHonest() {
        let entries = [
            makeEntry(role: .dispatch),
            makeEntry(role: .execution, providerID: "cp", modelID: "m1", error: "HTTP 500", result: nil),
        ]
        let message = RoutedTurnLogic.failureMessage(
            entries: entries,
            error: ModelRoutingError.unavailableModel(role: .execution, modelID: "m1")
        )
        #expect(message.contains("Execution"))
        #expect(message.contains("cp/m1"))
        #expect(message.contains("No fallback provider was used."))
    }

    @Test("reviewLimitText shows the findings and the last draft")
    func reviewLimitTextShowsEvidence() {
        let entries = [
            makeEntry(role: .execution, result: "draft answer"),
            makeEntry(role: .correction, result: "corrected draft"),
            makeEntry(role: .review, result: #"{"issues":["missing tests"],"complete":false}"#),
        ]
        let report = TurnRouteReport(entries: entries, finalText: nil, outcome: .reviewLimitReached)
        let text = RoutedTurnLogic.reviewLimitText(report: report)
        #expect(text.contains("missing tests"))
        #expect(text.contains("corrected draft"))
    }

    @Test("imageAttachments reads only real image files from disk")
    func imageAttachmentsFilter() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("routed-turn-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // PNG magic bytes: the only shape MessagePartsBuilder accepts as image.
        let pngPath = directory.appendingPathComponent("shot.png").path
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01]
        FileManager.default.createFile(atPath: pngPath, contents: Data(pngBytes))
        let textPath = directory.appendingPathComponent("notes.md").path
        FileManager.default.createFile(atPath: textPath, contents: Data("hello".utf8))

        let images = RoutedTurnLogic.imageAttachments(files: [
            FileInfo(name: "shot.png", type: .unknown, path: pngPath),
            FileInfo(name: "notes.md", type: .markdown, path: textPath),
            FileInfo(name: "ghost.png", type: .unknown, path: directory.appendingPathComponent("ghost.png").path),
        ])
        #expect(images.count == 1)
        #expect(images.first?.mimeType == "image/png")
    }

    @Test("validateAllRoles rejects a missing assignment before any send")
    func validateMissing() {
        let graph = TurnRouteGraph.build(agentMode: .compose)
        let resolver = ModelRouteResolver(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: ModelAssignment(providerID: "", modelID: "")
        )
        #expect(throws: ModelRoutingError.missingAssignment(role: .dispatch)) {
            try RoutedTurnLogic.validateAllRoles(
                graph: graph, resolver: resolver,
                availableModels: [:], visionSupport: [:]
            )
        }
    }

    @Test("validateAllRoles rejects a model absent from the real catalog")
    func validateUnavailableModel() {
        let graph = TurnRouteGraph.build(agentMode: .compose)
        let resolver = ModelRouteResolver(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: ModelAssignment(providerID: "routed-ollama", modelID: "deleted-model")
        )
        #expect(throws: ModelRoutingError.unavailableModel(role: .dispatch, modelID: "deleted-model")) {
            try RoutedTurnLogic.validateAllRoles(
                graph: graph, resolver: resolver,
                availableModels: ["routed-ollama": ["gemma4"]], visionSupport: [:]
            )
        }
    }

    @Test("validateAllRoles also validates correction when review is in the graph")
    func validateIncludesCorrection() {
        let graph = TurnRouteGraph.build(agentMode: .build)
        #expect(graph.initialRoles.contains(.review))
        let resolver = ModelRouteResolver(
            configuration: ModelRoutingConfiguration(mode: .perRole, assignments: [
                .dispatch: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                .planning: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                .research: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                .execution: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                .review: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                .finalResponse: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                // correction deliberately points at a deleted model
                .correction: ModelAssignment(providerID: "routed-ollama", modelID: "gone"),
            ]),
            primary: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4")
        )
        #expect(throws: ModelRoutingError.unavailableModel(role: .correction, modelID: "gone")) {
            try RoutedTurnLogic.validateAllRoles(
                graph: graph, resolver: resolver,
                availableModels: ["routed-ollama": ["gemma4"]], visionSupport: [:]
            )
        }
    }

    @Test("validateAllRoles rejects a vision node whose catalog says no vision")
    func validateVisionUnavailable() {
        let graph = TurnRouteGraph.build(agentMode: .compose, hasImages: true, mainSupportsVision: false)
        #expect(graph.requiresVisionFallback)
        let visionAssignment = ModelAssignment(providerID: "routed-ollama", modelID: "gemma4")
        let resolver = ModelRouteResolver(
            configuration: ModelRoutingConfiguration(mode: .perRole, assignments: [
                .vision: visionAssignment,
            ]),
            primary: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4")
        )
        #expect(throws: ModelRoutingError.visionUnavailable) {
            try RoutedTurnLogic.validateAllRoles(
                graph: graph, resolver: resolver,
                availableModels: ["routed-ollama": ["gemma4"]],
                visionSupport: [visionAssignment: false]
            )
        }
    }
}

@MainActor
@Suite("Routed turn executor (M1)")
struct RoutedTurnExecutorTests {

    private func composeSnapshot(
        configuration: ModelRoutingConfiguration,
        primary: ModelAssignment = ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
        request: String = "do the task"
    ) -> RoutedTurnSnapshot {
        RoutedTurnSnapshot(
            configuration: configuration,
            primary: primary,
            context: routedTestContext(models: ["gemma4", "kimi"]),
            availableModels: ["routed-ollama": ["gemma4", "kimi"]],
            visionSupport: [:],
            mainSupportsVision: nil,
            agentMode: .compose,
            sessionID: "s-exec",
            request: request,
            images: []
        )
    }

    @Test("Compose graph runs dispatch → execution → finalResponse on the assigned models")
    func executorRunsComposeChain() async {
        let transport = RoutedTurnScriptedTransport(responses: [
            openAIResponse("routed", prompt: 3, completion: 1),
            openAIResponse("worked", prompt: 10, completion: 5),
            openAIResponse("final answer", prompt: 7, completion: 2),
        ])
        let snapshot = composeSnapshot(
            configuration: ModelRoutingConfiguration(mode: .perRole, assignments: [
                .dispatch: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                .execution: ModelAssignment(providerID: "routed-ollama", modelID: "kimi"),
                .finalResponse: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
            ])
        )
        let outcome = await RoutedTurnExecutor.run(snapshot: snapshot, transport: transport)
        #expect(outcome.status == .completed)
        #expect(outcome.finalText == "final answer")
        #expect(outcome.entries.count == 3)
        #expect(outcome.entries.map(\.role) == [.dispatch, .execution, .finalResponse])
        #expect(outcome.entries.map(\.assignment.modelID) == ["gemma4", "kimi", "gemma4"])
        #expect(outcome.entries.allSatisfy { $0.isCompleted })
        #expect(outcome.usage?.promptTokens == 20)
        #expect(outcome.usage?.modelID == "routed:3 nodes")
        #expect(outcome.chips == [
            "Request routing → routed-ollama/gemma4",
            "Execution → routed-ollama/kimi",
            "Final response → routed-ollama/gemma4",
        ])
    }

    @Test("A failed node stops the graph honestly and still journals every node")
    func executorFailsHonestly() async {
        let transport = RoutedTurnScriptedTransport(responses: [
            openAIResponse("routed"),
            (500, #"{"error":"server exploded"}"#),
        ])
        let snapshot = composeSnapshot(
            configuration: ModelRoutingConfiguration(mode: .perRole, assignments: [
                .dispatch: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
                .execution: ModelAssignment(providerID: "routed-ollama", modelID: "kimi"),
                .finalResponse: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
            ])
        )
        let outcome = await RoutedTurnExecutor.run(snapshot: snapshot, transport: transport)
        if case .failed(let message) = outcome.status {
            #expect(message.contains("Execution"))
            #expect(message.contains("No fallback provider was used."))
        } else {
            Issue.record("Expected .failed, got \(outcome.status)")
        }
        #expect(outcome.finalText == nil)
        // The journal keeps both the successful dispatch and the failed node.
        #expect(outcome.entries.count == 2)
        #expect(outcome.entries[0].isCompleted)
        #expect(outcome.entries[1].error != nil)
        #expect(outcome.chips[1].hasPrefix("⚠️"))
    }

    @Test("Pre-send validation failure never touches the network")
    func executorValidatesBeforeSend() async {
        let transport = RoutedTurnScriptedTransport(responses: [openAIResponse("never")])
        let snapshot = composeSnapshot(
            configuration: ModelRoutingConfiguration(mode: .perRole),
            primary: ModelAssignment(providerID: "routed-ollama", modelID: "deleted-model")
        )
        let outcome = await RoutedTurnExecutor.run(snapshot: snapshot, transport: transport)
        if case .failed(let message) = outcome.status {
            #expect(message.contains("deleted-model"))
        } else {
            Issue.record("Expected .failed, got \(outcome.status)")
        }
        #expect(outcome.entries.isEmpty)
        let bodies = await transport.postedBodies
        #expect(bodies.isEmpty)
    }

    @Test("Vision fallback is a hard failure when no node can carry images")
    func executorVisionFallbackHonest() async {
        let transport = RoutedTurnScriptedTransport(responses: [openAIResponse("never")])
        var snapshot = composeSnapshot(
            configuration: ModelRoutingConfiguration(mode: .perRole, assignments: [
                .vision: ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"),
            ])
        )
        snapshot.mainSupportsVision = false
        snapshot.images = [ClipboardImage(base64: "AAAA", mimeType: "image/png")]
        snapshot.visionSupport = [ModelAssignment(providerID: "routed-ollama", modelID: "gemma4"): false]
        let outcome = await RoutedTurnExecutor.run(snapshot: snapshot, transport: transport)
        if case .failed(let message) = outcome.status {
            #expect(message.lowercased().contains("vision"))
        } else {
            Issue.record("Expected .failed, got \(outcome.status)")
        }
        let bodies = await transport.postedBodies
        #expect(bodies.isEmpty)
    }

    @Test("Progress callback reports each node before it is sent")
    func executorReportsProgress() async {
        let transport = RoutedTurnScriptedTransport(responses: [
            openAIResponse("routed"), openAIResponse("worked"), openAIResponse("done"),
        ])
        let snapshot = composeSnapshot(
            configuration: ModelRoutingConfiguration(mode: .perRole)
        )
        let progressLog = ProgressLog()
        _ = await RoutedTurnExecutor.run(snapshot: snapshot, progress: { role, assignment in
            Task { await progressLog.add("\(role.rawValue)→\(assignment.modelID)") }
        }, transport: transport)
        // Give the detached logging tasks a moment to land.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let lines = await progressLog.lines
        #expect(lines == ["dispatch→gemma4", "execution→gemma4", "finalResponse→gemma4"])
    }
}

/// TEST-ONLY helper: collects progress callbacks from @Sendable closures.
private actor ProgressLog {
    private(set) var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
}
