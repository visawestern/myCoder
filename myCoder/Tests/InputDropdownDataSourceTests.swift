import Testing
@testable import myCoder

@Suite("Input dropdown data source (plan Раздел 6 Блок 1/2/3)")
struct InputDropdownDataSourceTests {

    private func trigger(_ symbol: Character, filter: String, at idx: Int = 0) -> TriggerContext {
        let source: TriggerContext.Source
        switch symbol {
        case "/": source = .commands
        case "@": source = .files
        case "#": source = .sessions
        default: source = .mcp
        }
        return TriggerContext(source: source, symbol: symbol, triggerIndex: idx, filter: filter)
    }

    @Test func slashListsCommandsAndSkills() {
        SlashCommandRegistry.resetHistory()
        let ctx = InputDropdownDataSource.Context(installedSkills: ["lazyweb"])
        let items = InputDropdownDataSource.items(for: trigger("/", filter: ""), context: ctx)
        #expect(items.contains { $0.kind == .command && $0.actionKey == "goal" })
        #expect(items.contains { $0.kind == .skill && $0.actionKey == "lazyweb" })
    }

    @Test func slashFiltersByQuery() {
        SlashCommandRegistry.resetHistory()
        let items = InputDropdownDataSource.items(for: trigger("/", filter: "rev"), context: .init())
        #expect(items.contains { $0.actionKey == "review" })
        #expect(!items.contains { $0.actionKey == "goal" })
    }

    @Test func atListsFiles() {
        let ctx = InputDropdownDataSource.Context(fileNames: ["README.md", "main.swift"])
        let items = InputDropdownDataSource.items(for: trigger("@", filter: "read"), context: ctx)
        #expect(items.count == 1)
        #expect(items.first?.actionKey == "README.md")
        #expect(items.first?.kind == .file)
    }

    @Test func hashListsSessions() {
        let ctx = InputDropdownDataSource.Context(sessionTitles: ["Fix bug", "Add feature"])
        let items = InputDropdownDataSource.items(for: trigger("#", filter: "fix"), context: ctx)
        #expect(items.first?.actionKey == "Fix bug")
        #expect(items.first?.kind == .session)
    }

    @Test func recentCommandsRankFirst() {
        SlashCommandRegistry.resetHistory()
        let ctx = InputDropdownDataSource.Context(recentCommandNames: ["verify"])
        let items = InputDropdownDataSource.items(for: trigger("/", filter: ""), context: ctx)
        #expect(items.first?.actionKey == "verify")
    }

    @Test func applySelectionReplacesTriggerFragmentForCommand() {
        let t = trigger("/", filter: "rev", at: 0)
        let item = CommandDropdownItem(id: "cmd:review", title: "/review", subtitle: "", category: "Commands",
                                       icon: "eye", kind: .command, actionKey: "review")
        let (text, caret) = InputDropdownDataSource.applySelection(item, trigger: t, text: "/rev")
        #expect(text == "/review ")
        #expect(caret == 8)
    }

    @Test func applySelectionMidTextForFile() {
        // "look at @rea" — trigger at index 8, filter "rea"
        let t = trigger("@", filter: "rea", at: 8)
        let item = CommandDropdownItem(id: "file:README.md", title: "README.md", subtitle: "", category: "Files",
                                       icon: "doc", kind: .file, actionKey: "README.md")
        let (text, _) = InputDropdownDataSource.applySelection(item, trigger: t, text: "look at @rea")
        #expect(text == "look at @README.md ")
    }

    @Test func groupedSectionsPreserveOrder() {
        let items = [
            CommandDropdownItem(id: "1", title: "a", subtitle: "", category: "Commands", icon: "x", kind: .command, actionKey: "a"),
            CommandDropdownItem(id: "2", title: "b", subtitle: "", category: "Skills", icon: "x", kind: .skill, actionKey: "b"),
            CommandDropdownItem(id: "3", title: "c", subtitle: "", category: "Commands", icon: "x", kind: .command, actionKey: "c")
        ]
        let groups = InputDropdownDataSource.grouped(items)
        #expect(groups.map { $0.category } == ["Commands", "Skills"])
        #expect(groups.first?.items.count == 2)
    }

    @Test func dollarListsMCPServers() {
        let ctx = InputDropdownDataSource.Context(mcpServers: ["context7", "github"])
        let items = InputDropdownDataSource.items(for: trigger("$", filter: ""), context: ctx)
        #expect(items.contains { $0.kind == .mcp && $0.actionKey == "context7" })
        #expect(items.contains { $0.kind == .mcp && $0.actionKey == "github" })
    }

    @Test func dollarFiltersMCPServers() {
        let ctx = InputDropdownDataSource.Context(mcpServers: ["context7", "github"])
        let items = InputDropdownDataSource.items(for: trigger("$", filter: "git"), context: ctx)
        #expect(items.map { $0.actionKey } == ["github"])
        #expect(!items.contains { $0.actionKey == "context7" })
    }

    @Test func dollarWithoutServersYieldsNoItems() {
        let items = InputDropdownDataSource.items(for: trigger("$", filter: ""), context: .init())
        #expect(items.isEmpty)
    }

    @Test func applySelectionForMCP() {
        let t = trigger("$", filter: "cont", at: 0)
        let item = CommandDropdownItem(id: "mcp:context7", title: "context7", subtitle: "", category: "MCP Servers",
                                       icon: "server.rack", kind: .mcp, actionKey: "context7")
        let (text, caret) = InputDropdownDataSource.applySelection(item, trigger: t, text: "$cont")
        #expect(text == "$context7 ")
        #expect(caret == 10)
    }
}
