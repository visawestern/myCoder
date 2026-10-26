import Testing
@testable import myCoder

struct CursorHitLogicTests {
    @Test func buttonRoleIsAction() {
        #expect(CursorHitLogic.isAction(role: "AXButton", actionNames: []))
        #expect(CursorHitLogic.isAction(role: "AXLink", actionNames: []))
        #expect(CursorHitLogic.isAction(role: "AXMenuItem", actionNames: []))
    }

    @Test func pressActionWithoutRoleIsAction() {
        #expect(CursorHitLogic.isAction(role: "AXGroup", actionNames: ["AXPress"]))
        #expect(CursorHitLogic.isAction(role: nil, actionNames: ["AXPress"]))
    }

    @Test func plainTextIsNotAction() {
        #expect(!CursorHitLogic.isAction(role: "AXStaticText", actionNames: []))
        #expect(!CursorHitLogic.isAction(role: nil, actionNames: []))
    }
}
