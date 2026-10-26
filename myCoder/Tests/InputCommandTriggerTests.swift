import Testing
@testable import myCoder

@Suite("Input command trigger + dropdown filter (plan Раздел 6)")
struct InputCommandTriggerTests {

    private func ctx(_ text: String, _ cursor: Int) -> TriggerContext? {
        InputCommandTriggerLogic.detectTrigger(text: text, cursorPosition: cursor)
    }

    @Test func detectsSlashAtStart() {
        let c = ctx("/rev", 4)
        #expect(c?.source == .commands)
        #expect(c?.symbol == "/")
        #expect(c?.triggerIndex == 0)
        #expect(c?.filter == "rev")
    }

    @Test func detectsAtSymbolAfterSpace() {
        let c = ctx("hello @read", 11)
        #expect(c?.source == .files)
        #expect(c?.filter == "read")
    }

    @Test func detectsHashForSessions() {
        let c = ctx("#task", 5)
        #expect(c?.source == .sessions)
        #expect(c?.filter == "task")
    }

    @Test func detectsDollarForMCP() {
        let c = ctx("$context7", 9)
        #expect(c?.source == .mcp)
        #expect(c?.symbol == "$")
        #expect(c?.filter == "context7")
    }

    @Test func emptyFilterWhenJustTriggerTyped() {
        #expect(ctx("/", 1)?.filter == "")
        #expect(ctx("@", 1)?.filter == "")
    }

    @Test func ignoresMidWordTriggerLikeEmail() {
        #expect(ctx("user@example.com", 17) == nil)
    }

    @Test func ignoresTriggerAfterNonWhitespaceNonStart() {
        // "ab/cd" — '/' is preceded by 'b', not whitespace → ignore
        #expect(ctx("ab/cd", 5) == nil)
    }

    @Test func returnsNilForCursorAtStart() {
        #expect(ctx("hello", 0) == nil)
    }

    @Test func returnsNilWhenNoTriggerPresent() {
        #expect(ctx("hello world", 11) == nil)
    }

    @Test func shouldDismissOnSpaceAfterTrigger() {
        let trig = ctx("/review", 7)!
        #expect(InputCommandTriggerLogic.shouldDismiss(after: trig, text: "/review ", cursorPosition: 8))
    }

    @Test func shouldNotDismissWhileTypingFilter() {
        let trig = ctx("/rev", 4)!
        #expect(!InputCommandTriggerLogic.shouldDismiss(after: trig, text: "/review", cursorPosition: 7))
    }

    @Test func shouldDismissWhenTriggerSymbolRemoved() {
        let trig = ctx("/rev", 4)!
        #expect(InputCommandTriggerLogic.shouldDismiss(after: trig, text: "rev", cursorPosition: 3))
    }

    // MARK: - Dropdown filter

    private func item(_ id: String, _ title: String, _ sub: String = "", _ cat: String = "Command") -> CommandDropdownItem {
        CommandDropdownItem(id: id, title: title, subtitle: sub, category: cat, icon: "star", kind: .command, actionKey: id)
    }

    @Test func filterEmptyReturnsAll() {
        let items = [item("a", "Goal"), item("b", "Review")]
        #expect(CommandDropdownFilter.filter(items, query: "").count == 2)
    }

    @Test func prefixMatchesRankFirst() {
        let items = [item("a", "Review"), item("b", "Goal"), item("c", "Preview")]
        let r = CommandDropdownFilter.filter(items, query: "rev")
        #expect(r.first?.title == "Review")
        #expect(r.contains { $0.title == "Preview" })  // fuzzy subsequence r-e-v
    }

    @Test func fuzzyMatchSubsequence() {
        #expect(CommandDropdownFilter.fuzzyMatch("rv", in: "review"))
        #expect(CommandDropdownFilter.fuzzyMatch("gol", in: "goal"))
        #expect(!CommandDropdownFilter.fuzzyMatch("xyz", in: "review"))
        #expect(CommandDropdownFilter.fuzzyMatch("", in: "anything"))
    }
}
