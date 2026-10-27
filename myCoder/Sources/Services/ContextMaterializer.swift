import Foundation

/// Turns an atomic task into the real code it points at.
///
/// The local model only named files and symbols; the host reads those files
/// from disk and builds one focused context block. Nothing is invented here —
/// every line in the output comes from a real file of the project, and every
/// block carries the file's own line numbers.
enum ContextMaterializer {

    /// Default cap for one code block (bytes of UTF-8).
    static let defaultMaxBlockBytes = 24_000
    /// Default cap for the whole materialized context (bytes of UTF-8).
    static let defaultMaxTotalBytes = 120_000

    static func materialize(task: AtomicTask,
                            projectRoot: String,
                            maxBlockBytes: Int = defaultMaxBlockBytes,
                            maxTotalBytes: Int = defaultMaxTotalBytes,
                            maxFileBytes: Int = ProjectFileIndexLogic.defaultMaxFileSize) throws -> String {
        var sections: [String] = []

        sections.append("## Атомарная задача\n\(task.atomicTask)")

        if !task.tddSteps.isEmpty {
            let steps = task.tddSteps.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            sections.append("## TDD-порядок\n\(steps)")
        }

        if !task.acceptance.isEmpty {
            let criteria = task.acceptance.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Критерии приёмки\n\(criteria)")
        }

        var codeBlocks: [String] = []
        var omitted: [String] = []
        var seen = Set<String>()
        var totalBytes = sections.joined(separator: "\n\n").utf8.count

        for reference in task.refs {
            let key = dedupKey(reference)
            guard seen.insert(key).inserted else { continue }

            let block = try codeBlock(
                for: reference,
                projectRoot: projectRoot,
                maxBytes: maxBlockBytes,
                maxFileBytes: maxFileBytes
            )
            if totalBytes + block.utf8.count > maxTotalBytes {
                omitted.append("- \(referenceLabel(reference)) — превышен общий лимит контекста")
                continue
            }
            totalBytes += block.utf8.count
            codeBlocks.append(block)
        }

        if !codeBlocks.isEmpty {
            sections.append("## Код\n" + codeBlocks.joined(separator: "\n"))
        }

        if !task.knownGaps.isEmpty {
            let gaps = task.knownGaps.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Чего не знаем\n\(gaps)")
        }

        if !omitted.isEmpty {
            sections.append("## Не вошло\n" + omitted.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Code blocks

    /// Builds one code block for a reference. Internal so `TurnContextCompiler`
    /// can compose sections without inventing its own file reading.
    static func block(for reference: TaskReference,
                      projectRoot: String,
                      maxBytes: Int = defaultMaxBlockBytes,
                      maxFileBytes: Int = ProjectFileIndexLogic.defaultMaxFileSize) throws -> String {
        try codeBlock(for: reference, projectRoot: projectRoot, maxBytes: maxBytes, maxFileBytes: maxFileBytes)
    }

    private static func codeBlock(for reference: TaskReference,
                                  projectRoot: String,
                                  maxBytes: Int,
                                  maxFileBytes: Int) throws -> String {
        let path = reference.path
        let url = try resolve(path: path, projectRoot: projectRoot)

        // Directories, devices and sockets are not source files; reading a
        // huge file into memory is not acceptable either.
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw LocalCompilerError.unknownReference(path: path)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw LocalCompilerError.materializationFailed(path: path, reason: "not a regular file")
        }
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize <= maxFileBytes else {
            throw LocalCompilerError.materializationFailed(
                path: path,
                reason: "file is \(fileSize) bytes, the read limit is \(maxFileBytes)"
            )
        }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw LocalCompilerError.materializationFailed(
                path: path,
                reason: error.localizedDescription
            )
        }

        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else {
            throw LocalCompilerError.materializationFailed(path: path, reason: "empty file")
        }

        let language = ProjectFileIndexLogic.language(forExtension: url.pathExtension)
        var range: ClosedRange<Int>
        var notes: [String] = []

        if let start = reference.startLine {
            let first = max(1, start)
            // A reference beyond the file is a hard error: silently clamping
            // would hand the model code it did not ask for.
            guard first <= lines.count else {
                throw LocalCompilerError.materializationFailed(
                    path: path,
                    reason: "startLine \(first) is beyond the end of the file (\(lines.count) lines)"
                )
            }
            if let end = reference.endLine, end < first {
                throw LocalCompilerError.materializationFailed(
                    path: path,
                    reason: "endLine \(end) is before startLine \(first)"
                )
            }
            let requestedLast = reference.endLine ?? (first + 79)
            let last = min(lines.count, max(first, requestedLast))
            range = first...last
            if let end = reference.endLine, end > lines.count {
                notes.append("файл заканчивается на строке \(lines.count)")
            }
        } else if let symbol = reference.symbol, !symbol.isEmpty {
            let cleaned = symbol.replacingOccurrences(of: "()", with: "")
            let declarations = SymbolNameExtractor.declarations(in: text, language: language)
            guard let match = declarations.first(where: { $0.name == cleaned }) else {
                // No silent "here are the first 60 lines instead": the model
                // named a symbol, so a miss is a real failure.
                throw LocalCompilerError.materializationFailed(
                    path: path,
                    reason: "symbol '\(symbol)' was not found in this file"
                )
            }
            let first = max(1, match.line - 4)
            let last = min(lines.count, match.line + 59)
            range = first...max(first, last)
        } else {
            range = 1...lines.count
        }

        var header = "### \(path):\(range.lowerBound)-\(range.upperBound)"
        if let symbol = reference.symbol, !symbol.isEmpty {
            header += " — \(symbol)"
        }
        if let why = reference.why, !why.isEmpty {
            header += "\n(зачем: \(why))"
        }

        // Keep the block inside the byte budget by dropping trailing lines,
        // never by cutting a line in half. The truncation is stated in the
        // block itself so the model knows the excerpt is partial.
        var body = renderBody(lines: lines, range: range)
        if header.utf8.count + body.utf8.count + 1 > maxBytes {
            let marker = "\n(_усечено по лимиту: показаны строки \(range.lowerBound)-"
            while range.upperBound > range.lowerBound,
                  header.utf8.count + body.utf8.count + marker.utf8.count + 12 > maxBytes {
                range = range.lowerBound...(range.upperBound - 1)
                body = renderBody(lines: lines, range: range)
            }
            notes.append("усечено по лимиту: показаны строки \(range.lowerBound)-\(range.upperBound)")
            header = "### \(path):\(range.lowerBound)-\(range.upperBound)"
            if let symbol = reference.symbol, !symbol.isEmpty {
                header += " — \(symbol)"
            }
        }

        var block = header
        for note in notes {
            block += "\n(_\(note)_)"
        }
        block += "\n" + body
        return block
    }

    /// `123 | code` — the file's real line number in front of every line.
    private static func renderBody(lines: [String], range: ClosedRange<Int>) -> String {
        (range.lowerBound...range.upperBound)
            .map { "\($0) | \(lines[$0 - 1])" }
            .joined(separator: "\n")
    }

    // MARK: - Paths

    /// Resolves a project-relative path and refuses anything that leaves the
    /// project root — including `..` traversal, absolute paths and symlinks
    /// that point outside.
    private static func resolve(path: String, projectRoot: String) throws -> URL {
        guard !path.hasPrefix("/") else {
            throw LocalCompilerError.outsideProject(path: path)
        }
        let root = URL(fileURLWithPath: projectRoot, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        guard isInside(candidate, root: root) else {
            throw LocalCompilerError.outsideProject(path: path)
        }
        let resolved = candidate.resolvingSymlinksInPath()
        guard isInside(resolved, root: root) else {
            throw LocalCompilerError.outsideProject(path: path)
        }
        return resolved
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let path = url.path
        return path == root.path || path.hasPrefix(root.path + "/")
    }

    // MARK: - Helpers

    private static func dedupKey(_ reference: TaskReference) -> String {
        "\(reference.path)|\(reference.startLine.map(String.init) ?? "-")|\(reference.endLine.map(String.init) ?? "-")|\(reference.symbol ?? "-")"
    }

    private static func referenceLabel(_ reference: TaskReference) -> String {
        var label = reference.path
        if let start = reference.startLine {
            label += ":\(start)"
            if let end = reference.endLine { label += "-\(end)" }
        } else if let symbol = reference.symbol {
            label += " — \(symbol)"
        }
        return label
    }
}
