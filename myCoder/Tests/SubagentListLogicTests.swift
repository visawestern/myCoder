import Testing
import Foundation
@testable import myCoder

/// Right-panel sub-agents: at most five rows are visible; more rows scroll
/// inside a fixed-height list. Opening a child chat must keep a breadcrumb to
/// the parent so the user can return, and must show the siblings that belong
/// to the same parent.
@Suite("Sub-agent list — five visible rows and parent navigation")
struct SubagentListLogicTests {

    private func session(
        _ id: String,
        parent: String? = nil
    ) -> ChatSession {
        ChatSession(
            id: id,
            title: id,
            directory: "/tmp/project",
            parentSessionID: parent
        )
    }

    @Test("At most five rows are visible")
    func visibleCountCapped() {
        #expect(SubagentListLogic.visibleCount(total: 0) == 0)
        #expect(SubagentListLogic.visibleCount(total: 3) == 3)
        #expect(SubagentListLogic.visibleCount(total: 5) == 5)
        #expect(SubagentListLogic.visibleCount(total: 6) == 5)
        #expect(SubagentListLogic.visibleCount(total: 99) == 5)
    }

    @Test("The list height is fixed to the visible rows")
    func fixedHeight() {
        #expect(SubagentListLogic.listHeight(total: 0, rowHeight: 44) == 0)
        #expect(SubagentListLogic.listHeight(total: 3, rowHeight: 44) == 132)
        #expect(SubagentListLogic.listHeight(total: 5, rowHeight: 44) == 220)
        #expect(SubagentListLogic.listHeight(total: 12, rowHeight: 44) == 220)
    }

    @Test("Scrolling appears only above five rows")
    func scrollOnlyWhenNeeded() {
        #expect(!SubagentListLogic.shouldScroll(total: 0))
        #expect(!SubagentListLogic.shouldScroll(total: 5))
        #expect(SubagentListLogic.shouldScroll(total: 6))
    }

    @Test("A child chat keeps its parent's children list")
    func childShowsSiblings() {
        let parent = session("parent")
        let child = session("child", parent: "parent")
        #expect(SubagentListLogic.childrenParentID(for: parent) == "parent")
        #expect(SubagentListLogic.childrenParentID(for: child) == "parent")
    }

    @Test("A child chat resolves its parent session for the back button")
    func childResolvesParent() {
        let parent = session("parent")
        let child = session("child", parent: "parent")
        #expect(SubagentListLogic.parentSession(for: child, in: [parent, child])?.id == "parent")
        #expect(SubagentListLogic.parentSession(for: parent, in: [parent, child]) == nil)
        #expect(SubagentListLogic.parentSession(for: session("orphan", parent: "gone"),
                                                 in: [parent]) == nil)
    }
}
