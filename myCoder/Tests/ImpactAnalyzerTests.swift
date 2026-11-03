import Foundation
import Testing
@testable import myCoder

/// User directive 2026-11-03 (харнесс): before the model answers, the harness
/// must walk every connection of the code it is about to change and demand a
/// decision for each one. The owner's example: frames moved from files on disk
/// into memory — the folder picker in the UI is now dead code, and a plain
/// model never raises that by itself.
@Suite("Харнесс-вопросы о зависимостях")
struct ImpactAnalyzerTests {

    // MARK: - Fixture

    private struct Fixture {
        let graph: ImpactGraph
        let save: CodeSymbol
        let chooseFolder: CodeSymbol
        let body: CodeSymbol
        let testSave: CodeSymbol
    }

    private func fixture() -> Fixture {
        let store = """
        struct FrameStore {
            func save(_ frame: Data) {}
            func loadFrame() {}
        }
        """
        let settings = """
        func chooseFolder() { store.save(Data()) }
        func body() { chooseFolder() }
        """
        let tests = """
        func testSave() { FrameStore().save(Data()) }
        """
        let files = [
            CodeIndexExtractor.extract(path: "FrameStore.swift", text: store, language: "swift"),
            CodeIndexExtractor.extract(path: "SettingsView.swift", text: settings, language: "swift"),
            CodeIndexExtractor.extract(path: "FrameStoreTests.swift", text: tests, language: "swift")
        ]
        let graph = ImpactGraph.build(extractions: files)
        func symbol(_ name: String) -> CodeSymbol {
            let all = files.flatMap(\.symbols)
            guard let found = all.first(where: { $0.name == name }) else {
                fatalError("fixture symbol missing: \(name)")
            }
            return found
        }
        return Fixture(graph: graph, save: symbol("save"), chooseFolder: symbol("chooseFolder"),
                       body: symbol("body"), testSave: symbol("testSave"))
    }

    private let ownerMessage = """
    мы переделали способ хранения файлов — из файлов в папке мы стали хранить кадры в памяти.
    в интерфейсе был раздел выбора папки для хранения, теперь он не нужен
    """

    // MARK: - Trigger

    @Test("Структурная замена запускает анализ влияния")
    func structuralChangeTriggers() {
        #expect(!ImpactAnalyzer.triggers(message: ownerMessage).isEmpty)
        #expect(!ImpactAnalyzer.triggers(message: "remove the folder picker").isEmpty)
        #expect(!ImpactAnalyzer.triggers(message: "перенеси хранение в память").isEmpty)
        #expect(!ImpactAnalyzer.triggers(message: "этот раздел устарел").isEmpty)
    }

    @Test("Обычный вопрос не запускает анализ влияния")
    func plainQuestionDoesNotTrigger() {
        #expect(ImpactAnalyzer.triggers(message: "почему падает тест?").isEmpty)
        #expect(ImpactAnalyzer.triggers(message: "объясни, как работает индекс").isEmpty)
    }

    @Test("Намерение refactor из внутренней модели запускает анализ без ключевых слов")
    func refactorIntentTriggers() {
        #expect(!ImpactAnalyzer.triggers(message: "поправь это", intent: .refactor).isEmpty)
        #expect(ImpactAnalyzer.triggers(message: "поправь это", intent: .explain).isEmpty)
    }

    // MARK: - Reverse edges

