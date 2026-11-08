import Testing
import Foundation
@testable import myCoder

@Suite("App action router")
struct AppActionRouterTests {

    @Test("The action catalog has unique names and covers core surfaces")
    @MainActor
    func catalogCoverage() {
        let names = AppActionRouter.catalog.compactMap { $0["name"] as? String }
        #expect(names.count == Set(names).count)
        let required = [
            "app.state", "project.create", "project.open", "project.select",
            "wizard.state", "wizard.save", "wizard.answer", "wizard.spec.generate",
            "wizard.decompose", "wizard.node.status", "wizard.node.start", "session.rename", "session.delete",
            "chat.send", "chat.stop", "toolApproval.resolve", "provider.select", "model.select", "ui.tree", "ui.click"
        ]
        for name in required {
            #expect(names.contains(name), "missing action \(name)")
        }
        #expect(names.count >= 45)
    }

    @Test("Каталог содержит действия ЦЕЛЬ и скриншотов (привязанные к UI)")
    @MainActor
    func catalogCoversGoalAndScreenshots() {
        let names = AppActionRouter.catalog.compactMap { $0["name"] as? String }
        let required = [
            "goal.state", "goal.list", "goal.create", "goal.start",
            "goal.pause", "goal.resume", "goal.delete",
            "ui.screenshot", "ui.screenshots.list"
        ]
        for name in required {
            #expect(names.contains(name), "missing action \(name)")
        }
    }

    @Test("Every catalog parameter declares a type and required flag")
    @MainActor
    func catalogParametersAreDocumented() {
        for action in AppActionRouter.catalog {
            let params = action["params"] as? [[String: Any]] ?? []
            for param in params {
                #expect(param["name"] is String)
                #expect(param["type"] is String)
                #expect(param["required"] is Bool)
            }
        }
    }

    @Test("Language aliases map to AppLanguage")
    @MainActor
    func languageAliases() {
        #expect(AppActionRouter.language(named: "ru") == .russian)
        #expect(AppActionRouter.language(named: "Russian") == .russian)
        #expect(AppActionRouter.language(named: "zh") == .chineseSimplified)
        #expect(AppActionRouter.language(named: "klingon") == nil)
    }

    @Test("Unknown actions are rejected")
    @MainActor
    func unknownAction() async {
        let appState = AppState()
        do {
            _ = try await AppActionRouter.shared.perform(
                action: "does.not.exist",
                params: [:],
                appState: appState
            )
            Issue.record("unknown action unexpectedly succeeded")
        } catch {
            #expect(error.localizedDescription.contains("Unknown action"))
        }
    }

    @Test("Управление сжатием контекста доступно по HTTP")
    @MainActor
    func compactionControlActions() async throws {
        final class Box: @unchecked Sendable {
            var action: String?
            var providerID: String?
            var modelID: String?
        }
        let box = Box()
        let appState = AppState()

        let expected = [
            "context.compaction.stop",
            "context.compaction.rollback",
            "context.compaction.retry"
        ]
        let names = AppActionRouter.catalog.compactMap { $0["name"] as? String }
        for name in expected {
            #expect(names.contains(name), "missing action \(name)")
        }
        // The model menu of the banner is a choice too — it must be reachable
        // without the accessibility tree.
        #expect(names.contains("context.compaction.chooseModel"), "missing action context.compaction.chooseModel")

        let token = NotificationCenter.default.addObserver(
            forName: .apiCompactionControlRequested,
            object: nil,
            queue: nil
        ) { notification in
            box.action = notification.userInfo?["action"] as? String
            box.providerID = notification.userInfo?["providerID"] as? String
            box.modelID = notification.userInfo?["modelID"] as? String
        }
        defer { NotificationCenter.default.removeObserver(token) }

        for name in expected {
            box.action = nil
            _ = try await AppActionRouter.shared.perform(
                action: name,
                params: [:],
                appState: appState
            )
            #expect(box.action != nil, "action \(name) did not reach the panel")
        }

        box.action = nil
        box.providerID = nil
        box.modelID = nil
        _ = try await AppActionRouter.shared.perform(
            action: "context.compaction.chooseModel",
            params: ["providerID": "p2", "modelID": "huge"],
            appState: appState
        )
        #expect(box.action == "chooseModel")
        #expect(box.providerID == "p2")
        #expect(box.modelID == "huge")
    }
}
