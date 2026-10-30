import Testing
import Foundation
@testable import myCoder

/// Логика MCP-здоровья: классификация пробы (http/stdio/nil), разрешение
/// stdio-команды по PATH и маппинг статуса с учётом свежести.
@Suite("MCP Health Check Logic")
struct MCPHealthCheckLogicTests {

    private func entry(url: String? = nil, command: String? = nil, args: [String] = []) -> MCPServerEntry {
        MCPServerEntry(id: "e1", name: "Server", command: command, isEnabled: true, url: url, args: args)
    }

    @Test("URL-запись → http-проба")
    func urlEntryMapsToHttpProbe() {
        let probe = MCPHealthCheckLogic.probe(for: entry(url: "https://localhost:3000"))
        guard case .some(.http(let url)) = probe?.kind else {
            Issue.record("ожидалась http-проба")
            return
        }
        #expect(url.absoluteString == "https://localhost:3000")
    }

    @Test("Команда без URL → stdio-проба")
    func commandEntryMapsToStdioProbe() {
        let probe = MCPHealthCheckLogic.probe(for: entry(command: "npx", args: ["-y", "server"]))
        guard case .some(.stdio(let command, let args)) = probe?.kind else {
            Issue.record("ожидалась stdio-проба")
            return
        }
        #expect(command == "npx")
        #expect(args == ["-y", "server"])
    }

    @Test("Запись без URL и команды → nil")
    func emptyEntryHasNoProbe() {
        #expect(MCPHealthCheckLogic.probe(for: entry()) == nil)
    }

    @Test("resolveStdioCommand ищет по PATH и проверяет исполняемость")
    func resolveStdioCommand() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = dir.appendingPathComponent("mytool")
        try "#!/bin/sh\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        // По PATH: поиск в директории.
        #expect(MCPHealthCheckLogic.resolveStdioCommand("mytool", searchPath: dir.path, fileManager: .default) == tool.path)
        // Отсутствует в PATH → nil.
        #expect(MCPHealthCheckLogic.resolveStdioCommand("mytool", searchPath: "/nonexistent", fileManager: .default) == nil)
        // Абсолютный путь напрямую.
        #expect(MCPHealthCheckLogic.resolveStdioCommand(tool.path, searchPath: nil, fileManager: .default) == tool.path)
    }

    @Test("Статус: выключен/нет данных/устарел → unknown")
    func statusMapping() {
        let now = Date()
        #expect(MCPHealthCheckLogic.status(isEnabled: false, lastCheck: now, lastStatus: true, now: now) == .unknown)
        #expect(MCPHealthCheckLogic.status(isEnabled: true, lastCheck: nil, lastStatus: nil, now: now) == .unknown)
        #expect(MCPHealthCheckLogic.status(
            isEnabled: true,
            lastCheck: now.addingTimeInterval(-400),
            lastStatus: true,
            now: now
        ) == .unknown, "устаревший результат → unknown")
        #expect(MCPHealthCheckLogic.status(isEnabled: true, lastCheck: now, lastStatus: true, now: now) == .healthy)
        #expect(MCPHealthCheckLogic.status(isEnabled: true, lastCheck: now, lastStatus: false, now: now) == .unhealthy)
    }
}
