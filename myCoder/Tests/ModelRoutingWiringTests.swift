import Foundation
import Testing
@testable import myCoder

/// TEST-ONLY helper: proves the injected `complete` closure was really called.
private actor CompletionFlag {
    private(set) var wasCalled = false
    func set() { wasCalled = true }
}

/// M1 wiring guards: the routed send path must exist in the real composer code,
/// BEFORE the route guard, with journaling helpers, planner passthrough,
/// session cleanup and the routing menu. Source-inspection tests (audit B6
/// pattern) plus one behavior test for the planner `complete:` passthrough.
@MainActor
@Suite("Model routing wiring (M1)")
struct ModelRoutingWiringTests {

    @Test("performDirectSend branches to the routed turn before the route guard")
    func routedBranchPrecedesGuard() throws {
        let source = try RepoRoot.chatPanelSourceText
        guard let routedRange = source.range(of: "modelRoutingConfiguration.mode == .perRole"),
              let guardRange = source.range(of: "SendRouteGuard.errorMessage(for: route") else {
            Issue.record("Routed branch or route guard missing in ChatPanelView.swift")
            return
        }
        #expect(routedRange.lowerBound < guardRange.lowerBound)
        #expect(source.contains("runRoutedTurn"))
    }

    @Test("ChatPanelView keeps runRoutedTurn where the private streaming state lives")
    func runRoutedTurnInPanel() throws {
        let source = try RepoRoot.chatPanelSourceText
        #expect(source.contains("func runRoutedTurn"))
        // Compaction in per-role mode sends the locally collected history.
        #expect(source.contains("summaryTransport(for: route, sessionID:"))
        #expect(source.contains("routedSubagentTransport"))
        #expect(source.contains("routedPlanningComplete"))
        // Configuration reloads on every entry point that can change it.
        #expect(source.contains("reloadModelRouting"))
        #expect(source.contains("onChange(of: appState.selectedWorkspace?.path)"))
    }

    @Test("Routing helpers live in the ChatPanelView+Routing extension")
    func routingExtensionExists() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView+Routing.swift")
        #expect(source.contains("buildRoutedTurnSnapshot"))
        #expect(source.contains("func reloadModelRouting"))
        #expect(source.contains("routedCompactionTransport"))
        #expect(source.contains("routedPlanningComplete"))
        #expect(source.contains("routedSubagentTransport"))
        // Every routed helper journals its node, including failures.
        #expect(source.contains("recordRouteJournalEntry"))
    }

    @Test("Planner accepts the routed completion closure")
    func planningServiceHasCompletePassthrough() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/TurnContextPlanningService.swift")
        #expect(source.contains("complete:"))
    }

    @Test("Planner passthrough really reaches InternalContextPlanner")
    func planningServiceUsesInjectedComplete() async {
        let flag = CompletionFlag()
        let result = await TurnContextPlanningService.plan(
            message: "fix the bug",
            board: ContextBoard(projectPath: "/nonexistent-routing-test", entries: [], builtAt: Date()),
            memories: [],
            records: [],
            priorTurns: [],
            ledger: nil,
            complete: { _ in
                await flag.set()
                return "{}"
            }
        )
        #expect(await flag.wasCalled)
        if case .fallback(let reason) = result.status {
            #expect(reason == "empty internal plan")
        } else {
            Issue.record("Injected complete must be used; got status \(result.status)")
        }
    }

    @Test("Deleting a chat clears its route journal and chat override")
    func deleteSessionCleansRoutingState() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/App/AppState+StorageMaintenance.swift")
        guard let range = source.range(of: "func deleteSessionInDatabaseUI") else {
            Issue.record("deleteSessionInDatabaseUI missing")
            return
        }
        let tail = source[range.lowerBound...]
        #expect(tail.contains("ModelRouteJournalStore"))
        #expect(tail.contains("clearChat(sessionID:"))
    }

    @Test("Routing menu is wired into the composer input controls")
    func menuWiredIntoInputControls() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Components/InputControls.swift")
        #expect(source.contains("ModelRoutingMenu()"))
    }

    @Test("Routing menu exposes mode, scope, roles, warnings, bulk actions and journal")
    func menuCoversChecklist() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/Components/ModelRoutingMenu.swift")
        #expect(source.contains("Применить ко всем"))
        #expect(source.contains("Сбросить к единой"))
        #expect(source.contains("chainPreview"))
        #expect(source.contains("modelRoutingUsesMultipleProviders"))
        #expect(source.contains("modelRouteJournal"))
        #expect(source.contains("catalogVisionSupport"))
        // Capability badges come from the catalog, never from the model name.
        #expect(source.contains("ModelMetadataResolver.resolve"))
        // Pre-send warnings for shapes that cannot execute.
        #expect(source.contains("webUnsupported"))
    }
}
