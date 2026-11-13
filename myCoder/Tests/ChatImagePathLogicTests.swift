import Foundation
import Testing
@testable import myCoder

/// TDD for plan item 13.1: image paths from message text are extracted as
/// inline previews (bounded thumbnails) instead of plain text.
@Suite("Chat image path extraction — inline previews")
struct ChatImagePathLogicTests {

    @Test("Known image extensions are recognized")
    func imageExtensions() {
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "tiff", "svg"] {
            #expect(ChatImagePathLogic.imageExtensions.contains(ext), "missing \(ext)")
        }
        #expect(!ChatImagePathLogic.imageExtensions.contains("html"))
        #expect(!ChatImagePathLogic.imageExtensions.contains("md"))
    }

    @Test("Relative image path resolves against the project root")
    func relativeImagePath() throws {
        let root = try makeProject(files: ["shot.png", "docs/plan.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ChatImagePathLogic.extractImagePaths(
            from: "Смотри скриншот shot.png и документ docs/plan.md",
            projectRoot: root.path
        )
        #expect(paths == [root.appendingPathComponent("shot.png").path])
    }

    @Test("Nonexistent files and non-images are ignored")
    func ignoresMissingAndNonImages() throws {
        let root = try makeProject(files: ["a.png"])
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ChatImagePathLogic.extractImagePaths(
            from: "missing.png a.html a.png",
            projectRoot: root.path
        )
        #expect(paths == [root.appendingPathComponent("a.png").path])
    }

    @Test("Duplicate paths are deduplicated and result is bounded")
    func dedupAndBound() throws {
        let root = try makeProject(files: ["a.png", "b.png", "c.png", "d.png", "e.png", "f.png", "g.png"])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = (0..<4).map { "a.png photo\($0)" }.joined(separator: " ")
        let paths = ChatImagePathLogic.extractImagePaths(from: text, projectRoot: root.path, limit: 3)
        #expect(paths.count == 1)
        #expect(paths == [root.appendingPathComponent("a.png").path])
    }

    @Test("Empty text yields no paths")
    func emptyText() {
        #expect(ChatImagePathLogic.extractImagePaths(from: "", projectRoot: nil).isEmpty)
    }

    // MARK: - Helpers

    private func makeProject(files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        return root
    }
}
