import Foundation
import Testing
@testable import myCoder

@Suite("Command file manager CRUD", .serialized)
struct CommandFileManagerTests {

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-commands-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func sanitizeNameKeepsSafeCharacters() {
        #expect(CommandFileManager.sanitized(name: "my-command_2") == "my-command_2")
        #expect(CommandFileManager.sanitized(name: "bad/name!") == "badname")
    }

    @Test func renderWritesFrontmatterAndBody() {
        let rendered = CommandFileManager.render(name: "summarize", description: "Do a thing", template: "Summarize the current diff.\n{{input}}")
        #expect(rendered.hasPrefix("---\nname: summarize\ndescription: Do a thing\n---\n"))
        #expect(rendered.contains("Summarize the current diff."))
    }

    @Test func createThenLoadReturnsEntryWithFrontmatter() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try CommandFileManager.create(name: "deploy", description: "Deploy to staging", template: "Deploy the app to staging with {{input}}", homeDirectory: home)

        let loaded = CommandFileManager.load(homeDirectory: home)
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "deploy")
        #expect(loaded[0].description == "Deploy to staging")
        #expect(loaded[0].isEnabled)
    }

    @Test func duplicateCreateThrows() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try CommandFileManager.create(name: "deploy", description: "", template: "x", homeDirectory: home)
        #expect(throws: CommandFileError.duplicate("deploy")) {
            try CommandFileManager.create(name: "deploy", description: "", template: "x", homeDirectory: home)
        }
    }

    @Test func updateRenamesFileAndRewritesContent() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try CommandFileManager.create(name: "old", description: "Old desc", template: "Old body", homeDirectory: home)

        try CommandFileManager.update(from: "old", name: "new", description: "New desc", template: "New body", homeDirectory: home)

        let loaded = CommandFileManager.load(homeDirectory: home)
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "new")
        #expect(loaded[0].description == "New desc")
        let body = CommandFileManager.body(of: URL(fileURLWithPath: loaded[0].path))
        #expect(body == "New body")
    }

    @Test func updateMissingFileThrows() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: CommandFileError.notFound("ghost")) {
            try CommandFileManager.update(from: "ghost", name: "new", description: "", template: "x", homeDirectory: home)
        }
    }

    @Test func deleteRemovesFile() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try CommandFileManager.create(name: "gone", description: "", template: "x", homeDirectory: home)
        let deleted = try CommandFileManager.delete(named: "gone", homeDirectory: home)
        #expect(deleted)
        #expect(CommandFileManager.load(homeDirectory: home).isEmpty)
    }

    @Test func toggleEnabledPersistsState() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let name = "flaky-\(UUID().uuidString.prefix(8))"
        try CommandFileManager.create(name: name, description: "", template: "x", homeDirectory: home)

        let newState = CommandFileManager.toggleEnabled(name: name)
        #expect(!newState)
        let loaded = CommandFileManager.load(homeDirectory: home)
        #expect(loaded[0].isEnabled == false)
        // Toggle back on.
        #expect(CommandFileManager.toggleEnabled(name: name))
    }

    @Test func disabledCommandsExcludedFromRegistry() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let name = "shipit-\(UUID().uuidString.prefix(8))"
        try CommandFileManager.create(name: name, description: "", template: "Ship it", homeDirectory: home)
        CommandFileManager.setEnabled(name, enabled: false)

        let all = SlashCommandRegistry.allCommands(custom: CommandFileManager.load(homeDirectory: home))
        #expect(all.contains { $0.name == name } == false)
    }

    @Test func frontmatterParsingHandlesQuotesAndMissingBlock() {
        let withQuotes = "---\nname: \"q\"\ndescription: 'single'\n---\nBody"
        let (name, desc) = CommandFileManager.frontmatter(in: withQuotes)
        #expect(name == "q")
        #expect(desc == "single")

        let noBlock = "no frontmatter here"
        let (n2, d2) = CommandFileManager.frontmatter(in: noBlock)
        #expect(n2 == nil)
        #expect(d2 == nil)
    }

    @Test func bodyStripsFrontmatter() {
        let content = "---\nname: x\n---\n\nActual template line one\nline two"
        #expect(CommandFileManager.body(in: content) == "Actual template line one\nline two")
        #expect(CommandFileManager.body(in: "plain body") == "plain body")
    }

    @Test func templateBodySubstitutesInputPlaceholder() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try CommandFileManager.create(name: "greet", description: "", template: "Say hello to {{input}}", homeDirectory: home)

        let injected = CommandFileManager.templateBody(named: "greet", argument: "Alice", homeDirectory: home)
        #expect(injected == "Say hello to Alice")
    }

    @Test func templateBodyReturnsNilForMissingCommand() {
        let home = FileManager.default.temporaryDirectory
        let injected = CommandFileManager.templateBody(named: "not-there", argument: "", homeDirectory: home)
        #expect(injected == nil)
    }
}

@Suite("Slash command executor custom template injection")
struct SlashCommandExecutorCustomTests {

    @Test func customCommandInjectsTemplateBody() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-exec-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try CommandFileManager.create(name: "deploy", description: "", template: "Deploy the app to staging: {{input}}", homeDirectory: home)

        let custom = SlashCommand(id: "custom.1", name: "deploy", description: "", kind: .custom(path: "x"), icon: "terminal")
        let executor = SlashCommandExecutor(hasGitRepo: false, commands: [custom], homeDirectory: home)
        let action = executor.execute("/deploy production")
        #expect(action == .injectInstruction("Deploy the app to staging: production"))
    }

    @Test func customCommandWithoutTemplateFallsBackToMarker() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-exec-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let custom = SlashCommand(id: "custom.1", name: "missing", description: "", kind: .custom(path: "x"), icon: "terminal")
        let executor = SlashCommandExecutor(hasGitRepo: false, commands: [custom], homeDirectory: home)
        let action = executor.execute("/missing arg1")
        #expect(action == .injectInstruction("/missing arg1"))
    }

    @Test func builtInCommandStillResolves() {
        let executor = SlashCommandExecutor(hasGitRepo: true)
        let action = executor.execute("/context")
        #expect(action == .showContext)
    }
}
