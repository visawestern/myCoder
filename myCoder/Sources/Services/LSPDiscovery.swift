import Foundation

/// A language-server (LSP) launch spec: a name the agent can pick from, the
/// binary to run, its arguments, and the languages it serves.
///
/// User directive 2026-11-08: give the agent local language servers to choose
/// from. This file is the catalog + discovery layer — it knows the standard
/// servers and which are actually installed on this machine.
struct LSPServerSpec: Equatable, Codable, Sendable {
    let id: String
    let name: String
    let command: String
    var args: [String]
    var languages: [String]
}

enum LSPDiscovery {

    /// The standard, well-known language servers the app knows how to launch.
    /// `command` is the binary on PATH (or a wrapper like `xcrun` for
    /// SourceKit-LSP). Discovery only reports servers whose executable
    /// resolves; the list is a catalog, never a claim that each is installed.
    static let standardServers: [LSPServerSpec] = [
        LSPServerSpec(id: "sourcekit-lsp", name: "SourceKit-LSP",
                      command: "xcrun", args: ["sourcekit-lsp"],
                      languages: ["Swift", "Objective-C"]),
        LSPServerSpec(id: "typescript-language-server", name: "TypeScript Language Server",
                      command: "typescript-language-server", args: ["--stdio"],
                      languages: ["TypeScript", "JavaScript"]),
        LSPServerSpec(id: "pyright", name: "Pyright",
                      command: "pyright-langserver", args: ["--stdio"],
                      languages: ["Python"]),
        LSPServerSpec(id: "rust-analyzer", name: "rust-analyzer",
                      command: "rust-analyzer", args: [],
                      languages: ["Rust"]),
        LSPServerSpec(id: "gopls", name: "gopls",
                      command: "gopls", args: ["serve"],
                      languages: ["Go"]),
        LSPServerSpec(id: "clangd", name: "clangd",
                      command: "clangd", args: [],
                      languages: ["C", "C++", "Objective-C"]),
        LSPServerSpec(id: "jdtls", name: "Eclipse JDT Language Server",
                      command: "jdtls", args: [],
                      languages: ["Java"]),
        LSPServerSpec(id: "vscode-html", name: "vscode-html-language-server",
                      command: "vscode-html-language-server", args: ["--stdio"],
                      languages: ["HTML"]),
        LSPServerSpec(id: "vscode-css", name: "vscode-css-language-server",
                      command: "vscode-css-language-server", args: ["--stdio"],
                      languages: ["CSS", "SCSS", "Less"]),
        LSPServerSpec(id: "vscode-json", name: "vscode-json-language-server",
                      command: "vscode-json-language-server", args: ["--stdio"],
                      languages: ["JSON"]),
        LSPServerSpec(id: "zls", name: "zls (Zig)",
                      command: "zls", args: [],
                      languages: ["Zig"])
    ]

    /// Resolve a launch command to an executable path. Mirrors `which`:
    /// a literal path wins if executable, then each PATH component.
    /// `xcrun` is special-cased: it is always present on macOS and its
    /// argument carries the real tool (e.g. `xcrun sourcekit-lsp`).
    static func resolveExecutable(_ command: String,
                                  searchPath: String?,
                                  fileManager: FileManager) -> String? {
        if command == "xcrun" {
            return "/usr/bin/xcrun"
        }
        if command.contains("/") {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: command, isDirectory: &isDir),
                  !isDir.boolValue,
                  fileManager.isExecutableFile(atPath: command) else { return nil }
            return command
        }
        let components = (searchPath ?? "").split(separator: ":").map(String.init)
        for component in components {
            let candidate = (component as NSString).appendingPathComponent(command)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDir),
                  !isDir.boolValue,
                  fileManager.isExecutableFile(atPath: candidate) else { continue }
            return candidate
        }
        return nil
    }

    /// Which of the given specs are actually installed (executable resolves).
    static func available(specs: [LSPServerSpec] = standardServers,
                          searchPath: String? = nil,
                          fileManager: FileManager = .default) -> [LSPServerSpec] {
        let path = searchPath ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        return specs.filter { resolveExecutable($0.command, searchPath: path, fileManager: fileManager) != nil }
    }
}
