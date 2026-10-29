import Foundation
import Testing
@testable import myCoder

/// Deleting a chat used to touch only `sessions`, while the sidebar tree
/// renders its own per-project/project-less caches. The deleted chat stayed in
/// the list and opened an empty chat when clicked (user report 2026-10-29).
@Suite("Удаление чата из боковой панели")
struct SidebarSessionRemovalLogicTests {

    @Test("Удалённый чат исчезает из плоского списка")
    func removesFromFlatList() {
        let sessions = [
            ChatSession(id: "keep", title: "Keep"),
            ChatSession(id: "gone", title: "Gone")
        ]
        let result = SidebarSessionRemovalLogic.removing(id: "gone", from: sessions)
        #expect(result.map(\.id) == ["keep"])
    }

    @Test("Удалённый чат исчезает из кешей всех проектов")
    func removesFromProjectCaches() {
        let caches: [String: [ChatSession]] = [
            "p1": [ChatSession(id: "gone", title: "Gone")],
            "p2": [
                ChatSession(id: "keep", title: "Keep"),
                ChatSession(id: "gone", title: "Gone")
            ]
        ]
        let result = SidebarSessionRemovalLogic.removing(id: "gone", from: caches)
        #expect(result["p1"]?.isEmpty == true)
        #expect(result["p2"]?.map(\.id) == ["keep"])
    }

    @Test("Строка без чата в памяти и без записи в БД удаляется как устаревшая")
    func staleRowIsRemoved() {
        #expect(
            SessionSelectionGuardLogic.decision(
                sessionIsInMemory: false,
                sessionExistsInStore: false
            ) == .removeStaleRow
        )
    }

    @Test("Чат из кеша другого проекта остаётся доступным")
    func persistedSessionProceeds() {
        #expect(
            SessionSelectionGuardLogic.decision(
                sessionIsInMemory: false,
                sessionExistsInStore: true
            ) == .proceed
        )
        #expect(
            SessionSelectionGuardLogic.decision(
                sessionIsInMemory: true,
                sessionExistsInStore: false
            ) == .proceed
        )
    }
}
