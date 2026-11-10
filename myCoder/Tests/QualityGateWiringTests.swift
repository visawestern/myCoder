import Testing
import Foundation
@testable import myCoder

/// Wiring tests for the quality gate and the internal-model onboarding: the
/// project has no UI test target, so the send path is verified at the source
/// level — a deleted call site is exactly the regression "tests pass" would
/// otherwise hide.
@Suite("Проводка гейта качества и онбординга внутренней модели")
struct QualityGateWiringTests {

    @Test("Ход завершён — гейт адвоката дьявола вызывается из отправки")
    func sendRunsQualityGate() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("func performDirectSend("), "старое тело должно быть выделено")
        #expect(source.contains("await runAnswerQualityGate("))
        #expect(source.contains("NoStopOrderStore.setOrdered(sessionID:"))
        #expect(source.contains("PlanTodoBridge.planItems"))
        #expect(source.contains("AnswerQualityGate.note("), "вердикт должен быть виден в чате")
        let gate = try RepoRoot.sourceText("myCoder/Sources/Services/AnswerQualityGate.swift")
        #expect(gate.contains("InternalModelRunner.complete"), "ревьюер идёт через назначенные внутренние модели")
    }

    @Test("Авто-продолжение уходит в ту же сессию и ограничено по глубине")
    func autoContinueIsBounded() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("qualityGateDepth: Int = 0"))
        #expect(source.contains("qualityGateDepth: depth + 1"))
        #expect(source.contains("depth < AnswerQualityGate.maxAutoContinues"))
    }

    @Test("Текст авто-продолжения помечен и несёт разбор контроля качества")
    func feedbackIsMarked() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/AnswerQualityGate.swift")
        #expect(source.contains("команды останавливаться не было"))
        #expect(source.contains("[Авто-продолжение: контроль качества]"))
    }
}

@Suite("Баннер «назначьте внутреннюю модель» в настройках индексации")
struct InternalModelOnboardingWiringTests {

    @Test("Баннер показывается при включённом планировщике и пустом списке моделей")
    func bannerAppearsWhenPlannerOnAndStoreEmpty() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Settings/IndexingSettingsView.swift")
        #expect(source.contains("appState.isLocalQueryPlannerEnabled && internalModelStore.models.isEmpty"))
        #expect(source.contains("locPlannerNoInternalModelTitle"))
        #expect(source.contains("locPlannerNoInternalModelBody"))
    }

    @Test("Баннер ведёт в настройки провайдеров одним нажатием")
    func bannerJumpsToProviders() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Settings/IndexingSettingsView.swift")
        #expect(source.contains("appState.showSettings = true"))
        #expect(source.contains("appState.settingsTab = .providers"))
        #expect(source.contains("locAddInternalModel"))
    }

    @Test("Баннер реактивный: стор наблюдается")
    func bannerObservesStore() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Settings/IndexingSettingsView.swift")
        #expect(source.contains("@ObservedObject private var internalModelStore = InternalModelStore.shared"))
    }
}
