import Foundation

enum CommitMessageComposer {
    private static let maxListedFiles = 3
    static let fallbackMessage = "Update project files"

    /// Builds a human-readable summary from `git diff --stat` output, e.g.
    /// "Update RightPanelView.swift, GitPublishFlowLogic.swift and 2 more files (+240 -24)".
    static func summary(fromDiffStat diffStat: String) -> String {
        let lines = diffStat
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }

        var fileNames: [String] = []
        var insertions = 0
        var deletions = 0

        for line in lines {
            if let pipeIndex = line.firstIndex(of: "|") {
                let path = String(line[..<pipeIndex]).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty {
                    fileNames.append((path as NSString).lastPathComponent)
                }
            } else if line.contains("changed") {
                insertions = Self.firstInt(matching: #"(\d+) insertion"#, in: line) ?? 0
                deletions = Self.firstInt(matching: #"(\d+) deletion"#, in: line) ?? 0
            }
        }

        return summary(fileNames: fileNames, insertions: insertions, deletions: deletions)
    }

    /// Core summary builder used both for parsed diff stats and for
    /// already-known VCS file changes.
    static func summary(fileNames: [String], insertions: Int, deletions: Int) -> String {
        guard !fileNames.isEmpty else { return "" }

        let listed = fileNames.prefix(maxListedFiles).joined(separator: ", ")
        let remaining = fileNames.count - maxListedFiles
        var text = "Update \(listed)"
        if remaining == 1 {
            text += " and 1 more file"
        } else if remaining > 1 {
            text += " and \(remaining) more files"
        }
        text += " (+\(insertions) -\(deletions))"
        return text
    }

    /// Final commit message: the user's comment as the subject,
    /// the auto-generated diff summary as the body.
    static func compose(userComment: String, diffStat: String) -> String {
        compose(userComment: userComment, summary: summary(fromDiffStat: diffStat))
    }

    /// Same as `compose(userComment:diffStat:)` but takes an already-built summary.
    static func compose(userComment: String, summary generated: String) -> String {
        let comment = userComment.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (comment.isEmpty, generated.isEmpty) {
        case (false, false): return "\(comment)\n\n\(generated)"
        case (false, true): return comment
        case (true, false): return generated
        case (true, true): return fallbackMessage
        }
    }

    private static func firstInt(matching pattern: String, in line: String) -> Int? {
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = line[range].prefix(while: { $0.isNumber })
        return Int(digits)
    }
}
