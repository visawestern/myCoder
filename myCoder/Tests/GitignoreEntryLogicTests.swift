import Testing
@testable import myCoder

@Suite("GitignoreEntryLogic — deciding whether .mycoder/ needs a .gitignore entry")
struct GitignoreEntryLogicTests {

    @Test("Needs an entry when there is no .gitignore yet")
    func needsEntryWhenMissing() {
        #expect(GitignoreEntryLogic.needsEntry(existingContents: nil))
    }

    @Test("Needs an entry when .gitignore exists but doesn't mention .mycoder")
    func needsEntryWhenNotPresent() {
        let contents = "node_modules/\n.build/\n"
        #expect(GitignoreEntryLogic.needsEntry(existingContents: contents))
    }

    @Test("Does not need an entry when already covered by an exact line")
    func skipsWhenAlreadyPresent() {
        for existing in [".mycoder/", ".mycoder", "/.mycoder/", "/.mycoder", ".mycoder/", ".mycoder", "/.mycoder/", "/.mycoder"] {
            #expect(!GitignoreEntryLogic.needsEntry(existingContents: "node_modules/\n\(existing)\n"))
        }
    }

    @Test("Appending preserves existing content and adds a trailing newline before the new entry")
    func appendingPreservesExistingContent() {
        let existing = "node_modules/\n.build/"
        let updated = GitignoreEntryLogic.appendingEntry(to: existing)
        #expect(updated == "node_modules/\n.build/\n.mycoder/\n")
    }

    @Test("Appending to an empty/missing .gitignore produces just the new entry")
    func appendingToMissingFile() {
        #expect(GitignoreEntryLogic.appendingEntry(to: nil) == ".mycoder/\n")
    }

    @Test("Appending is a no-op when the entry is already present")
    func appendingIsNoOpWhenPresent() {
        let existing = "node_modules/\n.mycoder/\n"
        #expect(GitignoreEntryLogic.appendingEntry(to: existing) == existing)
    }
}
