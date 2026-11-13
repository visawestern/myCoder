import Foundation

/// Deterministic preparation of the AntiBrowser engine's profile (plan item
/// 5, user directive 2026-11-13):
///   • the SAME persistent profile is always used — a login survives restarts,
///     no re-login is ever asked again;
///   • no window/tab restoration and no "Restore pages?" prompt — the session
///     restore mode is off and the crash flag is cleared;
///   • no startup window (the browser appears only from myCoder);
///   • the engine window is placed off-screen (it is viewed through myCoder's
///     Chromecast/panel, never as a standalone window).
///
/// Pure: takes the two profile JSON dictionaries and returns their updated
/// copies. `BrowserProcess` writes them to disk. Fully testable without a
/// real profile on disk.
enum EngineProfilePreparation {

    struct Result {
        let localState: [String: Any]
        let preferences: [String: Any]
    }

    /// The shared profile directory is a single constant — one profile for
    /// every launch (login persistence).
    static let profileDirectoryName = "AntiBrowserProfile"

    /// Apply every guarantee to copies of the two profile dictionaries.
    ///
    /// Input: `Local State` and `Default/Preferences` JSON dictionaries (may
    /// be empty for a first launch).
    /// Output: updated copies with the guarantees above.
    /// Dependencies: none (pure dictionary transforms).
    static func apply(localState: [String: Any],
                      preferences: [String: Any]) -> Result {
        var ls = localState
        ls["first_run_completed"] = true
        var ab = ls["antibrowser"] as? [String: Any] ?? [:]
        ab["no_startup_window"] = true
        ls["antibrowser"] = ab

        var prefs = preferences
        var session = prefs["session"] as? [String: Any] ?? [:]
        // 4 = never restore windows/session on startup (Chromium UIThread).
        session["restore_on_startup"] = 4
        // Clear the crash flag so the "Restore pages?" bubble never appears.
        session.removeValue(forKey: "crashed")
        prefs["session"] = session
        var browser = prefs["browser"] as? [String: Any] ?? [:]
        browser["window_placement"] = [
            "left": -4000,
            "top": 0,
            "width": 1280,
            "height": 800,
        ]
        prefs["browser"] = browser
        return Result(localState: ls, preferences: prefs)
    }

    /// Whether the browser window placement is off-screen (left < 0).
    static func isWindowOffScreen(preferences: [String: Any]) -> Bool {
        guard let browser = preferences["browser"] as? [String: Any],
              let placement = browser["window_placement"] as? [String: Any],
              let left = placement["left"] as? Int else {
            return false
        }
        return left < 0
    }
}
