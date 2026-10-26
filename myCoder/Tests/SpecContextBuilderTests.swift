import Testing
import Foundation
@testable import myCoder

@Suite("Spec context builder")
struct SpecContextBuilderTests {

    private func makeProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-spec-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (path, content) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return dir
    }

    @Test("Includes the tree and key manifests")
    func includesTreeAndKeyFiles() throws {
        let dir = try makeProject([
            "README.md": "# Notes\n\nOffline notes.",
            "Package.swift": "// swift-tools-version: 6.0",
            "src/main.swift": "print(\"hi\")"
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let context = SpecContextBuilder.build(projectPath: dir.path)
        #expect(context.contains("README.md"))
        #expect(context.contains("Package.swift"))
        #expect(context.contains("src/main.swift"))
        #expect(context.contains("Offline notes."))
        #expect(context.contains("swift-tools-version"))
    }

    @Test("Skips secrets, dependencies and build output")
    func skipsSecretsAndDependencies() throws {
        let dir = try makeProject([
            "README.md": "# App",
            ".env": "SECRET=1",
            "config/.env.local": "SECRET=2",
            "secrets.json": "{\"token\":\"x\"}",
            "certs/server.pem": "key",
            "node_modules/pkg/index.js": "module.exports = 1",
            ".build/debug/app": "binary",
            "src/app.swift": "let x = 1"
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let context = SpecContextBuilder.build(projectPath: dir.path)
        #expect(context.contains("src/app.swift"))
        #expect(!context.contains("SECRET=1"))
        #expect(!context.contains("SECRET=2"))
        #expect(!context.contains("secrets.json"))
        #expect(!context.contains("server.pem"))
        #expect(!context.contains("node_modules"))
        #expect(!context.contains(".build"))
    }

    @Test("Empty folders produce no context")
    func emptyFolder() throws {
        let dir = try makeProject([:])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SpecContextBuilder.build(projectPath: dir.path).isEmpty)
    }

    @Test("Output is deterministic and bounded")
    func deterministicAndBounded() throws {
        var files: [String: String] = ["README.md": String(repeating: "a", count: 20_000)]
        for index in 0..<20 {
            files["Sources/File\(index).swift"] = String(repeating: "b", count: 2_000)
        }
        let dir = try makeProject(files)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = SpecContextBuilder.build(projectPath: dir.path, maxCharacters: 5_000)
        let second = SpecContextBuilder.build(projectPath: dir.path, maxCharacters: 5_000)
        #expect(first == second)
        #expect(first.count <= 5_000 + 40)
    }
}
