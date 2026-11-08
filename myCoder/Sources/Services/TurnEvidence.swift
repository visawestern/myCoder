import Foundation

/// Evidence that belongs to EVERY turn but was missing from the pack:
/// the project's own instructions (AGENTS.md / PERCH.md / CLAUDE.md), the
/// skill whose SKILL.md actually matches the request, and the real code-graph
/// neighbours of the symbols the user named.
///
/// Everything here is read from disk and filtered by the user's own words —
/// no model, no invented content. When a source is absent the section is
/// absent, so the pack never claims evidence it does not have.
enum TurnEvidence {

    /// Instruction files, in priority order. The first one that exists wins:
    /// two competing rule sets in one pack would contradict each other.
    static let instructionFileNames = ["AGENTS.md", "PERCH.md", "CLAUDE.md", "miagents.md"]

    static let maxInstructionBytes = 4_000
    static let maxSkillBytes = 2_000
    static let maxSkills = 3
    static let maxGraphHits = 6

    // MARK: - Instructions + skills

    /// Project instructions plus the single best matching skill. Returns an
    /// empty array when neither exists — the caller then adds no section.
    static func instructions(projectPath: String,
                             query: String,
                             skillsDirectory: URL?) -> [ContextSection] {
        var sections: [ContextSection] = []
        if let project = projectInstructions(projectPath: projectPath) {
            sections.append(project)
        }
        sections.append(contentsOf: matchingSkills(query: query, skillsDirectory: skillsDirectory))
        return sections
    }

    /// The project's rule file, bounded. A file that is unreadable is skipped
    /// rather than reported as an empty instruction set.
    static func projectInstructions(projectPath: String) -> ContextSection? {
        guard !projectPath.isEmpty else { return nil }
        let root = URL(fileURLWithPath: projectPath)
        for name in instructionFileNames {
            let url = root.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return ContextSection(
                title: "Инструкции проекта (\(name))",
                body: bounded(trimmed, bytes: maxInstructionBytes)
            )
        }
        return nil
    }

    /// Skills whose name or SKILL.md body matches the request. Ranking is by
    /// how many query terms hit, so a skill named after the language wins over
    /// one that merely mentions it once.
    static func matchingSkills(query: String, skillsDirectory: URL?) -> [ContextSection] {
        guard let skillsDirectory else { return [] }
        let terms = queryTerms(query)
        guard !terms.isEmpty else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: skillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var scored: [(score: Int, id: String, body: String)] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let skillFile = entry.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }
            let id = entry.lastPathComponent
            let haystack = (id + "\n" + text).lowercased()
            let score = terms.reduce(0) { partial, term in
                partial + (haystack.contains(term) ? 1 : 0)
            }
            guard score > 0 else { continue }
            scored.append((score, id, text))
        }
        return scored
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.id < right.id
            }
            .prefix(maxSkills)
            .map { entry in
                ContextSection(
                    title: "Скилл: \(entry.id)",
                    body: bounded(entry.body.trimmingCharacters(in: .whitespacesAndNewlines),
                                  bytes: maxSkillBytes)
                )
            }
    }

    struct SkillEntry {
        let id: String
        let summary: String
    }

    /// Catalog cap. The user installed the full OpenCode skill set (100+),
    /// so 64 was too small — the planner could not even see all installed
    /// skills. Bumped to 128.
    static let maxSkillCatalog = 128

    static func skillCatalog(directory: URL) -> [SkillEntry] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory,
                       includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let text = try? String(contentsOf: url.appendingPathComponent("SKILL.md"), encoding: .utf8) else { return nil }
            return SkillEntry(id: url.lastPathComponent, summary: String(text.prefix(240)))
        }.prefix(maxSkillCatalog).map { $0 }
    }

    static func selectedSkills(ids: [String], directory: URL?) -> [ContextSection] {
        guard let directory else { return [] }
        let catalog = Set(skillCatalog(directory: directory).map(\.id))
        return Array(Set(ids)).sorted().filter { catalog.contains($0) }.prefix(maxSkills).compactMap { id in
            guard let text = try? String(contentsOf: directory.appendingPathComponent(id).appendingPathComponent("SKILL.md"), encoding: .utf8) else { return nil }
            return ContextSection(title: "Скилл: \(id)", body: bounded(text, bytes: maxSkillBytes))
        }
    }

    // MARK: - Code graph

    /// Real graph evidence: the symbols matching the request plus their
    /// neighbours (who calls them, what they call, what tests them). This is
    /// the part the flat context board cannot give — it has symbols but no
    /// edges.
    static func graph(projectPath: String,
                      query: String,
                      records: [FileIndexRecord]) throws -> ContextSection {
        let hits = try CodeIndexService.search(
            projectPath: projectPath,
            query: query,
            limit: maxGraphHits,
            records: records
        )
        guard !hits.isEmpty else {
            return ContextSection(title: "Граф кода", body: "нет символов, подходящих под запрос")
        }
        var lines: [String] = []
        for hit in hits {
            let symbol = hit.symbol
            lines.append("- \(symbol.kind) \(symbol.name) — \(symbol.path):\(symbol.startLine)-\(symbol.endLine)")
            for neighbor in hit.neighbors {
                let arrow = neighbor.isOutgoing ? "→" : "←"
                let edge = neighbor.edge.rawValue
                let confidence = neighbor.confidence == .exact ? "" : " (\(neighbor.confidence.rawValue))"
                let location = neighbor.startLine.map { ":\($0)" } ?? ""
                lines.append("  \(arrow) \(edge) \(neighbor.name) — \(neighbor.path)\(location)\(confidence)")
            }
        }
        return ContextSection(title: "Граф кода", body: lines.joined(separator: "\n"))
    }

    /// Explicit gap section used when the graph build exceeded its budget. The
    /// pack must say so honestly instead of silently dropping the section, so
    /// the model sees why the graph is missing (bюджет стадии графа).
    static func graphGap(reason: String) -> ContextSection {
        ContextSection(title: "Граф кода", body: reason)
    }

    // MARK: - Pieces

    /// Query terms for matching: lowercased words of three or more characters.
    /// Short words carry no signal and would match every skill.
    static func queryTerms(_ query: String) -> [String] {
        var terms: [String] = []
        var current = ""
        func flush() {
            let word = current.lowercased()
            if word.count >= 3, !terms.contains(word) { terms.append(word) }
            current = ""
        }
        for character in query {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return terms
    }

    /// Truncates on a UTF-8 boundary so a multi-byte character is never split.
    static func bounded(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var result = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            if used + size > bytes { break }
            result.append(character)
            used += size
        }
        return result + "\n[обрезано]"
    }
}
