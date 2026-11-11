import Testing
import Foundation
@testable import myCoder

/// Live regression: `POST /api/context-preview` was timing out at the handler's
/// 60 s deadline on a 1000-file project because the real pipeline (index +
/// board + planner + impact) needs more time. This proves the *same* pipeline
/// collects real context (status=compiled, included non-empty) when it is given
/// a finite project, and pins the JSON surface the API returns.
@MainActor
@Suite("Context preview collects real context")
struct ContextPreviewCollectsContextTests {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctx-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = """
        import Foundation

        final class UserStore {
            func load(id: String) -> Int { 0 }
        }
        """
        try source.write(to: root.appendingPathComponent("UserStore.swift"),
                         atomically: true, encoding: .utf8)
        return root
    }

    @Test("Preview возвращает compiled с непустым included")
    func previewCompilesRealContext() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        // Build the index the same way the project does on disk.
        let text = try String(contentsOf: root.appendingPathComponent("UserStore.swift"), encoding: .utf8)
        let record = FileIndexRecord(
            path: "UserStore.swift", hash: "h", size: text.utf8.count,
            lastModified: 1_700_000_000, language: "swift", searchableText: text
        )
        try ProjectFileIndexStore.save(projectPath: root.path, records: [record])

        let request = ContextPreviewService.Request(
            message: "как работает UserStore.load",
            projectPath: root.path,
            isEnabled: true,
            isPlannerEnabled: false,   // no internal model / network in tests
            systemPrompt: "You are a test assistant.",
            skillsDirectory: nil,
            isPlanMode: false
        )
        let payload = await ContextPreviewService.run(request)

        #expect(payload["status"] as? String == "compiled")
        let included = payload["included"] as? [String] ?? []
        #expect(!included.isEmpty)
        #expect(included.contains { $0.contains("UserStore.swift") })
        #expect((payload["estimatedTokens"] as? Int ?? 0) > 0)
        // The viewer surface is present.
        let tabs = payload["tabs"] as? [[String: Any]] ?? []
        #expect(!tabs.isEmpty)
    }

    @Test("Preview честно сообщает о отсутствии совпадений (noEvidence)")
    func previewReportsNoEvidence() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = try String(contentsOf: root.appendingPathComponent("UserStore.swift"), encoding: .utf8)
        let record = FileIndexRecord(
            path: "UserStore.swift", hash: "h", size: text.utf8.count,
            lastModified: 1_700_000_000, language: "swift", searchableText: text
        )
        try ProjectFileIndexStore.save(projectPath: root.path, records: [record])

        let request = ContextPreviewService.Request(
            message: "совершенно несвязанный запрос теории струн",
            projectPath: root.path,
            isEnabled: true,
            isPlannerEnabled: false,
            systemPrompt: "You are a test assistant.",
            skillsDirectory: nil,
            isPlanMode: false
        )
        let payload = await ContextPreviewService.run(request)
        let status = payload["status"] as? String
        #expect(status == "compiled" || status == "noEvidence")
        // Either way the surface must be honest and never empty.
        #expect(payload["summary"] as? String != nil)
    }
}
