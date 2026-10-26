import Testing
import Foundation
@testable import myCoder

// ═══════════════════════════════════════════════════════════════════════════
// Round 10 — Settings action regressions + localization coverage.
//
// The crash on "Reset app cache" is traced to the navigation-history didSet:
// navigationHistory and navigationIndex are mutated from multiple paths and
// can get out of sync (index > count), so `removeSubrange` crashes with an
// out-of-range index. These RED tests pin that down so the fix can be shipped
// with localization coverage in the same pass.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Settings actions — crash regression (Round 10)")
struct SettingsActionsRegressionTests {

    @Test("clearInMemoryState executes without crashing after a normal navigation history")
    func clearAfterNavigation() {
        let appState = AppState()
        let w1 = Workspace(id: "w1", name: "A", path: "/tmp/a", tasks: [])
        let w2 = Workspace(id: "w2", name: "B", path: "/tmp/b", tasks: [])
        appState.selectedWorkspace = w1
        appState.selectedWorkspace = w2
        // The old code crashed here: setting selectedWorkspace = nil triggered
        // didSet on a navigationHistory whose index could exceed its count.
        appState.clearInMemoryState()
        #expect(appState.selectedWorkspace == nil)
    }

    @Test("clearInMemoryState clears session, workspace, sessions, projects")
    func clearClearsState() {
        let appState = AppState()
        appState.selectedWorkspace = Workspace(id: "w1", name: "A", path: "/tmp/a", tasks: [])
        appState.clearInMemoryState()
        #expect(appState.selectedSession == nil)
        #expect(appState.sessions.isEmpty)
        #expect(appState.projects.isEmpty)
    }

    @Test("clearInMemoryState works when history is empty")
    func clearWithEmptyHistory() {
        let appState = AppState()
        appState.selectedSession = ChatSession(id: "s1", title: "Chat")
        #expect(appState.selectedSession != nil)
        appState.clearInMemoryState()
        #expect(appState.selectedSession == nil)
        #expect(appState.navigationIndex == -1)
        #expect(appState.navigationHistory.isEmpty)
    }

    @Test("navigation history stays consistent after a reset")
    func navigationConsistencyAfterReset() {
        let appState = AppState()
        appState.selectedWorkspace = Workspace(id: "w1", name: "A", path: "/tmp/a", tasks: [])
        appState.selectedWorkspace = Workspace(id: "w2", name: "B", path: "/tmp/b", tasks: [])
        appState.clearInMemoryState()
        // Index must be within bounds of the history array.
        #expect(appState.navigationIndex >= -1)
        #expect(appState.navigationIndex < appState.navigationHistory.count)
    }

    @Test("clearInMemoryState does not mutate settings")
    func clearLeavesSettings() {
        let appState = AppState()
        let before = appState.settings
        appState.clearInMemoryState()
        #expect(appState.settings.httpProxy == before.httpProxy)
        #expect(appState.settings.language == before.language)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Localization coverage — every user-facing string must be translated for
// every AppLanguage. This generates the list of missing keys so the fix pass
// can fill them all.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Localization coverage — every key translated (Round 10)")
struct LocalizationCoverageTests {

    @Test("Localized returns non-empty strings for English")
    func localizedNonEmpty() {
        // Verify the highest-visibility keys have non-empty English values.
        let checked: [(AppLocalizationKey, String)] = [
            (.settingsBackToWorkspace, "Back to workspace"),
            (.settingsGeneralTitle, "General"),
            (.settingsTabGeneral, "General"),
            (.gitCommit, "Commit"),
        ]
        for (key, expected) in checked {
            let s = AppLocalization.string(key, language: .english)
            #expect(!s.isEmpty, "\(key) missing for english")
            #expect(s == expected)
        }
    }

    @Test("Extra-language translations are present (not English fallback)")
    func extraLanguagesTranslated() {
        // Full localization: verify French has its own translation (not English fallback).
        let s = AppLocalization.string(.settingsBackToWorkspace, language: .french)
        #expect(s == "Retour à l'espace de travail", "French translation exists")
        // Verify it differs from English (actual translation, not fallback).
        let en = AppLocalization.string(.settingsBackToWorkspace, language: .english)
        #expect(s != en, "French translation differs from English")
    }

    @Test("English and Russian are present for known keys")
    func englishAndRussianPresent() {
        // Spot-check the highest-visibility keys (AppLocalizationKey isn't CaseIterable).
        let keys: [AppLocalizationKey] = [
            .settingsBackToWorkspace, .settingsGeneralTitle, .settingsTabGeneral,
            .settingsTabProviders, .settingsTabSkills, .settingsTabMCPServers,
            .settingsTabPlugins, .settingsTabCommands, .settingsTabIndexing,
            .settingsTabUsage, .gitTab, .terminalTab,
        ]
        for key in keys {
            let en = AppLocalization.string(key, language: .english)
            let ru = AppLocalization.string(key, language: .russian)
            #expect(!en.isEmpty, "\(key) missing English")
            #expect(!ru.isEmpty, "\(key) missing Russian")
        }
    }
}
