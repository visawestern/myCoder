import Testing
import Foundation
@testable import myCoder

/// TEST-ONLY MOCK: scripted HTTP transport that records every call and
/// replays a fixed (status, body) queue. Never used in production code.
private actor ScriptedRoleTransport: DirectChatTransport {
    struct Call: Equatable {
        let url: String
        let headers: [String: String]
        let body: String
    }

    private var calls: [Call] = []
    private let responses: [(status: Int, body: String)]
    private var next = 0

    init(responses: [(Int, String)]) {
        self.responses = responses.map { (status: $0.0, body: $0.1) }
    }

    func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? {
        calls.append(Call(url: url, headers: headers, body: String(data: body, encoding: .utf8) ?? ""))
        guard next < responses.count else { return nil }
        let response = responses[next]
        next += 1
        return (response.status, Data(response.body.utf8))
    }

    func get(url: String, headers: [String: String]) async -> (Int, Data)? { nil }

    func recorded() -> [Call] { calls }
}

private func testContext(
    custom: [CustomProvider] = [],
    local: [LocalProviderConfig] = [],
    server: [MimoProviderResponse] = [],
    serverConnected: Bool = false,
    webIDs: [String] = [],
    serverPort: Int = 4096,
    agentMode: AgentMode = .build
) -> RoleTransportContext {
    RoleTransportContext(
        customProviders: custom,
        localProviders: local,
        serverProviders: server,
        serverConnected: serverConnected,
        webProviderIDs: webIDs,
        serverPort: serverPort,
        agentMode: agentMode
    )
}

@MainActor
@Suite("Role transport resolution (M1)")
struct RoleTransportResolverTests {

    @Test("Local Ollama assignment resolves to the OpenAI-compatible /v1 route")
    func ollamaResolvesToOpenAICompatible() {
        let local = LocalProviderConfig(id: "loc-ollama-1", kind: .ollama, port: 11434, models: ["llama3"])
        let kind = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "loc-ollama-1", modelID: "llama3"),
            context: testContext(local: [local])
        )
        #expect(kind == .openAICompatible(baseURL: "http://127.0.0.1:11434/v1", apiKey: nil, model: "llama3"))
    }

    @Test("Local OpenCode assignment resolves to the session REST route")
    func openCodeResolvesToServe() {
        let local = LocalProviderConfig(id: "loc-oc-1", kind: .openCode, openCodeProviderID: "opencode")
        let kind = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "loc-oc-1", modelID: "gpt-x"),
            context: testContext(local: [local])
        )
        #expect(kind == .openCodeServe(baseURL: "http://127.0.0.1:4096", headers: [:], providerID: "opencode", model: "gpt-x"))
    }

    @Test("Custom cloud provider resolves with its own endpoint and key")
    func customResolvesToOpenAICompatible() {
        let custom = CustomProvider(id: "routetest-cp-1", name: "CP", type: .openAI,
                                    baseURL: "https://api.test/v1", apiKey: "secret")
        let kind = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "routetest-cp-1", modelID: "model-a"),
            context: testContext(custom: [custom])
        )
        if case .openAICompatible(let baseURL, let apiKey, let model) = kind {
            #expect(baseURL == "https://api.test/v1")
            #expect(apiKey == "secret")
            #expect(model == "model-a")
        } else {
            Issue.record("Custom provider must resolve to openAICompatible, got \(kind)")
        }
    }

    @Test("ACP-enabled custom provider resolves to the ACP transport")
    func acpCustomResolvesToACP() {
        let custom = CustomProvider(id: "routetest-acp-1", name: "ACP", type: .acp,
                                    baseURL: "http://127.0.0.1:8080/acp/v1", apiKey: "",
                                    acpEnabled: true)
        let kind = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "routetest-acp-1", modelID: "model-a"),
            context: testContext(custom: [custom])
        )
        #expect(kind == .acp(baseURL: "http://127.0.0.1:8080/acp/v1", apiKey: "", model: "model-a"))
    }

    @Test("Connected serve resolves its own catalog providers to mimoServe")
    func serverProviderResolvesToMimoServe() {
        let server = MimoProviderResponse(id: "srv-google", name: "Google", models: [:])
        let kind = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "srv-google", modelID: "gemini-x"),
            context: testContext(server: [server], serverConnected: true)
        )
        #expect(kind == .mimoServe(model: "gemini-x", providerID: "srv-google"))
    }

    @Test("Web providers are explicitly unsupported for role requests")
    func webResolvesToExplicitUnsupported() {
        let kind = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "web:cfg-routing-1", modelID: "chatgpt"),
            context: testContext(webIDs: ["cfg-routing-1"])
        )
        #expect(kind == .webUnsupported(configID: "cfg-routing-1"))
    }

    @Test("Unknown and disabled providers never resolve — no silent fallback")
    func unknownAndDisabledAreUnresolved() {
        let unknown = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "ghost-provider", modelID: "m"),
            context: testContext()
        )
        #expect(unknown == .unresolved)

        let disabled = CustomProvider(id: "routetest-off-1", name: "Off", type: .openAI,
                                      baseURL: "https://api.test/v1", apiKey: "k", isEnabled: false)
        let disabledKind = RoleTransportResolver.kind(
            for: ModelAssignment(providerID: "routetest-off-1", modelID: "m"),
            context: testContext(custom: [disabled])
        )
        #expect(disabledKind == .unresolved)
    }
}

