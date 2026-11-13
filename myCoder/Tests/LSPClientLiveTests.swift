import Foundation
import Testing
@testable import myCoder

/// Live language-server integration: launches the real SourceKit-LSP binary
/// and checks that a type error produces a diagnostic and that definition /
/// hover resolve inside a standalone Swift file. Skipped automatically when
/// the toolchain is absent or `MYCODER_SKIP_LIVE_LSP` is set.
enum LSPLiveEnvironment {
    static var enabled: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")
            && ProcessInfo.processInfo.environment["MYCODER_SKIP_LIVE_LSP"] == nil
    }
}

@Suite("LSP client — live sourcekit-lsp")
struct LSPClientLiveTests {

    @Test(.enabled(if: LSPLiveEnvironment.enabled), .timeLimit(.minutes(3)))
    func reportsDiagnosticsAndNavigates() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("mycoder-lsp-live-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let broken = root.appendingPathComponent("Broken.swift")
        try "let value: Int = \"not an int\"\n"
            .write(to: broken, atomically: true, encoding: .utf8)
        let good = root.appendingPathComponent("Good.swift")
        try """
        struct Greeter {
            func greet(name: String) -> String { "Hello, \\(name)" }
        }
        let greeter = Greeter()
        let message = greeter.greet(name: "world")
        """.write(to: good, atomically: true, encoding: .utf8)

        let client = LSPClient(configuration: .init(
            serverID: "sourcekit-lsp",
            executable: "/usr/bin/xcrun",
            arguments: ["sourcekit-lsp"],
            projectRoot: root.path,
            requestTimeout: 30,
            diagnosticsTimeout: 90
        ))
        try await client.start()

        do {
            let report = await client.diagnostics(forPath: broken.path, timeout: 90)
            #expect(!report.timedOut, "sourcekit-lsp did not publish diagnostics")
            #expect(report.diagnostics.contains { ($0.severity ?? 0) == 1 },
                    "expected a type error, got \(report.diagnostics)")

            // `greet` starts at column 23 of line 5.
            let definition = try await client.definition(path: good.path, line: 5, column: 23)
            #expect(definition.contains("Good.swift"))

            let hover = try await client.hover(path: good.path, line: 5, column: 23)
            #expect(hover.lowercased().contains("greet"))
        } catch {
            await client.shutdown()
            throw error
        }
        await client.shutdown()
    }
}
