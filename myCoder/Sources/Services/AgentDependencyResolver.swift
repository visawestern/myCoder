import Foundation

/// Runtime/system requirements resolution for agent resources (plan Section 3
/// Блок 2 / Section 4 Блок 2 / Section 4 п.17). Splits a catalog requirement
/// string into a typed check and evaluates it against the live machine.
enum AgentDependencyResolver {

    /// How a single catalog requirement string should be interpreted.
    enum RequirementKind: Equatable {
        /// Well-known runtime binary, optionally version-constrained, e.g. "node>=18".
        case runtime(binary: String, constraint: String?)
        /// An MCP server id that should already be configured, e.g. "playwright-mcp".
        case mcp(serverID: String)
    }

    /// Result of evaluating one requirement on the current machine.
    struct CheckResult: Equatable {
        let requirement: String
        let kind: RequirementKind
        let isSatisfied: Bool
        /// Human-readable summary, e.g. "node v24.7.0" or "playwright-mcp not installed".
        let detail: String
    }

    /// Classify a requirement string. "node>=18" / "python3" / "docker" are
    /// runtime; anything ending in "-mcp" or matching a known server id is MCP.
    static func classify(_ requirement: String) -> RequirementKind {
        let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mcpID = mcpServerID(in: trimmed) {
            return .mcp(serverID: mcpID)
        }
        let parts = splitVersionConstraint(trimmed)
        return .runtime(binary: parts.binary, constraint: parts.constraint)
    }

    /// Resolve a skill's declared dependencies. MCP-id dependencies that are not
    /// currently installed surface as unsatisfied; runtime binaries are probed
    /// via `checkBinary`.
    static func resolve(skill: CatalogSkillItem,
                        homeDirectory: URL,
                        checkBinary: (String) -> Bool = Self.runtimeBinaryPresent) -> [CheckResult] {
        skill.dependencyIDs.map { resolve(requirement: $0, homeDirectory: homeDirectory, checkBinary: checkBinary) }
    }

    /// Resolve an MCP server's declared `requires` (runtime binaries only).
    static func resolve(server: CatalogMCPServerItem,
                        homeDirectory: URL,
                        checkBinary: (String) -> Bool = Self.runtimeBinaryPresent) -> [CheckResult] {
        server.requirementIDs.map { resolve(requirement: $0, homeDirectory: homeDirectory, checkBinary: checkBinary) }
    }

    static func resolve(requirement: String,
                        homeDirectory: URL,
                        checkBinary: (String) -> Bool = Self.runtimeBinaryPresent) -> CheckResult {
        let kind = classify(requirement)
        switch kind {
        case .runtime(let binary, let constraint):
            let present = checkBinary(binary)
            let version = present ? Self.runtimeVersion(binary) : nil
            let detail: String
            if let version = version, let constraint = constraint {
                detail = "\(binary) \(version) (\(constraint))"
            } else if let version = version {
                detail = "\(binary) \(version)"
            } else {
                detail = "\(binary) not found"
            }
            return CheckResult(requirement: requirement, kind: kind,
                               isSatisfied: present, detail: detail)
        case .mcp(let serverID):
            let installed = Self.mcpServerInstalled(serverID, homeDirectory: homeDirectory)
            return CheckResult(requirement: requirement, kind: kind,
                               isSatisfied: installed,
                               detail: installed ? "\(serverID) installed" : "\(serverID) not installed")
        }
    }

    // MARK: - Runtime probing

    /// Whether the binary is reachable on PATH (uses `which`).
    static func runtimeBinaryPresent(_ binary: String) -> Bool {
        guard !binary.isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", binary]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Best-effort version string for a binary (`binary --version`), trimmed.
    static func runtimeVersion(_ binary: String) -> String? {
        guard !binary.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binary, "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    // MARK: - MCP probe

    static func mcpServerInstalled(_ id: String, homeDirectory: URL) -> Bool {
        AgentResourceLibraryLogic.isMCPInstalled(id: id, homeDirectory: homeDirectory)
    }

    // MARK: - Parsing helpers

    /// Returns the MCP server id when the requirement names an MCP server
    /// (trailing "-mcp" suffix or explicit server name), else nil.
    private static func mcpServerID(in requirement: String) -> String? {
        let lower = requirement.lowercased()
        if lower.hasSuffix("-mcp") {
            return String(requirement.dropLast(4))
        }
        // Known catalog server ids (exact name, e.g. "playwright", "figma").
        let known = ["playwright", "puppeteer", "chrome-devtools", "figma", "github",
                     "lazyweb", "pablooo", "context7", "filesystem", "fetch", "memory",
                     "sequential-thinking", "time", "everything", "git", "sqlite",
                     "postgres", "slack", "google-drive", "brave-search", "redis",
                     "stripe", "linear", "browserbase", "shell", "everart"]
        if known.contains(lower) {
            return requirement
        }
        return nil
    }

    /// Split "node>=18" into ("node", ">=18"); "python3" -> ("python3", nil).
    private static func splitVersionConstraint(_ requirement: String) -> (binary: String, constraint: String?) {
        guard let opRange = requirement.range(of: ">=") ?? requirement.range(of: ">") ?? requirement.range(of: "==") else {
            return (requirement, nil)
        }
        let binary = String(requirement[..<opRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let constraint = String(requirement[opRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
        guard !binary.isEmpty else { return (requirement, nil) }
        return (binary, constraint)
    }
}
