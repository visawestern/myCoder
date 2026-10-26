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
