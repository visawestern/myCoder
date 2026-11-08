import Testing
import Foundation
@testable import myCoder

/// The model-switch compaction is a cross-cutting feature: the decision lives
/// in pure logic, the state in AppState, the control in the chat panel and the
/// visible actions in a banner. These tests read the wiring at the source
/// level — the project has no UI test target, and a deleted call site is
/// exactly the regression "the logic tests pass" would otherwise hide.
@Suite("Сжатие при смене модели подключено к приложению")
struct ModelSwitchCompactionWiringTests {

    @Test("Состояние уведомления живёт в AppState")
    func noticeStateIsPublished() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/App/MyCoderApp.swift")
        #expect(source.contains("@Published var modelSwitchCompactionNotice"))
    }

    @Test("Чат реагирует на смену модели и решает по чистой логике")
    func chatHandlesModelSwitch() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains(".onChange(of: appState.effectiveSelectedModel())"))
        #expect(source.contains("ModelSwitchCompactionLogic.notice("))
        // The candidates come from every provider — the panel does not build
        // them from the current provider alone.
        #expect(source.contains("appState.modelSwitchCompactionCandidates"))
    }

    @Test("Сжатие останавливается, откатывается и повторяется")
    func compactionCanBeControlled() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("stopModelSwitchCompaction"))
        #expect(source.contains("rollbackModelSwitchCompaction"))
        #expect(source.contains("retryModelSwitchCompaction"))
        #expect(source.contains("messageStore.remove(id:"))
    }

    @Test("Отправка ждёт незавершённое сжатие перед тем, как продолжить")
    func sendWaitsForCompaction() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("await modelSwitchCompactionTask?.value"))
        #expect(source.contains("ModelSwitchCompactionLogic.blocksSend("))
    }

    @Test("Баннер показывает стоп, откат, повтор и выбор модели")
    func bannerHasAllActions() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Components/ModelSwitchCompactionBanner.swift")
        #expect(source.contains("onStop"))
        #expect(source.contains("onRollback"))
        #expect(source.contains("onRetry"))
        #expect(source.contains("onChooseModel"))
        #expect(source.contains("notice.alternatives"))
    }

    @Test("Выход с большим окном ищется во всех провайдерах, а не только в текущем")
    func alternativesAreCollectedAcrossProviders() throws {
        let panel = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(panel.contains("appState.modelSwitchCompactionCandidates"))

        let state = try RepoRoot.sourceText("myCoder/Sources/App/AppState+ModelSwitchCandidates.swift")
        #expect(state.contains("var modelSwitchCompactionCandidates"))
        #expect(state.contains("serverProviders"))
        #expect(state.contains("customProviders"))
    }

    @Test("Выбор модели с большим окном переключает провайдера вместе с моделью")
    func choosingAnAlternativeSwitchesTheProvider() throws {
        let panel = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(panel.contains("private func chooseLargerModel(_ candidate: ModelSwitchCompactionLogic.Candidate)"))
        #expect(panel.contains("appState.selectProvider(candidate.providerID)"))
        #expect(panel.contains("appState.selectModel(candidate.id)"))
    }

    @Test("Баннер вставлен над композером")
    func bannerSitsAboveTheComposer() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        let banner = try #require(source.range(of: "ModelSwitchCompactionBanner("))
        let composer = try #require(source.range(of: "BottomInputBar("))
        #expect(banner.lowerBound < composer.lowerBound)
    }

    @Test("Подписи сжатия переведены на все языки")
    func compactionLabelsAreLocalized() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/AppLocalization.swift")
        for key in ["locModelSwitchCompactionTitle",
                    "locModelSwitchCompactionStop",
                    "locModelSwitchCompactionRollback",
                    "locModelSwitchCompactionRetry",
                    "locModelSwitchCompactionChooseModel",
                    "locModelSwitchCompactionDismiss",
                    "locModelSwitchCompactionPending",
                    "locModelSwitchCompactionRunning",
                    "locModelSwitchCompactionCompacted",
                    "locModelSwitchCompactionCancelled",
                    "locModelSwitchCompactionFailed",
                    "locModelSwitchCompactionRolledBack",
                    "locModelSwitchCompactionDetails",
                    "locModelSwitchCompactionNoAlternative",
                    "locModelSwitchCompactionModelFormat"] {
            #expect(source.contains("\"\(key)\""))
        }
    }

    @Test("Сжатие управляется и по HTTP, а не только кнопками баннера")
    func compactionIsControllableOverHTTP() throws {
        let router = try RepoRoot.sourceText("myCoder/Sources/Services/AppActionRouter.swift")
        #expect(router.contains("context.compaction.stop"))
        #expect(router.contains("context.compaction.rollback"))
        #expect(router.contains("context.compaction.retry"))
        #expect(router.contains("context.compaction.chooseModel"))
        #expect(router.contains(".apiCompactionControlRequested"))

        let panel = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(panel.contains(".apiCompactionControlRequested"))
        #expect(panel.contains("handleAPICompactionControl"))
        #expect(panel.contains("case \"chooseModel\""))
    }

    @Test("Запрос сводки получает собственное время ожидания")
    func summaryRequestHasItsOwnTimeout() throws {
        // The transcript is large: the default 120 s of the chat transport
        // killed the compaction before the model answered (verified live).
        let panel = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(panel.contains("transport: URLSessionDirectChatTransport("))
        #expect(panel.contains("timeout: ConversationCompactionLogic.summaryRequestTimeout"))
        let logic = try RepoRoot.sourceText("myCoder/Sources/Services/ConversationCompactionLogic.swift")
        #expect(logic.contains("static let summaryRequestTimeout"))
    }
}