@MainActor
@Suite("Role request execution (M1)")
struct RoleRequestExecutorTests {

    private let openAIResponse =
        #"{"choices":[{"message":{"role":"assistant","content":"plan ready","reasoning":"thinking"}}],"usage":{"prompt_tokens":11,"completion_tokens":7}}"#

    @Test("OpenAI-compatible kind sends the role input and maps real usage")
    func openAIKindSendsInputAndMapsUsage() async throws {
        let transport = ScriptedRoleTransport(responses: [(200, openAIResponse)])
        let custom = CustomProvider(id: "routetest-exec-1", name: "CP", type: .openAI,
                                    baseURL: "https://api.test/v1", apiKey: "secret")
        let executor = RoleRequestExecutor(context: testContext(custom: [custom]),
                                           directTransport: transport)
        let result = try await executor.send(
            role: .planning,
            assignment: ModelAssignment(providerID: "routetest-exec-1", modelID: "model-a"),
            input: "Build the plan"
        )
        #expect(result.text == "plan ready")
        #expect(result.reasoning == "thinking")
        #expect(result.usage == ModelRoleUsage(inputTokens: 11, outputTokens: 7))
        #expect(result.rawResponses?.first?.contains("plan ready") == true)

        let calls = await transport.recorded()
        #expect(calls.count == 1)
        #expect(calls[0].url == "https://api.test/v1/chat/completions")
        #expect(calls[0].headers["Authorization"] == "Bearer secret")
        #expect(calls[0].body.contains(#""model":"model-a""#))
        #expect(calls[0].body.contains("Build the plan"))
    }

    @Test("Vision images reach the OpenAI-compatible request as image_url parts")
    func visionImagesBecomeImageParts() async throws {
        let transport = ScriptedRoleTransport(responses: [(200, openAIResponse)])
        let custom = CustomProvider(id: "routetest-vis-1", name: "CP", type: .openAI,
                                    baseURL: "https://api.test/v1", apiKey: "")
        let executor = RoleRequestExecutor(context: testContext(custom: [custom]),
                                           directTransport: transport)
        _ = try await executor.send(
            role: .vision,
            assignment: ModelAssignment(providerID: "routetest-vis-1", modelID: "vision-model"),
            input: "Describe the screenshot",
            images: [ClipboardImage(base64: "QUJDRA==", mimeType: "image/png")]
        )
        let calls = await transport.recorded()
        #expect(calls.count == 1)
        #expect(calls[0].body.contains(#""type":"image_url""#))
        // JSONSerialization escapes "/" as "\/" inside the data URL, so the
        // prefix and the base64 payload are asserted separately.
        #expect(calls[0].body.contains("data:image"))
        #expect(calls[0].body.contains("base64,QUJDRA=="))
        #expect(calls[0].body.contains("Describe the screenshot"))
    }

