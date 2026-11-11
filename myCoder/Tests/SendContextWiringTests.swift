import Testing
import Foundation
@testable import myCoder

/// The compiler is only worth anything if the send path and the settings
/// really use it. These tests read the wiring at the source level — the
/// project has no UI test target, and a deleted call site is exactly the
/// regression that "tests pass" would otherwise hide.
@MainActor
@Suite("Точечный контекст подключён к отправке и настройкам")
struct SendContextWiringTests {

    @Test("Отправка компилирует контекст асинхронно и не использует старый блок")
    func sendUsesCompiler() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("SendContextPreparationLogic.prepareAsync("))
        #expect(source.contains("appState.beginContextCompilation(sessionID: sendSessionID)"))
        #expect(source.contains("appState.endContextCompilation(sessionID: sendSessionID)"))
        #expect(source.contains("SendContextPreparationLogic.contextParts("))
        #expect(!source.contains("ProjectContextGatherLogic"))
    }

    @Test("Пока контекст собирается, в поле ввода виден индикатор")
    func inputShowsLoader() throws {
        let source = try RepoRoot.inputViewsSourceText
        #expect(source.contains("var isCompilingContext: Bool"))
        #expect(source.contains("locCompilingPointContext"))
        #expect(source.contains("canSend: canSendNow"))
    }

    @Test("В настройках есть переключатель точечного контекста")
    func settingsExposeToggle() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Settings/IndexingSettingsView.swift")
        #expect(source.contains("locPointContext"))
        #expect(source.contains("pointContextBinding"))
    }

    @Test("Флаг включён по умолчанию и сохраняется между запусками")
    func flagDefaultsOnAndPersists() throws {
        let source = try RepoRoot.appStateSourceText
        #expect(source.contains("var isPointContextEnabled: Bool = true"))
        #expect(source.contains("com.mycoder.pointContextEnabled"))
    }

    @Test("Память проекта загружается перед компиляцией и передаётся в пакет")
    func sendPassesMemories() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("ProjectMemoryStore.loadChunks("))
        #expect(source.contains("memories: projectMemories"))
        #expect(source.contains("case .remember(let fact)"))
        #expect(source.contains("rememberProjectFact"))
    }

    @Test("Ключи памяти переведены на все языки")
    func memoryKeysAreLocalized() throws {
        let source = try RepoRoot.localizationSourceText
        for key in ["locMemorySaved", "locMemoryFailed", "locMemoryUsage", "locMemoryLoadFailed"] {
            #expect(source.contains("\"\(key)\""))
        }
    }

    @Test("Без пакета кнопка «Контекст» показывает честную причину, а не фолбэк-часть")
    func noPackShowsHonestReasonInsteadOfFallback() throws {
        let source = try RepoRoot.chatPanelSourceText
        // Части берутся напрямую из реального пакета (пусто, когда пакета нет).
        #expect(source.contains("let contextParts = SendContextPreparationLogic.contextParts(preparation)"))
        // Безусловная подстановка .compiledContext при пустом пакете должна
        // отсутствовать — иначе contextSummaryButton никогда не срабатывает.
        #expect(!source.contains("[.compiledContext(TurnDelivery.withSystem(sysPrompt"))
    }
}

/// The user's design (2026-11-03): the system instruction is built BEFORE the
/// context is compiled, so the pack can carry it and the context viewer shows
/// the whole payload (system + context + request) instead of only evidence.
@MainActor
@Suite("Системная инструкция собирается до контекста")
struct SendSystemPromptWiringTests {

    @Test("Системная инструкция передаётся в сборку контекста")
    func systemPromptReachesPreparation() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("systemPrompt: sysPrompt"))
        #expect(source.contains("skillsDirectory:"))
    }

    @Test("Пакет строится после системной инструкции, а не до неё")
    func systemPromptIsBuiltBeforePreparation() throws {
        let source = try RepoRoot.chatPanelSourceText
        let sysIndex = try #require(source.range(of: "let sysPrompt = TurnDelivery.systemInstruction("))
        let prepIndex = try #require(source.range(of: "SendContextPreparationLogic.prepareAsync("))
        #expect(sysIndex.lowerBound < prepIndex.lowerBound)
    }

    @Test("Вкладки контекста показывают системную инструкцию")
    func contextSheetShowsSystemInstruction() throws {
        let source = try RepoRoot.messageRowSourceText
        #expect(source.contains("TurnPresentation.inspectionTabs("))
    }
}
