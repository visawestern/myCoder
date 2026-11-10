import Testing
import Foundation
@testable import myCoder

@Suite("Role-based model routing")
struct ModelRoutingTests {
    private let primary = ModelAssignment(providerID: "alpha", modelID: "one")

    @Test func allNineRolesAreStableAndPersistable() throws {
        #expect(ModelRole.allCases.count == 9)
        let assignment = ModelAssignment(
            providerID: " beta ",
            modelID: " two ",
            parameters: ModelCallParameters(temperature: 0.2)
        )
        #expect(assignment.providerID == "beta")
        #expect(assignment.modelID == "two")
        let restored = try JSONDecoder().decode(
            ModelRoutingConfiguration.self,
            from: JSONEncoder().encode(ModelRoutingConfiguration(
                mode: .perRole,
                assignments: [.planning: assignment]
            ))
        )
        #expect(restored.mode == .perRole)
        #expect(restored.assignments[.planning] == assignment)
    }

    @Test func singleModelIsAuthoritativeWithoutDeletingInactiveAssignments() {
        let individual = ModelAssignment(providerID: "beta", modelID: "two")
        let configuration = ModelRoutingConfiguration(
            mode: .single,
            assignments: [.planning: individual]
        )
        let resolver = ModelRouteResolver(configuration: configuration, primary: primary)
        #expect(resolver.assignment(for: .planning) == primary)
        #expect(resolver.assignment(for: .vision) == primary)
        #expect(configuration.assignments[.planning] == individual)
    }

    @Test func perRoleUsesEveryIndependentAssignmentAndPrimaryForMissingRoles() {
        let review = ModelAssignment(providerID: "gamma", modelID: "three")
        let configuration = ModelRoutingConfiguration(
            mode: .perRole,
            assignments: [.planning: ModelAssignment(providerID: "beta", modelID: "two"), .review: review]
        )
        let resolver = ModelRouteResolver(configuration: configuration, primary: primary)
        #expect(resolver.assignment(for: .planning)?.modelID == "two")
        #expect(resolver.assignment(for: .review) == review)
        #expect(resolver.assignment(for: .execution) == primary)
        #expect(resolver.resolvedAssignments.count == 9)
        #expect(resolver.usesMultipleProviders)
    }

    @Test func incompleteOrInvalidRoleIsAnErrorNeverAnotherProvider() {
        let configuration = ModelRoutingConfiguration(
            mode: .perRole,
            assignments: [.vision: ModelAssignment(providerID: "", modelID: "")]
        )
        let resolver = ModelRouteResolver(configuration: configuration, primary: primary)
        // M1: a missing vision model is its own explicit error — the send must
        // offer a vision choice, never pretend success or pick another model.
        #expect(throws: ModelRoutingError.visionUnavailable) {
            try resolver.validatedAssignment(for: .vision)
        }
        let removed = ModelRouteResolver(
            configuration: ModelRoutingConfiguration(
                mode: .perRole,
                assignments: [.execution: ModelAssignment(providerID: "alpha", modelID: "gone")]
            ),
            primary: primary
        )
        #expect(throws: ModelRoutingError.unavailableModel(role: .execution, modelID: "gone")) {
            try removed.validatedAssignment(
                for: .execution,
                availableModels: ["alpha": ["one"]]
            )
        }
    }

    @Test func storeRoundTripsProjectAndChatPrecedence() throws {
        let suite = "ModelRoutingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Cannot create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ModelRoutingConfiguration(mode: .perRole, assignments: [.review: primary])
        let chat = ModelRoutingConfiguration(mode: .single, assignments: [.vision: primary])
        let store = ModelRoutingStore(defaults: defaults)
        store.saveProject(project, projectRoot: "/tmp/project")
        store.saveChat(chat, sessionID: "chat-1")
        #expect(store.configuration(projectRoot: "/tmp/project", sessionID: "chat-1") == chat)
        #expect(store.configuration(projectRoot: "/tmp/project", sessionID: "chat-2") == project)
        store.clearChat(sessionID: "chat-1")
        #expect(store.configuration(projectRoot: "/tmp/project", sessionID: "chat-1") == project)
        #expect(store.configuration(projectRoot: "/tmp/other", sessionID: "chat-2") == nil)
    }

    @Test func catalogValidationUsesActualProviderModelLists() {
        let assignment = ModelAssignment(providerID: "beta", modelID: "two")
        #expect(throws: ModelRoutingError.unavailableProvider(providerID: "beta")) {
            try ModelRouteResolver.validate(
                assignment,
                role: .vision,
                availableModels: ["alpha": ["one"]]
            )
        }
        #expect(throws: ModelRoutingError.unavailableModel(role: .vision, modelID: "two")) {
            try ModelRouteResolver.validate(
                assignment,
                role: .vision,
                availableModels: ["beta": ["other"]]
            )
        }
    }
}
