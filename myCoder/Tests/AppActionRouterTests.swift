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
}
