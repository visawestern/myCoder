import Foundation
import Testing
@testable import myCoder

/// TDD for plan item 5: the browser profile must be a single persistent
/// profile with session restore disabled, no crash-restore prompt, no startup
/// window, and an off-screen window placement (the browser is viewed through
/// myCoder's Chromecast/panel, so it needs no standalone presence).
@Suite("Engine profile preparation — single profile, no restore prompts")
struct EngineProfilePreparationTests {

    @Test("First launch gets all guarantees")
    func appliesGuarantees() {
        let result = EngineProfilePreparation.apply(localState: [:], preferences: [:])
        let ls = result.localState
        #expect(ls["first_run_completed"] as? Bool == true)
        #expect((ls["antibrowser"] as? [String: Any])?["no_startup_window"] as? Bool == true)

        let prefs = result.preferences
        #expect((prefs["session"] as? [String: Any])?["restore_on_startup"] as? Int == 4)
        #expect((prefs["session"] as? [String: Any])?["crashed"] == nil)
        #expect(EngineProfilePreparation.isWindowOffScreen(preferences: prefs))
    }

    @Test("Existing keys are overwritten, unrelated keys are kept")
    func preservesUnrelatedKeys() {
        let result = EngineProfilePreparation.apply(
            localState: ["first_run_completed": false, "custom": "kept"],
            preferences: [
                "session": ["restore_on_startup": 1, "crashed": true, "tab": "x"],
                "browser": ["window_placement": ["left": 100]],
                "other": 5,
            ]
        )
        #expect(result.localState["custom"] as? String == "kept")
        let prefs = result.preferences
        #expect((prefs["session"] as? [String: Any])?["tab"] as? String == "x")
        #expect((prefs["session"] as? [String: Any])?["restore_on_startup"] as? Int == 4)
        #expect((prefs["session"] as? [String: Any])?["crashed"] == nil)
        #expect(prefs["other"] as? Int == 5)
        #expect(EngineProfilePreparation.isWindowOffScreen(preferences: prefs))
    }

    @Test("Single profile directory constant is stable")
    func singleProfileConstant() {
        #expect(EngineProfilePreparation.profileDirectoryName == "AntiBrowserProfile")
    }

    @Test("Application is idempotent")
    func idempotent() {
        let once = EngineProfilePreparation.apply(localState: [:], preferences: [:])
        let twice = EngineProfilePreparation.apply(
            localState: once.localState,
            preferences: once.preferences
        )
        #expect((twice.localState["first_run_completed"] as? Bool) == true)
        #expect((twice.preferences["session"] as? [String: Any])?["restore_on_startup"] as? Int == 4)
        #expect(EngineProfilePreparation.isWindowOffScreen(preferences: twice.preferences))
    }
}
