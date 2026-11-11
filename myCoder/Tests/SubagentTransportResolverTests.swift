import Testing
import Foundation
@testable import myCoder

/// Фикстура каталога провайдеров для чистого резолвера транспорта субагента.
/// Значения только; ключи не копируются (см. `RoleTransportContext`).
private func routingContext(
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

private let fallbackTransport = SubagentRunner.Transport.openAICompatible(
    baseURL: URL(string: "http://127.0.0.1:11434")!,
    apiKey: "k",
    model: "parent-model"
)

/// Решение транспорта субагента (M1): в одиночном режиме субагент наследует
/// транспорт вызывающей модели; в режиме маршрутов он использует назначение
/// роли «Context research» — и только если это прямая OpenAI-совместимая
/// модель. Любой другой транспорт — явный `.unsupported`, без подмены.
@MainActor
@Suite("Subagent transport resolution")
struct SubagentTransportResolverTests {

    @Test("Single: субагент наследует транспорт вызывающей модели")
    func singleModeInheritsFallback() {
        let configuration = ModelRoutingConfiguration(mode: .single)
        let primary = ModelAssignment(providerID: "p", modelID: "m")
        let result = SubagentTransportResolver.transport(
            configuration: configuration,
            primary: primary,
            context: routingContext(),
            fallback: fallbackTransport
        )
        guard case .openAICompatible(let url, let key, let model) = result else {
            Issue.record("single-режим обязан вернуть transport родителя")
            return
        }
        #expect(url.absoluteString == "http://127.0.0.1:11434")
        #expect(key == "k")
        #expect(model == "parent-model")
    }

    @Test("Per-role: роль research задаёт модель субагента")
    func perRoleUsesResearchAssignment() {
        let custom = CustomProvider(
            id: "custom-1",
            name: "Custom",
            type: .openAI,
            baseURL: "https://api.example.com/v1",
            models: ["research-model"]
        )
        var configuration = ModelRoutingConfiguration(mode: .perRole)
        configuration.assignments[.research] = ModelAssignment(
            providerID: "custom-1", modelID: "research-model"
        )
        let result = SubagentTransportResolver.transport(
            configuration: configuration,
            primary: ModelAssignment(providerID: "x", modelID: "y"),
            context: routingContext(custom: [custom]),
            fallback: fallbackTransport
        )
        guard case .openAICompatible(let url, _, let model) = result else {
            Issue.record("per-role с прямой ролью обязан дать openAI-транспорт")
            return
        }
        #expect(url.absoluteString == "https://api.example.com/v1")
        #expect(model == "research-model")
    }

    @Test("Per-role: веб-назначение роли — явный unsupported")
    func perRoleWebIsUnsupported() {
        var configuration = ModelRoutingConfiguration(mode: .perRole)
        configuration.assignments[.research] = ModelAssignment(
            providerID: "web:webcfg", modelID: "m"
        )
        let result = SubagentTransportResolver.transport(
            configuration: configuration,
            primary: ModelAssignment(providerID: "x", modelID: "y"),
            context: routingContext(webIDs: ["webcfg"]),
            fallback: fallbackTransport
        )
        guard case .unsupported(let reason) = result else {
            Issue.record("веб-роль обязана быть честным unsupported")
            return
        }
        #expect(reason.contains("OpenAI-совместимая"))
    }

    @Test("Per-role: без назначения роли — честный unsupported")
    func perRoleMissingAssignmentIsUnsupported() {
        let configuration = ModelRoutingConfiguration(mode: .perRole)
        let result = SubagentTransportResolver.transport(
            configuration: configuration,
            primary: ModelAssignment(providerID: "x", modelID: "y"),
            context: routingContext(),
            fallback: fallbackTransport
        )
        guard case .unsupported(let reason) = result else {
            Issue.record("отсутствие назначения обязано быть unsupported")
            return
        }
        #expect(reason.contains("роли"))
    }

    @Test("Роль субагентов зафиксирована как research")
    func subagentRoleIsResearch() {
        #expect(SubagentTransportResolver.role == .research)
    }
}
