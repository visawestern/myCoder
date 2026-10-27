import Testing
import Foundation
@testable import myCoder

@Suite("Подготовка контекста перед отправкой")
struct SendContextPreparationTests {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-send-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = """
        import Foundation

        final class UserStore {
            func load(id: String) -> Int { 0 }
        }
        """
        try source.write(to: root.appendingPathComponent("UserStore.swift"),
                         atomically: true, encoding: .utf8)
        return root
    }

    private func records(for root: URL) throws -> [FileIndexRecord] {
        let text = try String(contentsOf: root.appendingPathComponent("UserStore.swift"), encoding: .utf8)
        return [FileIndexRecord(path: "UserStore.swift", hash: "h", size: text.utf8.count,
                                lastModified: 1_700_000_000, language: "swift", searchableText: text)]
    }

    @Test("Выключенный точечный контекст не меняет текст запроса")
    func disabledLeavesMessageUntouched() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "как работает UserStore",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: false
        )
        #expect(preparation.modelText == "как работает UserStore")
        #expect(preparation.pack == nil)
        #expect(preparation.warning == nil)
    }

    @Test("Включённый контекст даёт пакет с цитатами и меняет только текст для модели")
    func enabledBuildsPack() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "как работает UserStore.load",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true
        )
        #expect(preparation.modelText.contains("UserStore.swift:"))
        #expect(preparation.pack?.citations.isEmpty == false)
        #expect(preparation.warning == nil)
    }

    @Test("Старый авто-блок проекта не дублируется в пакете")
    func legacyBlockIsNotDuplicated() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "UserStore load",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true
        )
        #expect(!preparation.modelText.contains("<project-context>"))
    }

    @Test("Пустой индекс — видимая деградация, отправка продолжается")
    func emptyIndexDegradesVisibly() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "UserStore load",
            records: [],
            projectPath: root.path,
            isEnabled: true
        )
        #expect(preparation.modelText == "UserStore load")
        #expect(preparation.warning != nil)
    }

    @Test("Пакет прикрепляется к user-сообщению как часть compiledContext")
    func packBecomesMessagePart() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "как работает UserStore.load",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true
        )
        let parts = SendContextPreparationLogic.contextParts(preparation)
        #expect(parts.count == 1)
        guard case .compiledContext(let text)? = parts.first else {
            Issue.record("expected a compiledContext part")
            return
        }
        #expect(text == preparation.pack?.text)
        #expect(text.contains("UserStore.swift:"))
    }

    @Test("Без пакета сообщение не получает лишних частей")
    func noPackNoPart() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "как работает UserStore",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: false
        )
        #expect(SendContextPreparationLogic.contextParts(preparation).isEmpty)
    }

    @Test("Асинхронная подготовка даёт тот же пакет, что и синхронная")
    func asyncMatchesSync() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try records(for: root)

        let sync = SendContextPreparationLogic.prepare(
            message: "как работает UserStore.load",
            records: records,
            projectPath: root.path,
            isEnabled: true
        )
        let async = await SendContextPreparationLogic.prepareAsync(
            message: "как работает UserStore.load",
            records: records,
            projectPath: root.path,
            isEnabled: true
        )
        #expect(async == sync)
        #expect(!async.modelText.isEmpty)
    }

    @Test("Длинный запрос доходит до модели целиком")
    func longMessageIsPreserved() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let message = String(repeating: "UserStore load ", count: 500)

        let preparation = SendContextPreparationLogic.prepare(
            message: message,
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true
        )
        #expect(preparation.pack?.citations.isEmpty == false)
        #expect(preparation.modelText.contains(message.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    @Test("Пробелы вместо запроса не запускают компиляцию")
    func blankMessageIsUntouched() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "   ",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true
        )
        #expect(preparation.modelText == "   ")
        #expect(preparation.pack == nil)
    }
}
