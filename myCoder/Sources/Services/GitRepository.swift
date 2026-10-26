import Foundation

enum GitCommandError: Error, LocalizedError, Equatable {
    case notARepository
    case emptyCommitMessage
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notARepository:
            return "Not a git repository"
        case .emptyCommitMessage:
            return "Commit message cannot be empty"
        case .commandFailed(let message):
            return message
        }
    }
}

struct GitLocalFileChange: Equatable {
    let path: String
    let status: String
    let additions: Int
    let deletions: Int
}

struct GitOperationResult: Equatable {
    let success: Bool
    let output: String
}

struct GitRepository {

    static func repositoryRoot(for path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitCommandError.notARepository }
        do {
            let root = try run(["rev-parse", "--show-toplevel"], in: trimmed)
            return normalizePath(root)
        } catch GitCommandError.commandFailed {
            throw GitCommandError.notARepository
        }
    }

    static func currentBranch(in repoPath: String) -> String {
        (try? run(["rev-parse", "--abbrev-ref", "HEAD"], in: repoPath)) ?? "main"
    }

    static func branches(in repoPath: String) throws -> [String] {
        let output = try run(["branch", "--format=%(refname:short)"], in: repoPath)
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func checkout(branch: String, in repoPath: String) throws -> GitOperationResult {
        let output = try run(["checkout", branch], in: repoPath)
        return GitOperationResult(success: true, output: output)
    }

    static func workingTreeChanges(in repoPath: String, maxNumstatFiles: Int = 150) throws -> [GitLocalFileChange] {
        let porcelain = try run(["status", "--porcelain"], in: repoPath)
        guard !porcelain.isEmpty else { return [] }

        let statusLines = porcelain.split(separator: "\n")
        let skipNumstat = statusLines.count > maxNumstatFiles

        var numstat: [String: (add: Int, del: Int)] = [:]
        if !skipNumstat {
            for line in try run(["diff", "--numstat"], in: repoPath).split(separator: "\n") {
                parseNumstatLine(String(line), into: &numstat)
            }
            for line in try run(["diff", "--cached", "--numstat"], in: repoPath).split(separator: "\n") {
                parseNumstatLine(String(line), into: &numstat)
            }
        }

        var changes: [GitLocalFileChange] = []
        for line in statusLines {
            let entry = String(line)
            guard let parsed = parseStatusLine(entry) else { continue }
            let codes = parsed.codes
            var filePath = parsed.path
            if filePath.contains(" -> ") {
                filePath = String(filePath.split(separator: " -> ").last ?? "")
            }
            let stats = numstat[filePath] ?? (0, 0)
            let status = mapPorcelainStatus(codes)
            var additions = stats.add
            let deletions = stats.del
            if status == "modified" && additions == 0 && deletions == 0 {
                additions = 1
            }
            if status == "added" && additions == 0 {
                additions = 1
            }
            changes.append(
                GitLocalFileChange(
                    path: filePath,
                    status: status,
                    additions: additions,
                    deletions: stats.del
                )
            )
        }
        return changes.sorted { $0.path < $1.path }
    }

    static func commitAll(in repoPath: String, message: String) throws -> GitOperationResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitCommandError.emptyCommitMessage }
        _ = try run(["add", "-A"], in: repoPath)
        let output = try run(["commit", "-m", trimmed], in: repoPath)
        return GitOperationResult(success: true, output: output)
    }

    static func remotes(in repoPath: String) throws -> [String] {
        let output = try run(["remote"], in: repoPath)
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func hasUpstream(in repoPath: String) -> Bool {
        (try? run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: repoPath)) != nil
    }

    static func pushArguments(hasUpstream: Bool, branch: String, remote: String = "origin") -> [String] {
        hasUpstream ? ["push"] : ["push", "--set-upstream", remote, branch]
    }

    static func push(in repoPath: String) throws -> GitOperationResult {
        let branch = currentBranch(in: repoPath)
        let arguments = pushArguments(hasUpstream: hasUpstream(in: repoPath), branch: branch)
        let output = try run(arguments, in: repoPath)
        return GitOperationResult(success: true, output: output)
    }

    static func toVcsFileDiffs(_ changes: [GitLocalFileChange]) -> [MimoVcsFileDiff] {
        changes.map {
            MimoVcsFileDiff(
                path: $0.path,
                status: $0.status,
                additions: $0.additions,
                deletions: $0.deletions
            )
        }
    }

    @discardableResult
    static func run(_ arguments: [String], in directory: String, timeout: TimeInterval = 20) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            process.waitUntilExit()  // Ensure process fully exits before reading status
            throw GitCommandError.commandFailed("Git command timed out")
        }

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = err.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = out.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitCommandError.commandFailed(message.isEmpty ? fallback : message)
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func parseNumstatLine(_ line: String, into numstat: inout [String: (add: Int, del: Int)]) {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return }
        let addToken = String(parts[0])
        let delToken = String(parts[1])
        let add = addToken == "-" ? 0 : (Int(addToken) ?? 0)
        let del = delToken == "-" ? 0 : (Int(delToken) ?? 0)
        let path = String(parts[2])
        let existing = numstat[path] ?? (0, 0)
        numstat[path] = (existing.add + add, existing.del + del)
    }

    private static func parseStatusLine(_ entry: String) -> (codes: Substring, path: String)? {
        guard entry.count >= 3 else { return nil }

        if entry.count >= 4 {
            let thirdIndex = entry.index(entry.startIndex, offsetBy: 2)
            if entry[thirdIndex] == " " {
                let pathStart = entry.index(after: thirdIndex)
                let path = String(entry[pathStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (entry.prefix(2), path)
            }
        }

        guard let space = entry.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        let path = String(entry[entry.index(after: space)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (entry[..<space], path)
    }

    private static func mapPorcelainStatus(_ codes: Substring) -> String {
        let normalized = codes.trimmingCharacters(in: .whitespaces)
        let index = normalized.index(normalized.startIndex, offsetBy: min(1, normalized.count), limitedBy: normalized.endIndex) ?? normalized.endIndex
        let y = normalized[index..<normalized.endIndex]
        let x = normalized[..<index]
        if y == "?" || x == "?" { return "added" }
        if y == "D" || x == "D" { return "deleted" }
        if x == "R" || y == "R" { return "renamed" }
        if x == "A" || y == "A" { return "added" }
        return "modified"
    }
}