    @Test("OpenCode serve kind runs exactly one ephemeral session turn")
    func serveKindRunsEphemeralSession() async throws {
        let transport = ScriptedRoleTransport(responses: [
            (200, #"{"id":"ses_routing_1"}"#),
            (200, #"{"parts":[{"type":"text","text":"served answer"}]}"#),
        ])
        let local = LocalProviderConfig(id: "routetest-oc-exec", kind: .openCode)
        let executor = RoleRequestExecutor(context: testContext(local: [local]),
                                           directTransport: transport)
        let result = try await executor.send(
            role: .execution,
            assignment: ModelAssignment(providerID: "routetest-oc-exec", modelID: "gpt-x"),
            input: "Do the work"
        )
        #expect(result.text == "served answer")
        let calls = await transport.recorded()
        #expect(calls.count == 2)
        #expect(calls[0].url == "http://127.0.0.1:4096/session")
        #expect(calls[1].url == "http://127.0.0.1:4096/session/ses_routing_1/message")
        #expect(calls[1].body.contains("Do the work"))
    }

    @Test("HTTP failures are thrown as-is — no fallback to another provider")
    func httpFailureThrowsWithoutFallback() async throws {
        let transport = ScriptedRoleTransport(responses: [(500, #"{"error":"boom"}"#)])
        let custom = CustomProvider(id: "routetest-err-1", name: "CP", type: .openAI,
                                    baseURL: "https://api.test/v1", apiKey: "")
        let executor = RoleRequestExecutor(context: testContext(custom: [custom]),
                                           directTransport: transport)
        do {
            _ = try await executor.send(
                role: .execution,
                assignment: ModelAssignment(providerID: "routetest-err-1", modelID: "model-a"),
                input: "x"
            )
            Issue.record("A 500 must surface as an error")
        } catch {
            let calls = await transport.recorded()
            #expect(calls.count == 1) // exactly one attempt, no alternative endpoint
        }
    }

    @Test("Web and unresolved assignments fail with explicit routing errors")
    func webAndUnresolvedFailExplicitly() async throws {
        let executor = RoleRequestExecutor(
            context: testContext(webIDs: ["cfg-routing-2"]),
            directTransport: ScriptedRoleTransport(responses: [])
        )
        do {
            _ = try await executor.send(
                role: .execution,
                assignment: ModelAssignment(providerID: "web:cfg-routing-2", modelID: "chatgpt"),
                input: "x"
            )
            Issue.record("Web role assignment must fail explicitly")
        } catch let error as ModelRoutingError {
            #expect(error == .webRoleUnsupported(role: .execution, configID: "cfg-routing-2"))
        }
        do {
            _ = try await executor.send(
                role: .review,
                assignment: ModelAssignment(providerID: "ghost-provider", modelID: "m"),
                input: "x"
            )
            Issue.record("Unresolved assignment must fail explicitly")
        } catch let error as ModelRoutingError {
            #expect(error == .unavailableProvider(providerID: "ghost-provider"))
        }
    }

    @Test("Serve-kind rejects images explicitly instead of silently dropping them")
    func serveKindRejectsImages() async throws {
        let local = LocalProviderConfig(id: "routetest-oc-vis", kind: .openCode)
        let executor = RoleRequestExecutor(context: testContext(local: [local]),
                                           directTransport: ScriptedRoleTransport(responses: []))
        do {
            _ = try await executor.send(
                role: .vision,
                assignment: ModelAssignment(providerID: "routetest-oc-vis", modelID: "gpt-x"),
                input: "Describe",
                images: [ClipboardImage(base64: "QUJDRA==", mimeType: "image/png")]
            )
            Issue.record("Serve transport cannot carry images and must say so")
        } catch let error as ModelRoutingError {
            #expect(error == .imagesUnsupported(role: .vision, modelID: "gpt-x"))
        }
    }

    @Test("mimo seam receives the exact assignment and agent mode (TEST MOCK)")
    func mimoSeamReceivesAssignment() async throws {
        // TEST-ONLY MOCK: captures what the real MimoServeClient would receive.
        actor Captured {
            var assignment: ModelAssignment?
            var agentMode: AgentMode?
            var input: String?
            var imageCount = 0
            func record(_ a: ModelAssignment, _ m: AgentMode, _ i: String, _ c: Int) {
                assignment = a; agentMode = m; input = i; imageCount = c
            }
        }
        let captured = Captured()
        let server = MimoProviderResponse(id: "routetest-srv", name: "Srv", models: [:])
        var executor = RoleRequestExecutor(
            context: testContext(server: [server], serverConnected: true, serverPort: 4321, agentMode: .plan),
            directTransport: ScriptedRoleTransport(responses: [])
        )
        executor.mimoSendOverride = { assignment, input, images, agentMode in
            await captured.record(assignment, agentMode, input, images.count)
            return ModelRoleResult(text: "mimo answer")
        }
        let result = try await executor.send(
            role: .compaction,
            assignment: ModelAssignment(providerID: "routetest-srv", modelID: "mimo-model"),
            input: "summarize this"
        )
        #expect(result.text == "mimo answer")
        #expect(await captured.assignment == ModelAssignment(providerID: "routetest-srv", modelID: "mimo-model"))
        #expect(await captured.agentMode == .plan)
        #expect(await captured.input == "summarize this")
    }

    @Test("ACP seam receives the exact assignment (TEST MOCK)")
    func acpSeamReceivesAssignment() async throws {
        // TEST-ONLY MOCK: captures what the real ACPClient would receive.
        actor Captured {
            var assignment: ModelAssignment?
            func record(_ a: ModelAssignment) { assignment = a }
        }
        let captured = Captured()
        let custom = CustomProvider(id: "routetest-acp-exec", name: "ACP", type: .acp,
                                    baseURL: "http://127.0.0.1:8080/acp/v1", apiKey: "",
                                    acpEnabled: true)
        var executor = RoleRequestExecutor(context: testContext(custom: [custom]),
                                           directTransport: ScriptedRoleTransport(responses: []))
        executor.acpSendOverride = { assignment, _, _ in
            await captured.record(assignment)
            return ModelRoleResult(text: "acp answer", usage: ModelRoleUsage(inputTokens: 3, outputTokens: 4))
        }
        let result = try await executor.send(
            role: .review,
            assignment: ModelAssignment(providerID: "routetest-acp-exec", modelID: "acp-model"),
            input: "review this"
        )
        #expect(result.text == "acp answer")
        #expect(result.usage == ModelRoleUsage(inputTokens: 3, outputTokens: 4))
        #expect(await captured.assignment?.modelID == "acp-model")
    }
}

@MainActor
@Suite("Routed images policy (M1)")
struct RoutedImagesPolicyTests {
    private let primary = ModelAssignment(providerID: "p-main", modelID: "main")
    private let visionModel = ModelAssignment(providerID: "p-vision", modelID: "sees")
    private let textModel = ModelAssignment(providerID: "p-text", modelID: "blind")

    private let openAIKind: (ModelAssignment) -> RoleTransportKind = { assignment in
        .openAICompatible(baseURL: "http://x/v1", apiKey: nil, model: assignment.modelID)
    }
    private let serveKind: (ModelAssignment) -> RoleTransportKind = { assignment in
        .openCodeServe(baseURL: "http://x", headers: [:], providerID: "oc", model: assignment.modelID)
    }

    @Test("The vision fallback node always carries the images")
    func visionNodeCarries() {
        let carriers = RoutedImagesPolicy.imageCarryingRoles(
            roles: [.vision, .dispatch, .execution, .finalResponse],
            primary: primary,
            assignments: { role in role == .vision ? visionModel : primary },
            visionSupport: { assignment in assignment == visionModel ? true : nil },
            transportKind: openAIKind
        )
        #expect(carriers.contains(.vision))
    }

    @Test("Explicitly vision-capable assignments carry images even without a vision node")
    func visionCapableCarries() {
        let carriers = RoutedImagesPolicy.imageCarryingRoles(
            roles: [.dispatch, .execution],
            primary: primary,
            assignments: { role in role == .execution ? visionModel : textModel },
            visionSupport: { assignment in assignment == visionModel ? true : false },
            transportKind: openAIKind
        )
        #expect(carriers == [.execution])
    }

    @Test("Without a vision node the primary-model roles carry images (single-mode parity)")
    func primaryParityWhenNoVisionNode() {
        let carriers = RoutedImagesPolicy.imageCarryingRoles(
            roles: [.dispatch, .execution, .finalResponse],
            primary: primary,
            assignments: { _ in primary },
            visionSupport: { _ in nil },
            transportKind: openAIKind
        )
        #expect(carriers == [.dispatch, .execution, .finalResponse])
    }

    @Test("Best effort: at least one image-capable role receives the images")
    func bestEffortFallback() {
        let carriers = RoutedImagesPolicy.imageCarryingRoles(
            roles: [.dispatch, .execution],
            primary: primary,
            assignments: { _ in primary },
            visionSupport: { _ in false }, // catalog says primary cannot see
            transportKind: openAIKind
        )
        #expect(carriers == [.dispatch])
    }

    @Test("A serve-only graph carries no images and the executor says so loudly")
    func serveOnlyCarriesNothing() {
        let carriers = RoutedImagesPolicy.imageCarryingRoles(
            roles: [.dispatch, .execution, .finalResponse],
            primary: primary,
            assignments: { _ in primary },
            visionSupport: { _ in nil },
            transportKind: serveKind
        )
        #expect(carriers.isEmpty)
    }
}
