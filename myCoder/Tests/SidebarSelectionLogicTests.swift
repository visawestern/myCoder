import Testing
import Foundation
@testable import myCoder

/// Сайдбар должен явно показывать, какой чат открыт в активном окне —
/// и для чатов проекта, и для без-проектных чатов (директива
/// 2026-10-30). Логика выбора вынесена в чистое правило, чтобы обе строки
/// сайдбара использовали ОДИНАКОВОЕ сравнение.
@Suite("Сайдбар: подсветка активного чата")
struct SidebarSelectionLogicTests {

    @Test("Выбранный чат совпадает по id")
    func selectedChatMatchesById() {
        #expect(SidebarSelectionLogic.isSelected(sessionID: "s1", selectedSessionID: "s1"))
    }

    @Test("Невыбранный чат не подсвечивается")
    func otherChatIsNotSelected() {
        #expect(!SidebarSelectionLogic.isSelected(sessionID: "s1", selectedSessionID: "s2"))
    }

    @Test("Без выбранной сессии ничего не подсвечивается")
    func nilSelectionSelectsNothing() {
        #expect(!SidebarSelectionLogic.isSelected(sessionID: "s1", selectedSessionID: nil))
    }

    @Test("Пустой id строки не может быть выбран")
    func emptyRowIdIsNeverSelected() {
        #expect(!SidebarSelectionLogic.isSelected(sessionID: "", selectedSessionID: "s1"))
    }
}
