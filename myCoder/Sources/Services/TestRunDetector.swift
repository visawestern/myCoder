import Foundation

/// One process-wide answer to "are we running under a test runner?".
///
/// Audit 2026-09-13 (user DB pollution): `AppState.isRunningTests` only
/// probed `XCTestCase`, but the suite runs via swift-testing — which does
/// NOT link XCTest into the runner process. The detector returned false, so
/// 245 junk sessions ("New Chat" / "merge me" / "Quick question" /
/// "API Chat") accumulated in the REAL ~/.mycoder/mycoder.db across 106 test
/// runs (verified live in the user's database). The probe now detects the
/// swift-testing runtime classes too, plus an explicit env escape hatch.
enum TestRunDetector {
    /// True when the process is a test runner (XCTest OR swift-testing),
    /// or when MIMO_TEST_MODE=1 is set explicitly.
    static let isRunningTests: Bool = {
        if ProcessInfo.processInfo.environment["MIMO_TEST_MODE"] == "1" { return true }
        if NSClassFromString("XCTestCase") != nil { return true }
        if NSClassFromString("XCTest.XCTestCase") != nil { return true }
        // swift-testing runner (swift test on macOS): the Testing module is
        // loaded into the process before any @Test executes.
        if NSClassFromString("Testing.EntryTest") != nil { return true }
        if NSClassFromString("Testing.SwiftTestingDiscovery") != nil { return true }
        return false
    }()
}
