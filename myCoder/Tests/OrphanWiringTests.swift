import Testing
import Foundation

// ═══════════════════════════════════════════════════════════════════════════
// Round-7 orphan-wiring RED tests.
//
// The recurring root cause every prior audit round claimed to have eliminated
// ("logic written & tested but never wired into the app") is still present for a
// concrete cluster of modules. These tests assert those modules are invoked from
// LIVE (non-test) source — App/ and Views/ — not merely from their own test file.
//
// They are RED on the unmodified baseline (the orphans are unwired) and turn
// GREEN only once the wiring lands. They are source-inspection lints (the App/
// View files are macOS-only and cannot execute on Linux), so they run in the
// Foundation-only harness and guard against regressions to "defined but dead".
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Round 7: orphan wiring")
struct OrphanWiringTests {

    /// Concatenated text of every LIVE source file (App + Services + Views +
    /// Models + Theme), i.e. everything under myCoder/Sources EXCEPT the file that
    /// defines the symbol itself. Used to prove a symbol has a real call site.
    private func liveSources(excluding excludedFileName: String) throws -> String {
        let root = RepoRoot.url.appendingPathComponent("myCoder/Sources")
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return "" }
        var combined = ""
        for case let u as URL in en where u.pathExtension == "swift" {
            if u.lastPathComponent == excludedFileName { continue }
            combined += (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            combined += "\n"
        }
        return combined
    }

    // R7-05: the per-project undo/history cluster must be referenced by live code.
    @Test("ProjectUndoManager is wired into live source")
    func projectUndoManagerWired() throws {
        let live = try liveSources(excluding: "ProjectUndoManager.swift")
        #expect(live.contains("ProjectUndoManager"),
                "ProjectUndoManager is an orphan — defined & tested but never invoked from App/Views.")
    }

    @Test("ProjectHistoryExporter is wired into live source")
    func projectHistoryExporterWired() throws {
        let live = try liveSources(excluding: "ProjectHistoryExporter.swift")
        #expect(live.contains("ProjectHistoryExporter"),
                "ProjectHistoryExporter is an orphan — no live call site.")
    }

    // NOTES on lower-severity orphans, deliberately NOT asserted here:
    //  • ChatPasteRoutingLogic (R7-07): a dead duplicate of the live
    //    PasteRoutingDecision path. It still has its own passing test suite
    //    ("Chat Paste Routing"), so deleting it is a separate, compile-verified
    //    step — tracked in the Round 7 doc, not force-failed here.
    //  • InputFieldHeightLogic (R7-08): unused utility with a passing suite
    //    ("Input field height"); same reasoning.
    //  • GitignoreEntryLogic: intentionally NOT auto-wired — its own docstring
    //    says it must only run on explicit user action (a feature not yet built),
    //    so it is a documented pending-feature, not an orphan defect.
}
