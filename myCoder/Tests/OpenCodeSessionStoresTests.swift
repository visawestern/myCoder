import Testing
import Foundation
@testable import myCoder

/// Хранилища сессий opencode serve: маппинг chatID→sessionID и
/// персистентное хранилище идентификаторов.
@Suite("Хранилища сессий OpenCode")
struct OpenCodeSessionStoresTests {

    @Test("OpenCodeServeSessionStore: remember/forget по chatID")
    func serveSessionStoreRoundTrip() {
        let store = OpenCodeServeSessionStore()
        #expect(store.sessionID(for: "chat-1") == nil)
        store.remember(sessionID: "ses-1", for: "chat-1")
        #expect(store.sessionID(for: "chat-1") == "ses-1")
        #expect(store.sessionID(for: "chat-2") == nil)
        store.forget(chatID: "chat-1")
        #expect(store.sessionID(for: "chat-1") == nil)
    }

    @Test("OpenCodeSessionIdentifierStore: стабильный id, rotate, лимит")
    func identifierStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "oc-sess-tests-\(UUID().uuidString)")!

        let store = OpenCodeSessionIdentifierStore()
        let first = store.identifier(for: "chat-1", defaults: defaults)
        #expect(first.hasPrefix("ses"))
        // Тот же chat → тот же id (контекст сохраняется).
        #expect(store.identifier(for: "chat-1", defaults: defaults) == first)
        // Другой chat → новый id.
        #expect(store.identifier(for: "chat-2", defaults: defaults) != first)
        // rotate меняет id.
        let rotated = store.rotate(identifier: first, defaults: defaults)
        #expect(rotated != nil)
        #expect(rotated != first)
        #expect(store.identifier(for: "chat-1", defaults: defaults) == rotated)
        // rotate для неизвестного id → nil.
        #expect(store.rotate(identifier: "nope", defaults: defaults) == nil)
    }
}
