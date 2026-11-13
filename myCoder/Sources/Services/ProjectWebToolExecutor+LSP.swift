import Foundation

/// LSP integration for the emulated tool executor.
///
/// Two behaviors live here, both kept out of the main executor file so it
/// stays inside the 600-line module budget:
///   * automatic diagnostics appended to a successful write/edit of a code
///     file (only when the turn enabled `automaticDiagnostics`);
///   * the explicit `lsp` tool: diagnostics, definition, references, hover
///     and completion from the real language server.
extension ProjectWebToolExecutor {

    /// Result of a successful `write_file`.
    /// Input: absolute path, display path, written character count.
    /// Output: the usual ok line plus diagnostics when enabled.
    /// Dependencies: `LSPManager`.
    func fileWriteResult(path: String, displayPath: String, contentCount: Int) async -> String {
        let base = "ok: wrote \(contentCount) chars to \(displayPath)"
        return base + (await diagnosticsSuffix(path: path))
    }

    /// Result of a successful `edit_file`.
    /// Input: absolute path + display path. Output: the usual ok line plus
    /// diagnostics when enabled. Dependencies: `LSPManager`.
    func fileEditResult(path: String, displayPath: String) async -> String {
        "ok: edited \(displayPath)" + (await diagnosticsSuffix(path: path))
    }

    /// Language-server check appended to a file mutation.
    /// Input: absolute path. Output: "\n\n<report>" or "" when automatic
    /// diagnostics are off or no server covers the file. Dependencies:
    /// `LSPManager` + the enabled server registry.
    private func diagnosticsSuffix(path: String) async -> String {
        guard automaticDiagnostics else { return "" }
        guard let summary = await LSPManager.shared.diagnosticsSummary(
            path: path,
            projectRoot: projectRoot,
            timeout: 15
        ) else { return "" }
        return "\n\n" + summary
    }

    /// Execute the `lsp` tool.
    /// Input: a canonicalized `lsp` call (`operation`, `path`, optional
    /// 1-based `line`/`column`). Output: formatted server answer or an
    /// actionable error. Dependencies: `LSPManager`, `url(for:)`.
    func lspToolResult(call: WebToolCall) async -> String {
        guard let rawOperation = call.arguments["operation"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !rawOperation.isEmpty else {
            return "error: missing operation (diagnostics|definition|references|hover|completion)"
        }
        guard let path = call.arguments["path"], !path.isEmpty else {
            return "error: missing path"
        }
        let line = call.arguments["line"].flatMap { Int($0.filter(\.isNumber)) } ?? 1
        let column = call.arguments["column"].flatMap { Int($0.filter(\.isNumber)) } ?? 1
        return await LSPManager.shared.perform(
            operation: rawOperation.lowercased(),
            path: url(for: path).path,
            projectRoot: projectRoot,
            line: max(1, line),
            column: max(1, column)
        )
    }
}
