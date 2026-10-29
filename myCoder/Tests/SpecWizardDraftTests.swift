import Testing
import Foundation
@testable import myCoder

@Suite("Spec wizard draft")
struct SpecWizardDraftTests {

    @Test("Checklist starts empty and does not count upcoming phases")
    func emptyDraft() {
        let draft = SpecWizardDraft()
        let items = SpecWizardChecklistLogic.items(for: draft)
        #expect(items.map(\.id) == [.models, .brief, .interview, .specification, .decomposition])
        #expect(items[0].state == .pending)
        #expect(items[1].state == .pending)
        #expect(items[2].state == .upcoming)
        #expect(items[3].state == .upcoming)
        #expect(items[4].state == .upcoming)
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 0)
    }

    @Test("Progress reflects real draft data only")
    func progressFromDraft() {
        var draft = SpecWizardDraft()
        draft.goal = "Ship a macOS app"
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 0)

        draft.plannerModel = "planner"
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 0)

        draft.plannerModel = "planner"
        draft.coderModel = "coder"
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 1.0 / 5.0)

        draft.stack = "SwiftUI"
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 2.0 / 5.0)

        draft.interviewComplete = true
        draft.specVersion = 1
        draft.decompositionNodeCount = 3
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 1)

        let items = SpecWizardChecklistLogic.items(for: draft)
        #expect(items.first(where: { $0.id == .models })?.state == .done)
        #expect(items.first(where: { $0.id == .brief })?.state == .done)
    }

    @Test("Whitespace-only input is not considered done")
    func whitespaceIsNotDone() {
        var draft = SpecWizardDraft()
        draft.goal = "   \n"
        draft.stack = "\t"
        draft.plannerModel = " "
        draft.coderModel = "coder"
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 0)
        #expect(SpecWizardChecklistLogic.canFinish(draft) == false)
    }

    @Test("Interview, spec and decomposition drive their checklist rows")
    func phasesDriveChecklist() {
        var draft = SpecWizardDraft()
        draft.plannerModel = "planner"
        draft.coderModel = "coder"
        draft.goal = "Goal"
        draft.stack = "Swift"
        draft.interviewComplete = true
        draft.specVersion = 2
        draft.decompositionNodeCount = 4

        let items = SpecWizardChecklistLogic.items(for: draft)
        #expect(items.allSatisfy { $0.state == .done })
        #expect(SpecWizardChecklistLogic.canFinish(draft))
        #expect(draft.step == .ready)
    }

    @Test("A restart restores the exact step the user was looking at")
    func activeStepIsRestored() {
        var draft = SpecWizardDraft()
        draft.plannerModel = "planner"
        draft.coderModel = "coder"
        draft.goal = "Goal"
        draft.stack = "Swift"
        draft.interviewComplete = true
        draft.specVersion = 2
        draft.decompositionNodeCount = 3

        // Data unlocks every step, the user sits on the interview.
        draft.activeStep = .interview
        #expect(draft.furthestStep == .ready)
        #expect(draft.visibleStep == .interview)

        // Going back to the very first step is allowed and survives.
        draft.activeStep = .setup
        #expect(draft.visibleStep == .setup)

        // Checklist availability follows the data, not the current view.
        #expect(SpecWizardChecklistLogic.items(for: draft).allSatisfy { $0.state == .done })
        #expect(SpecWizardChecklistLogic.progress(for: draft) == 1)
    }

    @Test("A step the data has not unlocked cannot be shown")
    func activeStepClampsToFurthest() {
        var draft = SpecWizardDraft()
        draft.plannerModel = "planner"
        draft.coderModel = "coder"
        draft.goal = "Goal"
        draft.stack = "Swift"
        draft.activeStep = .decomposition

        #expect(draft.furthestStep == .interview)
        #expect(draft.visibleStep == .interview)
    }

    @Test("A draft without a stored position opens at the furthest reached step")
    func legacyDraftWithoutActiveStepOpensAtFurthest() {
        var draft = SpecWizardDraft()
        draft.plannerModel = "planner"
        draft.coderModel = "coder"
        draft.goal = "Goal"
        draft.stack = "Swift"
        draft.interviewComplete = true

        #expect(draft.activeStep == nil)
        #expect(draft.visibleStep == .specification)
    }

    @Test("The stored position round-trips through JSON")
    func activeStepRoundTrips() throws {
        var draft = SpecWizardDraft()
        draft.goal = "Goal"
        draft.stack = "Swift"
        draft.plannerModel = "planner"
        draft.coderModel = "coder"
        draft.activeStep = .setup

        let restored = try JSONDecoder().decode(
            SpecWizardDraft.self,
            from: JSONEncoder().encode(draft)
        )
        #expect(restored.activeStep == .setup)
        #expect(restored == draft)
    }

    @Test("Checklist rows map to the wizard step they open")
    func checklistRowsMapToSteps() {
        #expect(SpecWizardChecklistLogic.step(for: .models) == .setup)
        #expect(SpecWizardChecklistLogic.step(for: .brief) == .setup)
        #expect(SpecWizardChecklistLogic.step(for: .interview) == .interview)
        #expect(SpecWizardChecklistLogic.step(for: .specification) == .specification)
        #expect(SpecWizardChecklistLogic.step(for: .decomposition) == .decomposition)
    }

    @Test("An unknown stored position falls back to the furthest reached step")
    func unknownActiveStepIsIgnored() throws {
        let json = #"{"status":"draft","goal":"G","stack":"S","plannerModel":"p","coderModel":"c","interviewComplete":true,"activeStep":"teleport"}"#
        let draft = try JSONDecoder().decode(SpecWizardDraft.self, from: Data(json.utf8))
        #expect(draft.activeStep == nil)
        #expect(draft.visibleStep == .specification)
    }

    @Test("Legacy draft JSON without new fields still decodes")
    func legacyDraftDecodes() throws {
        let legacy = """
        {"status":"draft","goal":"G","stack":"S","constraints":"C","plannerModel":"p","coderModel":"c","updatedAt":1}
        """.data(using: .utf8)!
        let draft = try JSONDecoder().decode(SpecWizardDraft.self, from: legacy)
        #expect(draft.step == .interview)
        #expect(draft.interviewComplete == false)
        #expect(draft.specVersion == 0)
        #expect(draft.decompositionNodeCount == 0)
        #expect(draft.goal == "G")
        #expect(draft.plannerProviderID == "")
        #expect(draft.coderProviderID == "")
    }

    @Test("Provider ids survive an encode/decode round-trip")
    func providerIDsRoundTrip() throws {
        var draft = SpecWizardDraft()
        draft.plannerModel = "gpt-4o"
        draft.coderModel = "gpt-4o"
        draft.plannerProviderID = "custom-1"
        draft.coderProviderID = "custom-2"
        let data = try JSONEncoder().encode(draft)
        let restored = try JSONDecoder().decode(SpecWizardDraft.self, from: data)
        #expect(restored == draft)
        #expect(restored.plannerProviderID == "custom-1")
        #expect(restored.coderProviderID == "custom-2")
    }

    @Test("Draft round-trips through the project metadata store")
    func draftPersistsInProjectDatabase() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-spec-wizard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            ProjectDatabaseManager.evictProject(projectPath: dir.path)
            try? FileManager.default.removeItem(atPath: dir.path)
        }

        let store = try ProjectDatabaseManager.manager(forProjectPath: dir.path)
        var draft = SpecWizardDraft()
        draft.goal = "Goal"
        draft.stack = "Swift"
        draft.plannerModel = "planner"
        draft.coderModel = "coder"
        draft.status = .draft

        let data = try JSONEncoder().encode(draft)
        try store.setMetadataValue(String(decoding: data, as: UTF8.self), forKey: "spec_wizard_draft")

        let raw = try #require(try store.metadataValue(forKey: "spec_wizard_draft"))
        let restored = try JSONDecoder().decode(SpecWizardDraft.self, from: Data(raw.utf8))
        #expect(restored == draft)

        try store.setMetadataValue("forced", forKey: "spec_wizard_status")
        #expect(try store.metadataValue(forKey: "spec_wizard_status") == "forced")
    }
}