    @Test("Обратные связи находятся на глубину 2")
    func reverseEdgesDepthTwo() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(
            message: ownerMessage,
            seeds: [f.save],
            graph: f.graph
        ))
        let names = report.dependents.map(\.name)
        #expect(names.contains("chooseFolder"))
        #expect(names.contains("testSave"))
        #expect(names.contains("body"))
        let body = try #require(report.dependents.first { $0.name == "body" })
        #expect(body.depth == 2)
    }

    @Test("Глубина 1 не достаёт потребителя потребителя")
    func depthLimitIsHonest() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(
            message: ownerMessage,
            seeds: [f.save],
            graph: f.graph,
            depth: 1
        ))
        #expect(!report.dependents.contains { $0.name == "body" })
        #expect(report.dependents.contains { $0.name == "chooseFolder" })
    }

    @Test("Цикл в графе не зацикливает обход и не дублирует связи")
    func cycleIsSafe() throws {
        let a = CodeIndexExtractor.extract(path: "A.swift", text: "func alpha() { beta() }", language: "swift")
        let b = CodeIndexExtractor.extract(path: "B.swift", text: "func beta() { alpha() }", language: "swift")
        let graph = ImpactGraph.build(extractions: [a, b])
        let alpha = try #require(a.symbols.first { $0.name == "alpha" })
        let report = try #require(ImpactAnalyzer.analyze(
            message: "переделай alpha",
            seeds: [alpha],
            graph: graph,
            depth: 5
        ))
        #expect(report.dependents.count <= 2)
        #expect(report.refs.allSatisfy { $0.symbol != "alpha" })
    }

    @Test("Неразрешённые рёбра не попадают в зависимости")
    func unresolvedEdgesAreIgnored() throws {
        let file = CodeIndexExtractor.extract(
            path: "Only.swift",
            text: "func use() { externalThing() }",
            language: "swift"
        )
        let graph = ImpactGraph.build(extractions: [file])
        let use = try #require(file.symbols.first { $0.name == "use" })
        let report = ImpactAnalyzer.analyze(
            message: "переделай use",
            seeds: [use],
            graph: graph
        )
        #expect(report?.dependents.isEmpty == true)
        #expect(report?.section().body.contains("не доказывает отсутствие") == true)
    }

    // MARK: - Fate and order

    @Test("Каждая связь получает требование решить судьбу")
    func everyDependencyHasFate() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        #expect(report.fates.count == report.dependents.count)
        for fate in report.fates {
            #expect(fate.question.contains("обновить"))
            #expect(fate.question.contains("удалить"))
            #expect(fate.question.contains("оставить"))
        }
    }

    @Test("Порядок TDD: красный тест → контракт → ядро → связи → UI → регрессия")
    func changeOrderIsExplicit() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        #expect(report.order.count == 6)
        #expect(report.order[0].lowercased().contains("тест"))
        #expect(report.order[0].contains("красный"))
        #expect(report.order[1].contains("контракт"))
        #expect(report.order[2].contains("ядро"))
        #expect(report.order[3].contains("связ"))
        #expect(report.order[4].contains("UI"))
        #expect(report.order[5].contains("регресси"))
    }

    // MARK: - Questions

    @Test("Вопрос про ненужные разделы UI появляется, когда есть UI-связь")
    func uiQuestionFollowsRealEdges() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        #expect(report.questions.contains { $0.contains("UI") || $0.contains("раздел") })
    }

    @Test("Без UI-связи харнесс требует поиск UI вместо вывода об отсутствии")
    func noUIQuestionWithoutUILink() throws {
        let a = CodeIndexExtractor.extract(path: "Core.swift", text: "func core() {}\nfunc wrap() { core() }", language: "swift")
        let graph = ImpactGraph.build(extractions: [a])
        let core = try #require(a.symbols.first { $0.name == "core" })
        let report = try #require(ImpactAnalyzer.analyze(message: "переделай core", seeds: [core], graph: graph))
        #expect(report.questions.contains { $0.contains("UI") && $0.contains("поиск") })
        #expect(report.questions.contains { $0.contains("выбор папки") })
    }

    @Test("Вопрос про тесты называет конкретный тестовый файл")
    func testQuestionNamesTheFile() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        #expect(report.questions.contains { $0.contains("FrameStoreTests.swift") })
    }

    // MARK: - Owner scenario

    @Test("Сценарий владельца: кадры в памяти — раздел выбора папки больше не нужен")
    func ownerScenarioIsAnswered() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        let section = report.section()
        #expect(section.title.contains("харнесс") || section.title.contains("зависимост"))
        #expect(section.body.contains("SettingsView.swift"))
        #expect(section.body.contains("chooseFolder"))
        #expect(section.body.contains("реши"))
        #expect(section.body.contains("мёртв"))
    }

    // MARK: - Empty and bounded inputs

    @Test("Пустой запрос — нет отчёта")
    func emptyMessageYieldsNil() {
        let f = fixture()
        #expect(ImpactAnalyzer.analyze(message: "   ", seeds: [f.save], graph: f.graph) == nil)
    }

    @Test("Без символов остаются вопросы и честный пробел графа")
    func emptySeedsYieldQuestions() throws {
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [], graph: .empty))
        #expect(!report.isEmpty)
        #expect(report.dependents.isEmpty)
        #expect(report.section().body.contains("не доказывает отсутствие"))
        #expect(report.questions.contains { $0.contains("UI") })
    }

    @Test("Каждый непустой запрос получает вопросы независимо от ключевых слов")
    func noTriggerStillReviewsConnections() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: "объясни save", seeds: [f.save], graph: f.graph))
        #expect(!report.dependents.isEmpty)
        #expect(!report.questions.isEmpty)
        #expect(!report.section().body.contains("Изменение структурное:"))
    }

    @Test("Лимит связей соблюдается и отчёт не разрастается")
    func capIsRespected() throws {
        var text = "func hub() {}\n"
        for index in 0..<40 {
            text += "func user\(index)() { hub() }\n"
        }
        let file = CodeIndexExtractor.extract(path: "Hub.swift", text: text, language: "swift")
        let graph = ImpactGraph.build(extractions: [file])
        let hub = try #require(file.symbols.first { $0.name == "hub" })
        let report = try #require(ImpactAnalyzer.analyze(
            message: "переделай hub",
            seeds: [hub],
            graph: graph,
            maxDependents: 8
        ))
        #expect(report.dependents.count == 8)
        #expect(report.refs.count <= 8)
    }

    @Test("Ссылки для материализации указывают на файлы зависимостей")
    func refsPointAtDependents() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        let paths = Set(report.refs.map(\.path))
        #expect(paths.contains("SettingsView.swift"))
        #expect(paths.contains("FrameStoreTests.swift"))
        #expect(!report.refs.contains {
            $0.path == f.save.path && $0.symbol == f.save.name
                && $0.startLine == f.save.startLine && $0.endLine == f.save.endLine
        })
    }

    @Test("Отчёт детерминирован: тот же вход — тот же выход")
    func reportIsDeterministic() throws {
        let f = fixture()
        let first = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        let second = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph))
        #expect(first == second)
    }
    @Test("Исходящие зависимости и эвристическая уверенность видны модели")
    func outgoingRelationsCarryConfidence() throws {
        let caller = CodeSymbol(path: "Processor.swift", name: "process", kind: "func", startLine: 1, endLine: 3)
        let callee = CodeSymbol(path: "Store.swift", name: "save", kind: "func", startLine: 2, endLine: 5)
        let graph = ImpactGraph(symbolsByID: [caller.id: caller, callee.id: callee], edges: [
            CodeEdge(from: caller.id, to: callee.id, kind: .calls, confidence: .heuristic)
        ])
        let report = try #require(ImpactAnalyzer.analyze(message: "change process", seeds: [caller], graph: graph))
        #expect(report.dependents.contains { $0.name == "save" })
        let text = report.section().body
        #expect(text.contains("Processor.swift:1-3 process → Store.swift:2-5 save"))
        #expect(text.contains("heuristic"))
        #expect(text.contains("гипотеза"))
    }

    @Test("Файловые импортёры также становятся проверяемыми зависимостями")
    func fileNodesAreIncluded() throws {
        let seed = CodeSymbol(path: "Store.swift", name: "save", kind: "func", startLine: 1, endLine: 3)
        let graph = ImpactGraph(symbolsByID: [seed.id: seed], edges: [
            CodeEdge(from: CodeNode.file("Settings.swift"), to: CodeNode.file("Store.swift"), kind: .imports, confidence: .exact)
        ])
        let report = try #require(ImpactAnalyzer.analyze(message: "change save", seeds: [seed], graph: graph))
        #expect(report.dependents.contains { $0.path == "Settings.swift" && $0.kind == "file" })
        #expect(report.section().body.contains("exact"))
    }

    @Test("Лимиты обхода и неполнота графа явно сообщаются")
    func traversalBoundariesAreVisible() throws {
        let f = fixture()
        let report = try #require(ImpactAnalyzer.analyze(message: ownerMessage, seeds: [f.save], graph: f.graph, depth: 1, maxDependents: 1))
        let text = report.section().body
        #expect(text.contains("глубина: 1"))
        #expect(text.contains("лимит связей: 1"))
        #expect(text.contains("полнота графа не гарантирована"))
        #expect(report.questions.contains { $0.contains("документац") })
    }

    @Test("Холодный граф индексируется до чтения связей; термины модели расширяют поиск")
    func coldGraphAndSemanticTerms() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("impact-cold-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let text = "func saveFrame() {}\nfunc chooseFolder() { saveFrame() }\n"
        try text.write(to: root.appendingPathComponent("Store.swift"), atomically: true, encoding: .utf8)
        let records = [FileIndexRecord(path: "Store.swift", hash: "test", size: text.utf8.count, lastModified: 0, language: "swift", searchableText: text)]
        let optionalReport = try ImpactAnalyzer.report(projectPath: root.path, message: "кадры теперь в RAM", query: "unmatched", records: records, intent: .refactor, semanticTerms: ["saveFrame"])
        let report = try #require(optionalReport)
        #expect(report.affected.contains { $0.name == "saveFrame" })
        #expect(report.dependents.contains { $0.name == "chooseFolder" })
        #expect(report.triggers.contains("намерение: refactor"))
    }

    @Test("Зависимый символ в том же файле сохраняет отдельный кодовый блок")
    func sameFileDependentIsMaterialized() throws {
        let extraction = CodeIndexExtractor.extract(path: "Store.swift", text: "func saveFrame() {}\nfunc chooseFolder() { saveFrame() }", language: "swift")
        let seed = try #require(extraction.symbols.first { $0.name == "saveFrame" })
        let report = try #require(ImpactAnalyzer.analyze(message: "кадры теперь в памяти", seeds: [seed], graph: ImpactGraph.build(extractions: [extraction])))
        #expect(report.refs.contains { $0.path == "Store.swift" && $0.symbol == "chooseFolder" })
    }

    @Test("Связь между двумя ядрами изменения остаётся видимой")
    func edgesBetweenSeedsAreNotLost() throws {
        let extraction = CodeIndexExtractor.extract(path: "Store.swift", text: "func saveFrame() {}\nfunc chooseFolder() { saveFrame() }", language: "swift")
        let report = try #require(ImpactAnalyzer.analyze(message: "fix storage", seeds: extraction.symbols, graph: ImpactGraph.build(extractions: [extraction])))
        #expect(!report.dependents.isEmpty)
        #expect(report.section().body.contains("chooseFolder"))
        #expect(report.section().body.contains("saveFrame"))
    }

    @Test("Вызываемая функция того же файла сохраняется, точное ядро не дублируется")
    func sameFileCalleeIsMaterialized() throws {
        let extraction = CodeIndexExtractor.extract(path: "FrameStore.swift", text: "func save() { loadFrame() }\nfunc loadFrame() {}", language: "swift")
        let seed = try #require(extraction.symbols.first { $0.name == "save" })
        let report = try #require(ImpactAnalyzer.analyze(message: "change save", seeds: [seed], graph: ImpactGraph.build(extractions: [extraction])))
        #expect(report.refs.contains { $0.path == "FrameStore.swift" && $0.symbol == "loadFrame" })
        #expect(!report.refs.contains { $0.path == seed.path && $0.symbol == seed.name && $0.startLine == seed.startLine && $0.endLine == seed.endLine })
    }

}
