import Testing
@testable import myCoder

@Suite("Dropdown keyboard navigation (plan Раздел 6 Блок 2 п.14)")
struct DropdownKeyboardLogicTests {

    @Test func moveDownWraps() {
        #expect(DropdownKeyboardLogic.moveDown(current: 0, count: 3) == 1)
        #expect(DropdownKeyboardLogic.moveDown(current: 2, count: 3) == 0)  // wrap
    }

    @Test func moveUpWraps() {
        #expect(DropdownKeyboardLogic.moveUp(current: 1, count: 3) == 0)
        #expect(DropdownKeyboardLogic.moveUp(current: 0, count: 3) == 2)    // wrap
    }

    @Test func clampKeepsInRange() {
        #expect(DropdownKeyboardLogic.clamp(5, count: 3) == 2)
        #expect(DropdownKeyboardLogic.clamp(-1, count: 3) == 0)
        #expect(DropdownKeyboardLogic.clamp(0, count: 0) == 0)
    }

    @Test func commitIndexNilWhenEmpty() {
        #expect(DropdownKeyboardLogic.commitIndex(highlight: 0, count: 0) == nil)
        #expect(DropdownKeyboardLogic.commitIndex(highlight: 5, count: 3) == 2)
    }

    @Test func emptyListSafe() {
        #expect(DropdownKeyboardLogic.moveDown(current: 0, count: 0) == 0)
        #expect(DropdownKeyboardLogic.moveUp(current: 0, count: 0) == 0)
    }
}
