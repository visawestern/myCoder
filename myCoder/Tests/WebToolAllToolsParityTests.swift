import Testing
import Foundation
@testable import myCoder

/// Пользовательский дефект 2026-11-09: «read_symbol tool call was not handled;
/// найди все тулы, которые объявлены в системном промпте, и сделай, чтобы они
/// обрабатывались и не проёбывались».
///
/// Системный преамбул строит список тулов прямо из `WebEmulatedTool.allCases`,
/// поэтому «объявлен в промпте» == «есть кейс в enum». Этот тест держит
/// инвариант «каждый объявленный тул обрабатывается и не теряется»:
///   1. парсится из канонического ```tool-блока (не исчезает);
///   2. имеет каноническое имя (canonicalToolName не теряет его);
///   3. проходит гейт доступа и политику plan/compose/build без падения;
///   4. безопасные файловые/читающие тулы исполняются и не отвечают
///      «unknown tool» (диспетчеризация реально есть).
@Suite("Все объявленные тулы обрабатываются (parity)")
struct WebToolAllToolsParityTests {

    /// Все тулы, которые перечисляются в системном промпте.
    private var allTools: [WebEmulatedTool] { WebEmulatedTool.allCases }

    /// Канонический ```tool-блок для заданного тула.
    private func fencedBlock(_ tool: WebEmulatedTool) -> String {
        "```tool\n" + "{\"name\": \"\(tool.rawValue)\", \"args\": {}}\n" + "```"
    }

    @Test("Каждый объявленный тул парсится из канонического блока")
    func everyDeclaredToolParsesFromCanonicalBlock() {
        for tool in allTools {
            let calls = WebToolProtocolEmulator.parseToolCalls(from: fencedBlock(tool))
            #expect(calls.count == 1, "\(tool.rawValue): должен дать ровно один вызов")
            #expect(calls.first?.name == tool.rawValue,
                    "\(tool.rawValue): имя вызова должно быть каноническим")
        }
    }

    @Test("Каждый тул имеет каноническое имя (canonicalToolName)")
    func everyToolHasCanonicalIdentity() {
        for tool in allTools {
            let canonical = WebToolProtocolEmulator.canonicalToolName(tool.rawValue)
            #expect(canonical == tool.rawValue,
                    "\(tool.rawValue): canonicalToolName не должен терять имя")
        }
    }

    @Test("Каждый тул проходит гейт доступа без падения")
    func everyToolSurvivesAccessGate() {
        for tool in allTools {
            let call = WebToolCall(name: tool.rawValue, arguments: [:])
            for level in [AccessLevel.askBeforeChanges, AccessLevel.fullAccess] {
                let permission = WebToolAccessGate.permission(for: call, accessLevel: level)
                // Не падает и возвращает валидное решение (allow/requireApproval).
                switch permission {
                case .allow, .requireApproval:
                    break
                }
            }
        }
    }

    @Test("Каждый тул проходит политику plan/compose/build без падения")
    func everyToolSurvivesPlanPolicy() {
        for tool in allTools {
            let call = WebToolCall(name: tool.rawValue, arguments: [:])
            for mode in [AgentMode.plan, AgentMode.compose, AgentMode.build] {
                let decision = PlanModeToolPolicy.decision(for: call, mode: mode)
                switch decision {
                case .execute, .deny:
                    break
                }
            }
        }
    }

    @Test("Исходный U3 read_symbol исполняется на реальном файле проекта")
    func reportedReadSymbolCallExecutes() async throws {
        let source = """
        <tool_call>{"name": "read_symbol", "args": {"path": "myCoder/Sources/Services/WebToolProtocolEmulator.swift", "name": "parseToolCalls"}}</tool_call>
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: source)
        let call = try #require(calls.first)
        let executor = ProjectWebToolExecutor(
            projectRoot: RepoRoot.url.path,
            accessLevel: .fullAccess
        )
        let result = await executor.execute(call)
        #expect(result.contains("hash verified"), "\(result)")
        #expect(result.contains("static func parseToolCalls"), "\(result)")
    }

    @Test("read_symbol парсится из блока и сохраняет имя")
    func readSymbolRoundTripsThroughParser() {
        let call = WebToolProtocolEmulator.parseToolCalls(from: fencedBlock(.readSymbol)).first
        #expect(call?.name == "read_symbol")
    }

    @Test("JSON внутри <tool_call> разбирается (live-дефект U3)")
    func toolCallXmlWrapperWithJsonParses() {
        let text = """
        <tool_call>
        {"name": "read_symbol", "args": {"path": "Sources/A.swift", "name": "parseToolCalls"}}
        </tool_call>
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1, "должен быть ровно один вызов, got: \(calls)")
        #expect(calls.first?.name == "read_symbol")
        #expect(calls.first?.arguments["name"] == "parseToolCalls")
        #expect(calls.first?.arguments["path"] == "Sources/A.swift")
    }

    @Test("JSON внутри ```tool-блока с многострочными аргументами разбирается")
    func fencedJsonWithMultilineArgsParses() {
        let text = """
        ```tool
        {
          "name": "read_symbol",
          "args": {
            "path": "myCoder/Sources/Services/WebToolProtocolEmulator.swift",
            "name": "parseToolCalls"
          }
        }
        ```
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_symbol")
        #expect(calls.first?.arguments["name"] == "parseToolCalls")
    }

    /// Безопасный детерминированный набор: файловые, читающие и планировочные
    /// тулы исполняются в пустом временном проекте и ни один не отвечает
    /// «unknown tool». Сетевые (web_fetch/browser_fetch), шелл (run_command),
    /// сабагент (task) и индексно-зависимые (code_search/read_symbol) в этом
    /// исполнении не гоняем — они покрыты парсингом, канонизацией, гейтом и
    /// политикой выше + визуальным/живым прогоном.
    @Test("Читающие/файловые тулы исполняются без «unknown tool»")
    func safeToolsExecuteWithoutUnknownTool() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-alltools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)

        // Подготовка: файл и гит-статус.
        _ = await exec.execute(WebToolCall(name: "write_file", arguments: ["path": "a.txt", "content": "hello world"]))

        let cases: [(String, [String: String])] = [
            ("read_file", ["path": "a.txt"]),
            ("list_dir", ["path": "."]),
            ("grep", ["pattern": "hello", "path": "."]),
            ("glob", ["pattern": "*.txt", "path": "."]),
            ("git_status", [:]),
            ("git_log", [:]),
            ("todo_read", [:]),
            ("task_list", [:]),
        ]
        for (name, args) in cases {
            let result = await exec.execute(WebToolCall(name: name, arguments: args))
            #expect(!result.contains("unknown tool"),
                    "\(name): не должен отвечать «unknown tool», получено: \(result)")
        }
    }
}
