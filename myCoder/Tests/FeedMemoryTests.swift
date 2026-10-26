import Testing
import Foundation
@testable import myCoder

@Suite("Feed Memory")
struct FeedMemoryTests {

    @Test("No pruning while inside the buffer zone — no row shifts, no flicker")
    func noPruneInsideBuffer() {
        let store = MessageStore(maxVisible: 30, pruneBuffer: 10)
        for i in 0..<39 {
            store.append(Message(id: "m\(i)", role: .user, content: "Msg \(i)"))
        }
        #expect(store.messages.count == 39)
        #expect(store.messages.first?.id == "m0")
    }

    @Test("Crossing the buffer trims old messages back to maxVisible in one batch")
    func batchPruneOnThreshold() {
        let store = MessageStore(maxVisible: 30, pruneBuffer: 10)
        for i in 0..<41 {
            store.append(Message(id: "m\(i)", role: .user, content: "Msg \(i)"))
        }
        #expect(store.messages.count == 30)
        #expect(store.messages.first?.id == "m11")
        #expect(store.messages.last?.id == "m40")
    }

    @Test("Old messages are kept while the user is reading history (not at bottom)")
    func noPruneWhenScrolledUp() {
        let store = MessageStore(maxVisible: 30, pruneBuffer: 10)
        store.isPinnedToBottom = false
        for i in 0..<60 {
            store.append(Message(id: "m\(i)", role: .user, content: "Msg \(i)"))
        }
        #expect(store.messages.count == 60)
        #expect(store.messages.first?.id == "m0")
    }

    @Test("Returning to the bottom applies the deferred prune")
    func deferredPruneAfterReturningToBottom() {
        let store = MessageStore(maxVisible: 30, pruneBuffer: 10)
        store.isPinnedToBottom = false
        for i in 0..<60 {
            store.append(Message(id: "m\(i)", role: .user, content: "Msg \(i)"))
        }
        store.isPinnedToBottom = true
        #expect(store.messages.count == 30)
        #expect(store.messages.last?.id == "m59")
    }

    @Test("Pruned history can be paged back in via load-earlier")
    func prunedHistoryReloadable() {
        let store = MessageStore(maxVisible: 30, pruneBuffer: 10)
        store.hasMoreMessages = false
        for i in 0..<41 {
            store.append(Message(id: "m\(i)", role: .user, content: "Msg \(i)"))
        }
        #expect(store.messages.count == 30)
        #expect(store.hasMoreMessages == true)
    }

    @Test("Chat panel keeps the store's bottom-pin state in sync")
    func chatPanelSyncsPinState() throws {
        let source = try sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("isPinnedToBottom = true"))
        #expect(source.contains("isPinnedToBottom = false"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
