import Foundation
import Testing
@testable import myCoder

/// Хранилище свёрнутости секций правой панели: состояние живёт в
/// `UserDefaults` (переживает перезапуск) и разделено по чатам.
///
/// Тесты используют собственный suite `UserDefaults`, чтобы не трогать
/// настройки пользователя.
@MainActor
@Suite("Правая панель — хранилище свёрнутости по чатам")
struct RightPanelSpoilerStoreTests {

    /// Изолированный `UserDefaults` на каждый тест.
    private func defaults() -> UserDefaults {
        let suite = "RightPanelSpoilerStoreTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Новый чат стартует с развёрнутыми секциями, кроме живого хромкаста")
    func freshChatHasDefaultCollapsed() {
        let store = RightPanelSpoilerStore(defaults: defaults())
        #expect(store.collapsed(in: "chat-a") == RightPanelSpoilerLogic.defaultCollapsed)
        #expect(store.collapsed(in: "chat-a") == [.chromecast])
    }

    @Test("Развёрнутый пользователем хромкаст остаётся развёрнутым в этом чате")
    func expandingChromecastIsRemembered() {
        let store = RightPanelSpoilerStore(defaults: defaults())
        store.toggle(.chromecast, in: "chat-a")
        #expect(store.collapsed(in: "chat-a").isEmpty)
        // Другой чат по-прежнему компактный.
        #expect(store.collapsed(in: "chat-b") == [.chromecast])
    }

    @Test("Переключение меняет только указанный чат")
    func toggleIsScopedToChat() {
        let store = RightPanelSpoilerStore(defaults: defaults())
        store.toggle(.git, in: "chat-a")

        #expect(store.collapsed(in: "chat-a") == [.chromecast, .git])
        #expect(store.collapsed(in: "chat-b") == [.chromecast])
    }

    @Test("Состояние переживает пересоздание хранилища")
    func statePersistsAcrossInstances() {
        let defaults = defaults()
        let first = RightPanelSpoilerStore(defaults: defaults)
        first.toggle(.plan, in: "chat-a")
        first.toggle(.goal, in: "chat-a")

        let second = RightPanelSpoilerStore(defaults: defaults)
        #expect(second.collapsed(in: "chat-a") == [.chromecast, .plan, .goal])
    }

    @Test("Повторное переключение возвращает стартовое состояние чата")
    func toggleTwiceRestores() {
        let store = RightPanelSpoilerStore(defaults: defaults())
        store.toggle(.terminal, in: "chat-a")
        store.toggle(.terminal, in: "chat-a")
        #expect(store.collapsed(in: "chat-a") == RightPanelSpoilerLogic.defaultCollapsed)
    }

    @Test("Сброс чата забывает только его настройки и возвращает стартовое состояние")
    func resetClearsOneChatOnly() {
        let store = RightPanelSpoilerStore(defaults: defaults())
        store.toggle(.git, in: "chat-a")
        store.toggle(.goal, in: "chat-b")

        store.reset(chatID: "chat-a")

        #expect(store.collapsed(in: "chat-a") == RightPanelSpoilerLogic.defaultCollapsed)
        #expect(store.collapsed(in: "chat-b") == [.chromecast, .goal])
    }

    @Test("Сброс без идентификатора чистит состояние вне чата")
    func resetAnonymousScope() {
        let store = RightPanelSpoilerStore(defaults: defaults())
        store.toggle(.subagents, in: nil)
        #expect(store.collapsed(in: nil) == [.chromecast, .subagents])
        store.reset(chatID: nil)
        #expect(store.collapsed(in: nil) == RightPanelSpoilerLogic.defaultCollapsed)
    }

    @Test("Изменение состояния уведомляет подписчиков")
    func changeNotifiesObservers() {
        let store = RightPanelSpoilerStore(defaults: defaults())
        var notifications = 0
        let token = NotificationCenter.default.addObserver(
            forName: RightPanelSpoilerStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notifications += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.toggle(.git, in: "chat-a")
        #expect(notifications == 1)
    }

    @Test("Испорченное значение в хранилище не роняет панель")
    func corruptedValueIsIgnored() {
        let defaults = defaults()
        let key = RightPanelSpoilerLogic.scopeKey(chatID: "chat-a")
        defaults.set("git,,мусор,goal", forKey: key)

        let store = RightPanelSpoilerStore(defaults: defaults)
        #expect(store.collapsed(in: "chat-a") == [.git, .goal])
    }
}
