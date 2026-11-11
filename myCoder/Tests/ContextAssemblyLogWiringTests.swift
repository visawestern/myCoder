import Testing
import Foundation
@testable import myCoder

/// The context journal is only real if the send path writes it and the
/// composer really renders it. These tests read the wiring at the source
/// level: the project has no UI test target, and a deleted call site is
/// exactly the regression "tests pass" would otherwise hide.
@Suite("Журнал сборки контекста подключён к отправке и к композеру")
struct ContextAssemblyLogWiringTests {

    @Test("Отправка начинает журнал и закрывает его реальным результатом")
    func sendPathRecordsTheJournal() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("appState.beginContextAssembly("))
        #expect(source.contains("appState.startContextAction("))
        #expect(source.contains("appState.finishContextAction("))
        #expect(source.contains("appState.completeContextAssembly("))
    }

    @Test("Композер показывает журнал раскрывающимся вверх спойлером")
    func composerShowsTheSpoiler() throws {
        let source = try RepoRoot.inputViewsSourceText
        #expect(source.contains("ContextAssemblyStatusPanel("))
        #expect(source.contains("appState.contextAssemblyLog"))
        #expect(source.contains("ContextAssemblyEntryRow("))
        #expect(source.contains("maxHeight: 260"))
    }

    @Test("Окно «Контекст» берёт содержимое из сообщения, а не из @State")
    func contextSheetReadsTheMessage() throws {
        let source = try RepoRoot.messageRowSourceText
        #expect(source.contains("MessageContextSheetLogic.content(for: message)"))
        // Transient state is exactly what produced the empty window.
        #expect(!source.contains("compiledContextText"))
        #expect(!source.contains("compiledContextFallback"))
    }

    @Test("Причина отсутствия пакета переживает перезагрузку чата")
    func contextSummaryIsPersisted() throws {
        // The save path spans the bridge and its message-parts extension,
        // so the contract is checked across both files.
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/DatabaseBridge.swift")
            + "\n"
            + RepoRoot.sourceText("myCoder/Sources/Services/DatabaseBridge+MessageParts.swift")
        #expect(source.contains("MessageMetadataCodec.encode("))
        #expect(source.contains("contextSummary: metadata.contextSummary"))
    }

    @Test("Журнал виден по HTTP в /api/state")
    func journalIsVisibleOverHttp() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/ContextStateSnapshotLogic.swift")
        #expect(source.contains("\"assemblyLog\""))
        #expect(source.contains("\"assemblySummary\""))
    }

    @Test("Новые подписи журнала переведены на все языки")
    func journalLabelsAreLocalized() throws {
        let source = try RepoRoot.localizationSourceText
        for key in ["locContextAssemblyLog", "locContextActionsCount", "locContextRequestLabel",
                    "locContextProcessingLabel", "locContextResultLabel", "locContextStatusRunning",
                    "locContextStatusDone", "locContextStatusWarning", "locContextStatusFailed",
                    "locContextStatusSkipped"] {
            #expect(source.contains("\"\(key)\""))
        }
    }
}
