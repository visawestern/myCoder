import Foundation
import Testing
@testable import myCoder

@Suite("Turn evidence")
struct TurnEvidenceTests {
    @Test func projectInstructionsAndMatchingSkillAreLoaded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skills/swift"), withIntermediateDirectories: true)
        try "Use TDD".write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "Swift concurrency review".write(to: root.appendingPathComponent("skills/swift/SKILL.md"), atomically: true, encoding: .utf8)
        let sections = TurnEvidence.instructions(projectPath: root.path, query: "swift", skillsDirectory: root.appendingPathComponent("skills"))
        #expect(sections.contains { $0.body.contains("Use TDD") })
        #expect(sections.contains { $0.body.contains("Swift concurrency review") })
        #expect(!TurnEvidence.instructions(projectPath: "", query: "unrelated", skillsDirectory: root.appendingPathComponent("skills")).contains { $0.body.contains("Swift concurrency review") })
    }
    @Test func graphIncludesRealNeighbors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let code = "func load() {}\nfunc reload() { load() }\n"
        try code.write(to: root.appendingPathComponent("Store.swift"), atomically: true, encoding: .utf8)
        let records = [FileIndexRecord(path: "Store.swift", hash: "test", size: code.utf8.count, lastModified: 0, language: "swift", searchableText: code)]
        let section = try TurnEvidence.graph(projectPath: root.path, query: "reload", records: records)
        #expect(section.body.contains("reload"))
        #expect(section.body.contains("load"))
        #expect(section.body.contains("Store.swift"))
    }
}
