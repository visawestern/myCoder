import Testing
@testable import myCoder

@Suite("Slash command registry (plan Раздел 5)")
struct SlashCommandRegistryTests {

    @Test func builtInCommandsAlwaysPresent() {
        let cmds = SlashCommandRegistry.builtInCommands
        #expect(cmds.count == BuiltInSlashCommand.allCases.count)
        let names = Set(cmds.map { $0.name })
        #expect(names.contains("goal"))
        #expect(names.contains("plan"))
        #expect(names.contains("review"))
        #expect(names.contains("verify"))
        #expect(names.contains("compact"))
        #expect(cmds.allSatisfy { $0.isBuiltIn })
    }

    @Test func builtInDescriptionsAndIconsNonEmpty() {
        for c in SlashCommandRegistry.builtInCommands {
            #expect(!c.description.isEmpty, "description for \(c.name)")
            #expect(!c.icon.isEmpty, "icon for \(c.name)")
        }
    }

    @Test func requiresGitFlaggedCorrectly() {
        #expect(BuiltInSlashCommand.review.requiresGit)
        #expect(BuiltInSlashCommand.commit.requiresGit)
        #expect(BuiltInSlashCommand.pr.requiresGit)
        #expect(!BuiltInSlashCommand.goal.requiresGit)
        #expect(!BuiltInSlashCommand.explain.requiresGit)
    }

    @Test func allCommandsMergesBuiltInAndCustom() {
        let custom = [
            CommandEntry(id: "/tmp/ship.md", name: "ship", path: "/tmp/ship.md"),
            CommandEntry(id: "/tmp/goal.md", name: "goal", path: "/tmp/goal.md")  // conflict
        ]
        let all = SlashCommandRegistry.allCommands(custom: custom)
        let goalEntries = all.filter { $0.name == "goal" }
        #expect(goalEntries.count == 1)            // built-in wins, custom dropped
        #expect(goalEntries.first?.isBuiltIn == true)
        #expect(all.contains { $0.name == "ship" && !$0.isBuiltIn })
        #expect(all.count == BuiltInSlashCommand.allCases.count + 1) // built-ins + 1 custom
    }

    @Test func parseExtractsNameAndArgument() {
        let p = SlashCommandRegistry.parse("/goal improve chat performance")
        #expect(p?.name == "goal")
        #expect(p?.argument == "improve chat performance")
    }

    @Test func parseHandlesNoArgument() {
        let p = SlashCommandRegistry.parse("/context")
        #expect(p?.name == "context")
        #expect(p?.argument == "")
    }

    @Test func parseIgnoresNonCommandText() {
        #expect(SlashCommandRegistry.parse("hello world") == nil)
        #expect(SlashCommandRegistry.parse("") == nil)
        #expect(SlashCommandRegistry.parse("/") == nil)
    }

    @Test func resolveFindsByName() {
        let cmds = SlashCommandRegistry.builtInCommands
        let parsed = SlashCommandRegistry.ParsedCommand(name: "goal", argument: "x")
        #expect(SlashCommandRegistry.resolve(parsed, in: cmds)?.name == "goal")
        #expect(SlashCommandRegistry.resolve(.init(name: "nope", argument: ""), in: cmds) == nil)
    }

    @Test func usageHistoryMostRecentFirstAndCapped() {
        SlashCommandRegistry.resetHistory()
        SlashCommandRegistry.recordUsage(name: "goal")
        SlashCommandRegistry.recordUsage(name: "review")
        SlashCommandRegistry.recordUsage(name: "goal")  // moves to front
        let h = SlashCommandRegistry.usageHistory()
        #expect(h.first == "goal")
        #expect(h.count == 2)
        for _ in 0..<20 { SlashCommandRegistry.recordUsage(name: "test") }
        #expect(SlashCommandRegistry.usageHistory().count <= 10)
        SlashCommandRegistry.resetHistory()
    }

    @Test func orderedByUsagePutsRecentFirst() {
        SlashCommandRegistry.resetHistory()
        let cmds = SlashCommandRegistry.builtInCommands
        SlashCommandRegistry.recordUsage(name: "verify")
        let ordered = SlashCommandRegistry.orderedByUsage(cmds)
        #expect(ordered.first?.name == "verify")
        #expect(ordered.count == cmds.count)
        SlashCommandRegistry.resetHistory()
    }

    @Test func concurrentUsageRecordingDoesNotCorruptHistory() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    SlashCommandRegistry.recordUsage(name: "cmd\(i % 7)")
                    _ = SlashCommandRegistry.usageHistory()
                }
            }
        }
        let history = SlashCommandRegistry.usageHistory()
        #expect(history.count <= 10)
        #expect(Set(history).count == history.count)
    }
}
