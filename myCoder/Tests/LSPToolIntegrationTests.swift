import Foundation
import Testing
@testable import myCoder

/// The agent-facing `lsp` tool: alias canonicalization, read-only access and
/// the hermetic paths (missing arguments, automatic diagnostics disabled).
@Suite("LSP tool integration")
struct LSPToolIntegrationTests {

    @Test func canonicalizesOperationPathLineAndColumnAliases() {
        let normalized = WebToolProtocolEmulator.normalizedArguments(
            for: .lsp,
            from: ["op": "definition", "file": "Sources/A.swift", "start_line": "12", "col": "4"]
        )
        #expect(normalized["operation"] == "definition")
        #expect(normalized["path"] == "Sources/A.swift")
        #expect(normalized["line"] == "12")
        #expect(normalized["column"] == "4")
    }

    @Test func everyEmulatedToolCanonicalizesFromItsOwnRawValue() {
        // Regression: adding an enum case without its canonical alias crashed
        // `parseTruncatedToolCallStub` on a force unwrap (full suite 2026-11-13).
        for tool in WebEmulatedTool.allCases {
            #expect(
                WebToolProtocolEmulator.canonicalToolName(tool.rawValue) == tool.rawValue,
                "missing canonical alias for \(tool.rawValue)"
            )
        }
        #expect(WebToolProtocolEmulator.canonicalToolName("language_server") == "lsp")
    }

    @Test func lspIsReadOnlyAndBoundToItsPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lsp-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let call = WebToolCall(name: "lsp", arguments: ["operation": "hover", "path": "A.swift"])
        #expect(WebToolAccessGate.permission(
            for: call, accessLevel: .askBeforeChanges, projectRoot: root.path
        ) == .allow)

        // A path outside the project still asks before the tool runs.
        let outside = WebToolCall(name: "lsp", arguments: ["operation": "hover", "path": "/etc/hosts"])
        #expect(WebToolAccessGate.permission(
            for: outside, accessLevel: .askBeforeChanges, projectRoot: root.path
        ) == .requireApproval)
    }

    @Test func missingOperationReturnsActionableError() async {
        let executor = ProjectWebToolExecutor(projectRoot: "/tmp", accessLevel: .fullAccess)
        let result = await executor.execute(WebToolCall(name: "lsp", arguments: ["path": "A.swift"]))
        #expect(result.contains("missing operation"))
        #expect(result.contains("diagnostics"))
    }

    @Test func missingPathReturnsActionableError() async {
        let executor = ProjectWebToolExecutor(projectRoot: "/tmp", accessLevel: .fullAccess)
        let result = await executor.execute(WebToolCall(
            name: "lsp", arguments: ["operation": "definition"]
        ))
        #expect(result.contains("missing path"))
    }

    @Test func writeStaysHermeticWhenAutomaticDiagnosticsAreOff() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lsp-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executor = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await executor.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "A.swift", "content": "let x = 1\n"]
        ))
        // No language server is launched and no diagnostics suffix is added.
        #expect(result == "ok: wrote 10 chars to A.swift")
    }
}
