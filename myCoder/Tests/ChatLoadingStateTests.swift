import Testing
import Foundation
@testable import myCoder

@Suite("Chat Loading Status Line")
struct ChatLoadingStateTests {

    @Test("Статус-строка загрузки сообщений локализована")
    func loadingMessagesLocalizationExists() {
        let ru = AppLocalization.string(.locLoadingMessages, language: .russian)
        #expect(!ru.isEmpty)
        #expect(ru.contains("Загружаем"))
        let en = AppLocalization.string(.locLoadingMessages, language: .english)
        #expect(!en.isEmpty)
        #expect(en.contains("Loading"))
    }

    @Test("BottomInputBar показывает строку «Загружаем сообщения…»")
    func inputBarRendersLoadingStatusLine() throws {
        let inputBar = try sourceText("myCoder/Sources/Views/Components/InputViews.swift")
        #expect(inputBar.contains("isLoadingMessages"))
        #expect(inputBar.contains("locLoadingMessages"))
        #expect(inputBar.contains("locCompilingPointContext"))
    }

    @Test("Загрузка в пустом чате и inline-индикатор используют ту же формулировку")
    func everyLoadingStateUsesSameWording() throws {
        let panel = try sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        let emptyState = try sourceText("myCoder/Sources/Views/Components/EmptyChatStateView.swift")
        #expect(panel.contains("locLoadingMessages"))
        #expect(emptyState.contains("locLoadingMessages"))
        #expect(!panel.contains("locLoadingChat"))
        #expect(!emptyState.contains("locLoadingChat"))
    }

    @Test("API state пробрасывает активную загрузку истории")
    func snapshotExposesLoadingFlag() throws {
        let router = try sourceText("myCoder/Sources/Services/AppActionRouter.swift")
        #expect(router.contains("\"isLoadingMessages\""))
        let app = try sourceText("myCoder/Sources/App/MyCoderApp.swift")
        #expect(app.contains("loadingChatSessionID"))
        let panel = try sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(panel.contains("appState.loadingChatSessionID = newID"))
    }

    @Test("ChatPanelView пробрасывает загрузку истории в строку состояния")
    func panelPassesLoadingFlag() throws {
        let panel = try sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(panel.contains("isLoadingMessages: messageStore.isLoadingMessages"))
    }

    @Test("Кэш фидов в памяти: повторное открытие не читает базу")
    func cachedFeedIsNotReread() {
        #expect(!SessionReloadLogic.shouldReloadMessages(hasCachedMessages: true))
        #expect(SessionReloadLogic.shouldReloadMessages(hasCachedMessages: false))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
