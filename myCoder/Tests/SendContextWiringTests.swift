import Testing
import Foundation
@testable import myCoder

/// The compiler is only worth anything if the send path and the settings
/// really use it. These tests read the wiring at the source level — the
/// project has no UI test target, and a deleted call site is exactly the
/// regression that "tests pass" would otherwise hide.
@Suite("Точечный контекст подключён к отправке и настройкам")
struct SendContextWiringTests {

    @Test("Отправка компилирует контекст асинхронно и не использует старый блок")
    func sendUsesCompiler() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("SendContextPreparationLogic.prepareAsync("))
        #expect(source.contains("appState.isCompilingContext = true"))
        #expect(source.contains("SendContextPreparationLogic.contextParts("))
        #expect(!source.contains("ProjectContextGatherLogic"))
    }

    @Test("Пока контекст собирается, в поле ввода виден индикатор")
    func inputShowsLoader() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Components/InputViews.swift")
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
        let source = try RepoRoot.sourceText("myCoder/Sources/App/MyCoderApp.swift")
        #expect(source.contains("var isPointContextEnabled: Bool = true"))
        #expect(source.contains("com.mycoder.pointContextEnabled"))
    }

    @Test("Память проекта загружается перед компиляцией и передаётся в пакет")
    func sendPassesMemories() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("ProjectMemoryStore.loadChunks("))
        #expect(source.contains("memories: projectMemories"))
        #expect(source.contains("case .remember(let fact)"))
        #expect(source.contains("rememberProjectFact"))
    }

    @Test("Ключи памяти переведены на все языки")
    func memoryKeysAreLocalized() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/AppLocalization.swift")
        for key in ["locMemorySaved", "locMemoryFailed", "locMemoryUsage", "locMemoryLoadFailed"] {
            #expect(source.contains("\"\(key)\""))
        }
    }
}
