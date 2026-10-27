import Testing
import Foundation
@testable import myCoder

/// The local planner may only *widen* the deterministic plan, from a bounded
/// list of real entities, and every failure must be a visible fallback — never
/// a broken send and never invented code or line numbers.
@Suite("Локальный планировщик запроса — контракт, валидатор, fallback")
struct LocalQueryPlannerTests {

    // MARK: - Fixtures

    private let candidate = LocalModelCandidate(
        providerID: "local",
        providerName: "Ollama",
        baseURL: "http://127.0.0.1:11434/v1",
        apiKey: nil,
        model: "test-model"
    )

    /// Answers with whatever text the test wants, after an optional delay.
    private struct FakeTransport: LocalCompilerTransporting {
        let answer: String
        var delay: TimeInterval = 0

        func complete(candidate: LocalModelCandidate, prompt: String, system: String?) async throws -> String {
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            return answer
        }
    }

    private func planner(answer: String,
                         delay: TimeInterval = 0,
                         timeout: TimeInterval = 5) -> LocalQueryPlanner {
        LocalQueryPlanner(
            runner: LocalModelRunner(
                directory: LocalModelDirectory(candidates: [candidate]),
                transport: FakeTransport(answer: answer, delay: delay)
            ),
            timeout: timeout
        )
    }

    private let validJSON = """
    {"intent": "fix",
     "terms": ["cache", "reload"],
     "symbols": ["load"],
     "files": ["Sources/UserStore.swift"],
     "memory_tags": ["cache"]}
    """

    private let context = LocalPlannerContext(
        entities: [
            LocalPlannerEntity(kind: .file, path: "Sources/UserStore.swift", name: "UserStore.swift"),
            LocalPlannerEntity(kind: .symbol, path: "Sources/UserStore.swift", name: "load")
        ],
        memoryTags: ["cache", "decisions"]
    )

    // MARK: - T1: JSON contract

    @Test("T1: план декодируется из JSON-контракта, включая memory_tags и camelCase")
    func decodesContract() throws {
        let plan = try LocalQueryPlanParser.parse(validJSON)
        #expect(plan.intent == .fix)
        #expect(plan.terms == ["cache", "reload"])
        #expect(plan.symbols == ["load"])
        #expect(plan.files == ["Sources/UserStore.swift"])
        #expect(plan.memoryTags == ["cache"])

        // Fenced answers and camelCase keys are normal model output.
        let fenced = "Here you go:\n```json\n{\"intent\":\"Explain\",\"terms\":\"Cache\",\"memoryTags\":[\"Decision\"]}\n```"
        let loose = try LocalQueryPlanParser.parse(fenced)
        #expect(loose.intent == .explain)
        #expect(loose.terms == ["cache"])
        #expect(loose.memoryTags == ["decision"])

        // An unknown intent never leaks into the pack.
        #expect(try LocalQueryPlanParser.parse(#"{"intent": "rewrite-everything"}"#).intent == .other)
    }

    // MARK: - T2: validator rejects code and line numbers

