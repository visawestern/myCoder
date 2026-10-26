import Foundation

/// Pure decision logic for whether a project's `.gitignore` needs a
/// `.mycoder/` entry. Deliberately **never applied automatically** — per
/// project policy, writing into a user's `.gitignore` requires their
/// explicit consent, so callers must invoke `appendingEntry` only in
/// response to an explicit user action (e.g. a "Add to .gitignore" button),
/// never during migration or database creation.
/// Legacy `.mycoder/` entries are recognized as covering (migration must not
/// duplicate the line), but newly appended entries always use `.mycoder/`.
enum GitignoreEntryLogic {
    static let mimocodeEntry = ".mycoder/"

    static let legacyEntry = ".mycoder/"

    private static let recognizedVariants: Set<String> = [
        ".mycoder", ".mycoder/", "/.mycoder", "/.mycoder/",
        ".mycoder", ".mycoder/", "/.mycoder", "/.mycoder/",
    ]

    static func needsEntry(existingContents: String?) -> Bool {
        guard let existingContents else { return true }
        let alreadyPresent = existingContents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { recognizedVariants.contains($0) }
        return !alreadyPresent
    }

    /// Returns `existingContents` with a `.mycoder/` line appended if it
    /// isn't already covered, or unchanged if it's already present.
    static func appendingEntry(to existingContents: String?) -> String {
        guard needsEntry(existingContents: existingContents) else { return existingContents ?? "" }
        var content = existingContents ?? ""
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += "\(mimocodeEntry)\n"
        return content
    }
}
