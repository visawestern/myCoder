import Testing
import Foundation
@testable import myCoder

/// User directive 2026-11-07: the composer status line must be an upward
/// spoiler with the complete context-assembly log. Every action keeps what was
/// requested, how it was processed and what actually came back — no invented
/// steps, no silent omissions. This suite locks the pure model behind that UI.
@MainActor
@Suite("Журнал сборки контекста")
struct ContextAssemblyLogLogicTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func pack(
        sections: [ContextSection] = [],
        included: [String] = [],
        dropped: [DroppedSource] = [],
        unknowns: [String] = [],
        text: String = "## Запрос\nвопрос",
        memoryIDs: [String] = [],
        systemPrompt: String? = "rules"
    ) -> CompiledContextPack {
        CompiledContextPack(
            sections: sections,
            citations: [],
            unknowns: unknowns,
            manifest: ContextManifest(included: included, dropped: dropped, considered: max(included.count, 1)),
            estimatedTokens: (text.utf8.count + 3) / 4,
            text: text,
            memoryIDs: memoryIDs,
            ledgerSummary: nil,
            planStatus: nil,
            systemPrompt: systemPrompt
        )
    }

    private func facts(
        status: SendContextStatus,
        pack: CompiledContextPack?,
        projectRoot: String = "/tmp/project",
        contextEnabled: Bool = true,
        plannerEnabled: Bool = true,
        impact: ImpactReport? = nil,
        impactTimedOut: Bool = false,
        systemPromptBytes: Int = 120,
        historyTurnCount: Int = 3
    ) -> ContextAssemblyLogLogic.Facts {
        ContextAssemblyLogLogic.Facts(
            preparation: SendContextPreparation(
                modelText: pack?.text ?? "вопрос",
                pack: pack,
                warning: nil,
                status: status
            ),
            projectRoot: projectRoot,
            contextEnabled: contextEnabled,
            plannerEnabled: plannerEnabled,
            impact: impact,
            impactTimedOut: impactTimedOut,
            systemPromptBytes: systemPromptBytes,
            historyTurnCount: historyTurnCount
        )
    }

    @Test("Начало сборки сразу фиксирует запрос и включает журнал")
    func beginCreatesRequestEntry() {
        let log = ContextAssemblyLogLogic.begin(
            message: "почини кнопку",
            projectRoot: "/tmp/project",
            now: start
        )
        #expect(log.isRunning)
        #expect(log.entries.count == 1)
        #expect(log.entries[0].key == ContextAssemblyLogLogic.requestKey)
        #expect(log.entries[0].request.contains("почини кнопку"))
        #expect(log.entries[0].processing.contains("/tmp/project"))
        #expect(log.entries[0].status == .running)
    }

    @Test("Каждое действие добавляется один раз, повторный старт не дублирует")
    func startIsIdempotentPerKey() {
        let begin = ContextAssemblyLogLogic.begin(message: "q", projectRoot: "/tmp/p", now: start)
        let once = ContextAssemblyLogLogic.start(
            key: ContextAssemblyLogLogic.indexKey,
            title: "Индекс проекта",
            request: "/tmp/p",
            processing: "Читаю индекс",
            now: start.addingTimeInterval(0.01),
            in: begin
        )
        let twice = ContextAssemblyLogLogic.start(
            key: ContextAssemblyLogLogic.indexKey,
            title: "Индекс проекта",
            request: "другой запрос",
            processing: "Повторный старт",
            now: start.addingTimeInterval(0.02),
            in: once
        )
        #expect(twice.entries.filter { $0.key == ContextAssemblyLogLogic.indexKey }.count == 1)
        #expect(twice.entries.last?.request == "/tmp/p")
    }

    @Test("Завершение действия записывает результат, статус и длительность")
    func finishRecordsResultAndDuration() {
        let begin = ContextAssemblyLogLogic.begin(message: "q", projectRoot: "/tmp/p", now: start)
        let started = ContextAssemblyLogLogic.start(
            key: ContextAssemblyLogLogic.indexKey,
            title: "Индекс проекта",
            request: "/tmp/p",
            processing: "Читаю индекс",
            now: start,
            in: begin
        )
        let finished = ContextAssemblyLogLogic.finish(
            key: ContextAssemblyLogLogic.indexKey,
            result: "Файлов: 42",
            status: .done,
            now: start.addingTimeInterval(0.25),
            in: started
        )
        let entry = try! #require(finished.entries.last)
        #expect(entry.result == "Файлов: 42")
        #expect(entry.status == .done)
        #expect(entry.durationMilliseconds == 250)
    }

    @Test("Пропуск действия остаётся видимым и называет причину")
    func skippedActionNamesReason() {
        let log = ContextAssemblyLogLogic.begin(message: "q", projectRoot: "", now: start)
        let skipped = ContextAssemblyLogLogic.start(
            key: ContextAssemblyLogLogic.planningKey,
            title: "Планировщик запроса",
            request: "q",
            processing: ContextStageLogLogic.line(for: .planning),
            now: start,
            in: log
        )
        let settled = ContextAssemblyLogLogic.settle(
            key: ContextAssemblyLogLogic.planningKey,
            title: "Планировщик запроса",
            result: "Локальный планировщик выключен.",
            status: .skipped,
            now: start.addingTimeInterval(0.1),
            in: skipped
        )
        #expect(settled.entries.last?.status == .skipped)
        #expect(settled.entries.last?.result.contains("выключен") == true)
    }

    @Test("Финальная сборка с пакетом отмечает реальные файлы и статусы")
    func finalizeWithCompiledPack() {
        let sections = [
            ContextSection(title: "Запрос", body: "вопрос"),
            ContextSection(title: "Скилл: swift", body: "review"),
            ContextSection(title: "Граф кода", body: "- func load — Store.swift:1-2")
        ]
        let pack = pack(
            sections: sections,
            included: ["Store.swift"],
            dropped: [DroppedSource(path: "Old.swift", reason: "не влезает в бюджет")],
            text: String(repeating: "x", count: 400),
            memoryIDs: ["mem-1"]
        )
        var log = ContextAssemblyLogLogic.begin(message: "q", projectRoot: "/tmp/p", now: start)
        log = ContextAssemblyLogLogic.start(key: ContextAssemblyLogLogic.filesKey, title: "Чтение файлов",
                                            request: "бюджет", processing: "Читаю", now: start, in: log)
        let done = ContextAssemblyLogLogic.finalize(
            log: log,
            facts: facts(status: .compiled, pack: pack),
            now: start.addingTimeInterval(1)
        )
        #expect(!done.isRunning)
        #expect(done.finishedAt != nil)
        #expect(done.entries.contains { $0.key == ContextAssemblyLogLogic.packKey })
        let packEntry = try! #require(done.entries.first { $0.key == ContextAssemblyLogLogic.packKey })
        #expect(packEntry.status == .done)
        #expect(packEntry.result.contains("Store.swift") || packEntry.result.contains("Секций"))
        let filesEntry = try! #require(done.entries.first { $0.key == ContextAssemblyLogLogic.filesKey })
        #expect(filesEntry.result.contains("Store.swift"))
        #expect(filesEntry.result.contains("Old.swift"))
        #expect(filesEntry.result.contains("не влезает в бюджет"))
        let graphEntry = try! #require(done.entries.first { $0.key == ContextAssemblyLogLogic.graphKey })
        #expect(graphEntry.result.contains("Store.swift:1-2"))
        let skillsEntry = try! #require(done.entries.first { $0.key == ContextAssemblyLogLogic.skillsKey })
        #expect(skillsEntry.result.contains("swift"))
    }

    @Test("Выключенный контекст честно пропускает проектные стадии")
    func finalizeWithDisabledContext() {
        let log = ContextAssemblyLogLogic.begin(message: "q", projectRoot: "/tmp/p", now: start)
        let done = ContextAssemblyLogLogic.finalize(
            log: log,
            facts: facts(status: .disabled, pack: nil, contextEnabled: false),
            now: start.addingTimeInterval(0.5)
        )
        let packEntry = try! #require(done.entries.first { $0.key == ContextAssemblyLogLogic.packKey })
        #expect(packEntry.status == .skipped)
        #expect(packEntry.result.contains("выключен"))
        for key in [ContextAssemblyLogLogic.indexKey, ContextAssemblyLogLogic.memoryKey,
                    ContextAssemblyLogLogic.filesKey, ContextAssemblyLogLogic.graphKey] {
            let entry = try! #require(done.entries.first { $0.key == key })
            #expect(entry.status == .skipped)
            #expect(!entry.result.isEmpty)
        }
        #expect(done.summary.contains("выключен"))
    }

    @Test("Ни одно действие не остаётся в вечном статусе «выполняется»")
    func finalizeClosesRunningEntries() {
        let log = ContextAssemblyLogLogic.begin(message: "q", projectRoot: "/tmp/p", now: start)
        let began = ContextAssemblyLogLogic.start(
            key: ContextAssemblyLogLogic.memoryKey,
            title: "Память проекта",
            request: "q",
            processing: "Загружаю память",
            now: start,
            in: log
        )
        let done = ContextAssemblyLogLogic.finalize(
            log: began,
            facts: facts(status: .projectless, pack: nil, projectRoot: ""),
            now: start.addingTimeInterval(2)
        )
        #expect(!done.entries.contains { $0.status == .running })
    }

    @Test("Файлы без попаданий дают честный результат, а не пустую строку")
    func filesResultWithoutEvidence() {
        let (text, status) = ContextAssemblyLogLogic.filesResult(
            manifest: ContextManifest(included: [], dropped: [], considered: 7),
            unknowns: ["в индексе проекта нет файлов, подходящих под запрос"]
        )
        #expect(status == .warning)
        #expect(text.contains("7"))
        #expect(text.contains("не попали") || text.contains("нет"))
        #expect(text.contains("пробелы") || text.contains("нет файлов") || text.contains("индекс"))
    }

    @Test("Планировщик-фолбэк показывает причину, а не притворяется успехом")
    func planningFallbackIsWarning() {
        let fallback = LocalQueryPlanResult(plan: nil, status: .fallback(reason: "модель не назначена"), dropped: [])
        let (text, status) = ContextAssemblyLogLogic.planningResult(fallback)
        #expect(status == .warning)
        #expect(text.contains("модель не назначена"))
    }

    @Test("Истёкший бюджет анализа связей остаётся видимым")
    func impactTimeoutIsWarning() {
        let (text, status) = ContextAssemblyLogLogic.impactResult(nil, timedOut: true)
        #expect(status == .warning)
        #expect(text.contains("бюджет") || text.contains("истёк"))
    }
}