    @Test("T2: план с кодом или номером строки отклоняется целиком")
    func rejectsCodeAndLineNumbers() {
        #expect(throws: LocalQueryPlanError.lineNumberDetected(field: "files")) {
            _ = try LocalQueryPlanParser.parse(#"{"files": ["Sources/UserStore.swift:12"]}"#)
        }
        #expect(throws: LocalQueryPlanError.codeDetected(field: "terms")) {
            _ = try LocalQueryPlanParser.parse(#"{"terms": ["func load()"]}"#)
        }
        #expect(throws: LocalQueryPlanError.codeDetected(field: "symbols")) {
            _ = try LocalQueryPlanParser.parse(#"{"symbols": ["func load() {\n    cache[id] ?? 0\n}"]}"#)
        }
        #expect(throws: LocalQueryPlanError.valueTooLong(field: "files")) {
            _ = try LocalQueryPlanParser.parse(
                #"{"files": [""# + String(repeating: "a", count: 200) + #""]}"#
            )
        }
        #expect(throws: LocalQueryPlanError.notJSON) {
            _ = try LocalQueryPlanParser.parse("I could not find anything relevant.")
        }
        #expect(throws: LocalQueryPlanError.tooManyItems(field: "terms")) {
            let items = (0..<40).map { "\"term\($0)\"" }.joined(separator: ",")
            _ = try LocalQueryPlanParser.parse("{\"terms\": [\(items)]}")
        }

        // A plan that passes the validator contains no line references.
        let plan = try? LocalQueryPlanParser.parse(validJSON)
        #expect(plan?.files.allSatisfy { !$0.contains(":") } == true)
    }

    // MARK: - T3: unknown entities are dropped, not fatal

    @Test("T3: неизвестные путь/символ/тег отбрасываются с записью, план остаётся")
    func dropsUnknownEntities() throws {
        let plan = try LocalQueryPlanParser.parse("""
        {"intent": "fix",
         "terms": ["cache"],
         "symbols": ["load", "NoSuchSymbol"],
         "files": ["Sources/UserStore.swift", "Sources/Ghost.swift"],
         "memory_tags": ["cache", "unknown-tag"]}
        """)
        let resolved = LocalQueryPlanParser.resolve(plan, context: context)

        #expect(resolved.plan.symbols == ["load"])
        #expect(resolved.plan.files == ["Sources/UserStore.swift"])
        #expect(resolved.plan.memoryTags == ["cache"])
        #expect(resolved.dropped.contains("symbol:NoSuchSymbol"))
        #expect(resolved.dropped.contains("file:Sources/Ghost.swift"))
        #expect(resolved.dropped.contains("tag:unknown-tag"))

        // Case-insensitive names still resolve to the canonical spelling.
        let loose = try LocalQueryPlanParser.parse(#"{"symbols": ["LOAD"], "files": ["sources/userstore.swift"]}"#)
        let canonical = LocalQueryPlanParser.resolve(loose, context: context)
        #expect(canonical.plan.symbols == ["load"])
        #expect(canonical.plan.files == ["Sources/UserStore.swift"])
        #expect(canonical.dropped.isEmpty)
    }

    // MARK: - T4: timeout and failures produce a visible fallback

    @Test("T4: таймаут и мусорный ответ дают детерминированный план и статус fallback")
    func timeoutAndGarbageFallBack() async throws {
        let slow = await planner(answer: validJSON, delay: 2, timeout: 0.05)
            .plan(message: "fix the cache", context: context)
        #expect(slow.plan == nil)
        #expect(slow.status == .fallback(reason: "timeout"))

        let garbage = await planner(answer: "Sure! I would look at the cache module.")
            .plan(message: "fix the cache", context: context)
        #expect(garbage.plan == nil)
        if case .fallback = garbage.status {} else {
            Issue.record("a garbage answer must fall back, got \(garbage.status)")
        }

        let code = await planner(answer: #"{"files": ["Sources/UserStore.swift:12"]}"#)
            .plan(message: "fix the cache", context: context)
        #expect(code.plan == nil)
        if case .fallback(let reason) = code.status {
            #expect(reason.contains("line number"))
        } else {
            Issue.record("a plan with a line number must fall back")
        }

        // The fallback pack is the deterministic pack plus one visible line:
        // retrieval itself is unchanged.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-planner-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        final class UserStore {
            func load(id: String) -> Int {
                cache[id] ?? 0
            }
        }
        """.write(
            to: root.appendingPathComponent("UserStore.swift"),
            atomically: true,
            encoding: .utf8
        )
        let records = ProjectFileScanner.scan(root: root.path)
        let board = ContextBoardBuilder.build(projectPath: root.path, records: records)

        let deterministic = TurnContextCompiler.compile(
            message: "fix the load cache",
            board: board,
            projectRoot: root.path
        )
        let fallback = TurnContextCompiler.compile(
            message: "fix the load cache",
            board: board,
            projectRoot: root.path,
            localPlan: slow
        )
        #expect(fallback.citations == deterministic.citations)
        #expect(fallback.manifest.included == deterministic.manifest.included)
        #expect(fallback.planStatus == .fallback(reason: "timeout"))
        #expect(fallback.text.contains("План запроса"))
        #expect(fallback.text.contains("детерминированный план"))
        #expect(TurnContextCompiler.merged(ContextQueryPlanner.plan(for: "x"), with: nil)
                == ContextQueryPlanner.plan(for: "x"))
    }

    @Test("T4: успешный план расширяет запрос и виден в пакете")
    func successfulPlanWidensQuery() async throws {
        let result = await planner(answer: validJSON)
            .plan(message: "fix the cache", context: context)
        #expect(result.plan?.symbols == ["load"])
        #expect(result.status == .local(model: "test-model"))
        #expect(result.dropped.isEmpty)

        let trace = TurnContextCompiler.planTraceText(result)
        #expect(trace.contains("источник: test-model"))
        #expect(trace.contains("намерение: fix"))

        let base = ContextQueryPlanner.plan(for: "fix the cache")
        let merged = TurnContextCompiler.merged(base, with: result.plan)
        #expect(merged.terms.contains("cache"))
        #expect(merged.terms.contains("reload"))
        #expect(merged.symbols == ["load"])
        #expect(merged.files == ["Sources/UserStore.swift"])
        // A local plan never removes what the user's own words produced.
        #expect(Set(base.terms).isSubset(of: Set(merged.terms)))
    }

    @Test("T4: без локальной модели и без сущностей — тоже fallback, отправка не падает")
    func missingModelAndEntitiesFallBack() async {
        let noModel = LocalModelRunner(
            directory: LocalModelDirectory(candidates: []),
            transport: FakeTransport(answer: validJSON)
        )
        let emptyDirectory = await LocalQueryPlanner(runner: noModel)
            .plan(message: "fix", context: context)
        #expect(emptyDirectory.plan == nil)
        if case .fallback = emptyDirectory.status {} else {
            Issue.record("no local model must fall back, got \(emptyDirectory.status)")
        }

        let noEntities = await planner(answer: validJSON)
            .plan(message: "fix", context: LocalPlannerContext(entities: [], memoryTags: []))
        #expect(noEntities.plan == nil)
        #expect(noEntities.status == .fallback(reason: "no entities to plan with"))
    }

    // MARK: - T5: the planner never sees the whole project

    @Test("T5: в промпт попадают только top-K сущности, без строк кода и номеров строк")
    func promptIsBounded() throws {
        let records: [FileIndexRecord] = (1...12).map { index in
            let path = "Sources/granite\(index).swift"
            let text = "func load\(index)() -> Int {\n    \(index)\n}\n"
            return FileIndexRecord(
                path: path,
                hash: "hash\(index)",
                size: text.utf8.count,
                lastModified: Double(index),
                language: "swift",
                searchableText: text
            )
        }
        let board = ContextBoardBuilder.build(projectPath: "/tmp/planner", records: records)
        let context = LocalPlannerContextBuilder.build(
            message: "update the granite loader",
            board: board,
            memories: [],
            maxFiles: 3
        )
        #expect(context.files.count == 3)
        #expect(context.symbolNames.count <= 12)

        let prompt = LocalPlannerPromptBuilder.build(message: "update the granite loader", context: context)
        let fileLines = prompt.user
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("- Sources/") && !$0.contains("→") }
        #expect(fileLines.count == 3)
        for path in context.files {
            #expect(prompt.user.contains(path))
        }
        // At least one of the twelve files is outside the top-K and must not
        // be visible to the planner at all.
        let notSelected = (1...12)
            .map { "Sources/granite\($0).swift" }
            .first { !context.files.contains($0) }
        #expect(notSelected != nil)
        if let notSelected {
            #expect(!prompt.user.contains(notSelected))
        }
        // No bodies, no line numbers anywhere in what the model sees.
        #expect(!prompt.user.contains("func load1()"))
        let lineRef = try NSRegularExpression(pattern: #"\b\d+:\d+\b"#)
        let range = NSRange(location: 0, length: (prompt.user as NSString).length)
        #expect(lineRef.firstMatch(in: prompt.user, options: [], range: range) == nil)
    }

    // MARK: - T6: switch is off by default

    @Test("T6: переключатель выключен по умолчанию и сохраняется")
    func settingsDefaultOff() throws {
        let suiteName = "mimo-planner-settings-\\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(LocalPlannerSettings.defaultEnabled == false)
        #expect(LocalPlannerSettings.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: LocalPlannerSettings.storageKey)
        #expect(LocalPlannerSettings.isEnabled(in: defaults) == true)

        defaults.set(false, forKey: LocalPlannerSettings.storageKey)
        #expect(LocalPlannerSettings.isEnabled(in: defaults) == false)
    }

    // MARK: - T6: the switch is wired into settings and the send path

    @Test("T6: переключатель, локализация и вызов из отправки существуют")
    func switchIsWired() throws {
        #expect(LocalPlannerSettings.storageKey == "com.mycoder.localQueryPlannerEnabled")
        let appSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/App/MyCoderApp.swift"),
            encoding: .utf8
        )
        #expect(appSource.contains("LocalPlannerSettings.isEnabled"))
        #expect(appSource.contains("isLocalQueryPlannerEnabled"))

        let settingsSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Views/Settings/IndexingSettingsView.swift"),
            encoding: .utf8
        )
        #expect(settingsSource.contains("locLocalQueryPlanner"))

        let chatSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Views/ChatPanelView.swift"),
            encoding: .utf8
        )
        #expect(chatSource.contains("isLocalQueryPlannerEnabled"))
        #expect(chatSource.contains("planLocally"))
        #expect(chatSource.contains("localPlan: localPlan"))

        // Every language the table supports has a non-empty translation.
        #expect(!L.t(AppLocalizationKey.locLocalQueryPlanner).isEmpty)
        #expect(!L.t(AppLocalizationKey.locLocalQueryPlannerDescription).isEmpty)
    }
}
