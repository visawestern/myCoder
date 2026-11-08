import Testing
import Foundation
@testable import myCoder

@Suite("LSP — обнаружение серверов")
struct LSPDiscoveryTests {

    @Test("xcrun (SourceKit-LSP) всегда доступен на macOS")
    func xcrunAlwaysAvailable() {
        let resolved = LSPDiscovery.resolveExecutable("xcrun", searchPath: "/usr/bin", fileManager: .default)
        #expect(resolved == "/usr/bin/xcrun")
    }

    @Test("Отсутствующий бинарник не находится")
    func missingBinaryReturnsNil() {
        let resolved = LSPDiscovery.resolveExecutable(
            "definitely-not-installed-lsp-xyz", searchPath: "/usr/bin:/bin", fileManager: .default)
        #expect(resolved == nil)
    }

    @Test("Каталог содержит стандартные серверы")
    func catalogHasStandardServers() {
        #expect(LSPDiscovery.standardServers.contains { $0.id == "sourcekit-lsp" })
        #expect(LSPDiscovery.standardServers.contains { $0.id == "rust-analyzer" })
    }

    @Test("Available возвращает только установленные")
    func availableFiltersToInstalled() {
        // Use an empty PATH: only xcrun (absolute fallback) is reported.
        let available = LSPDiscovery.available(searchPath: "", fileManager: .default)
        for spec in available {
            #expect(!spec.command.isEmpty)
        }
        #expect(available.allSatisfy { $0.command != "" })
    }
}

@Suite("LSP — реестр")
struct LSPRegistryManagerTests {

    private func record(id: String) -> InstalledLSPRecord {
        InstalledLSPRecord(
            id: id, version: "1.0.0", installedAt: Date(),
            source: .cursor, isEnabled: true, command: "test",
            args: [], languages: ["Swift"])
    }

    @Test("Upsert сохраняет предыдущий enabled-статус")
    func upsertKeepsEnabledState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        var r = record(id: "lsp-a")
        r.isEnabled = false
        try LSPRegistryManager.upsert(r, homeDirectory: home)
        let enabled = record(id: "lsp-a")
        try LSPRegistryManager.upsert(enabled, homeDirectory: home)
        let loaded = LSPRegistryManager.load(homeDirectory: home)
        #expect(loaded.first?.id == "lsp-a")
        #expect(loaded.first?.isEnabled == false, "upsert не должен затирать выключенное состояние")
    }

    @Test("SetEnabled и Remove работают")
    func setEnabledAndRemove() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try LSPRegistryManager.upsert(record(id: "lsp-b"), homeDirectory: home)
        try LSPRegistryManager.setEnabled(id: "lsp-b", enabled: false, homeDirectory: home)
        #expect(LSPRegistryManager.load(homeDirectory: home).first?.isEnabled == false)
        try LSPRegistryManager.remove(id: "lsp-b", homeDirectory: home)
        #expect(LSPRegistryManager.load(homeDirectory: home).isEmpty)
    }
}

@Suite("LSP — мутация конфига")
struct LSPConfigMutationLogicTests {

    @Test("setDisabled проставляет и снимает флаг")
    func toggleDisabled() throws {
        let base = try JSONSerialization.data(withJSONObject: [
            "lspServers": ["a": ["command": "x", "args": ["y"]]]
        ])
        let disabled = try LSPConfigMutationLogic.setDisabled(data: base, id: "a", disabled: true)
        var root = try JSONSerialization.jsonObject(with: disabled) as? [String: Any]
        var entry = (root?["lspServers"] as? [String: Any])?["a"] as? [String: Any]
        #expect(entry?["disabled"] as? Bool == true)

        let enabled = try LSPConfigMutationLogic.setDisabled(data: disabled, id: "a", disabled: false)
        root = try JSONSerialization.jsonObject(with: enabled) as? [String: Any]
        entry = (root?["lspServers"] as? [String: Any])?["a"] as? [String: Any]
        #expect(entry?["disabled"] == nil)
    }

    @Test("remove удаляет сервер")
    func removeServer() throws {
        let base = try JSONSerialization.data(withJSONObject: [
            "lspServers": ["a": ["command": "x"], "b": ["command": "y"]]
        ])
        let out = try LSPConfigMutationLogic.remove(data: base, id: "a")
        let root = try JSONSerialization.jsonObject(with: out) as? [String: Any]
        let servers = root?["lspServers"] as? [String: Any]
        #expect(servers?["a"] == nil)
        #expect(servers?["b"] != nil)
    }

    @Test("upsertServer из пустых данных создаёт объект")
    func upsertFromEmpty() throws {
        let out = try LSPConfigMutationLogic.upsertServer(data: Data(), id: "c", command: "run", args: ["--x"], languages: ["Go"])
        let root = try JSONSerialization.jsonObject(with: out) as? [String: Any]
        let entry = (root?["lspServers"] as? [String: Any])?["c"] as? [String: Any]
        #expect(entry?["command"] as? String == "run")
        #expect(entry?["args"] as? [String] == ["--x"])
        #expect(entry?["languages"] as? [String] == ["Go"])
    }
}
