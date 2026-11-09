import Testing
import Foundation
@testable import myCoder

/// Подгрузка истории не должна двигать то, что читает пользователь:
/// страница вставляется над вьюпортом, а смещение компенсируется ровно на её
/// высоту. Prefetch стартует заранее, за экран до верха.
@Suite("Подгрузка истории без рывков")
struct ChatPaginationLogicTests {

    @Test("Prefetch — только в верхней зоне, не в самом верху и не без вьюпорта")
    func prefetchWindow() {
        #expect(!ChatPaginationLogic.shouldPrefetch(offsetY: 0, viewportHeight: 600))
        #expect(ChatPaginationLogic.shouldPrefetch(offsetY: 1, viewportHeight: 600))
        #expect(ChatPaginationLogic.shouldPrefetch(offsetY: 600, viewportHeight: 600))
        #expect(!ChatPaginationLogic.shouldPrefetch(offsetY: 601, viewportHeight: 600))
        #expect(!ChatPaginationLogic.shouldPrefetch(offsetY: 100, viewportHeight: 0))
    }

    @Test("Смещение компенсирует высоту вставленного блока и клампится")
    func preservedOffset() {
        #expect(ChatPaginationLogic.preservedOffset(oldOffset: 500, anchorShift: 800, maxOffset: 2000) == 1300)
        #expect(ChatPaginationLogic.preservedOffset(oldOffset: 0, anchorShift: 800, maxOffset: 2000) == 800)
        #expect(ChatPaginationLogic.preservedOffset(oldOffset: 1900, anchorShift: 500, maxOffset: 2000) == 2000)
        #expect(ChatPaginationLogic.preservedOffset(oldOffset: 10, anchorShift: -50, maxOffset: 2000) == 0)
    }

    @Test("Якорь — первая видимая строка, а не последнее user-сообщение чата")
    func visibleAnchorSelection() {
        let frames = [
            "above": CGRect(x: 0, y: 0, width: 600, height: 100),
            "reading": CGRect(x: 0, y: 400, width: 600, height: 300),
            "below": CGRect(x: 0, y: 800, width: 600, height: 100),
        ]
        #expect(ChatPaginationLogic.visibleAnchor(frames: frames, offsetY: 450) == "reading")
        #expect(ChatPaginationLogic.visibleAnchor(frames: frames, offsetY: 0) == "above")
        #expect(ChatPaginationLogic.visibleAnchor(frames: [:], offsetY: 450) == nil)
    }

    @Test("Content-пространство строк отделено от scroll-пространства")
    func contentSpaceIsDistinct() {
        #expect(ChatScrollSpace.content != ChatScrollSpace.name)
    }
}
