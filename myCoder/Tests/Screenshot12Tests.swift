import Testing
import Foundation
@testable import myCoder

@Suite("Screenshot 12 Right Panel Icons")
struct Screenshot12Tests {

    @Test("Git tools icons match screenshot 12")
    func gitToolsIcons() {
        #expect(RightPanelLayout.changesIcon == "doc.text")
        #expect(RightPanelLayout.branchIcon == "arrow.triangle.branch")
        #expect(RightPanelLayout.commitIcon == "arrow.up.to.line.circle")
        #expect(RightPanelLayout.panelMenuIcon == "ellipsis")
        #expect(RightPanelLayout.panelExpandIcon == "arrow.up.left.and.arrow.down.right")
        #expect(RightPanelLayout.branchChevronIcon == "chevron.down")
    }

    @Test("Progress step icons match screenshot 12")
    func progressStepIcons() {
        #expect(RightPanelLayout.stepInProgressIcon == "arrow.right")
        #expect(RightPanelLayout.stepWaitingIcon == "circle")
        #expect(RightPanelLayout.completedHeaderIcon == "chevron.up")
        #expect(RightPanelLayout.waitingHeaderIcon == "chevron.down")
    }

    @Test("Progress display splits waiting into inline and collapsed")
    func waitingSplit() {
        let steps = [
            TaskStep(title: "Done", status: .completed),
            TaskStep(title: "Active", status: .inProgress),
            TaskStep(title: "W1", status: .waiting),
            TaskStep(title: "W2", status: .waiting),
            TaskStep(title: "W3", status: .waiting),
            TaskStep(title: "W4", status: .waiting),
            TaskStep(title: "W5", status: .waiting)
        ]
        let inline = RightPanelProgressDisplay.inlineWaitingSteps(steps)
        #expect(inline.count == 2)
        #expect(inline[0].title == "W1")
        #expect(RightPanelProgressDisplay.collapsedWaitingCount(steps) == 3)
    }
}
