import Testing
import Foundation
@testable import myCoder

/// Round 28 (Settings split quality): the monolithic SettingsView.swift was
/// split into myCoder/Sources/Views/Settings/ (Round 27). These source-inspection
/// tests guard the split's invariants:
///   1. the shared `emptyState` helper is defined ONCE, not copy-pasted into
///      every Settings sub-view;
///   2. no dead/unreferenced state variables were carried over by the split.
@Suite("Settings Split Quality")
struct SettingsSplitQualityTests {

    private static let settingsFolder: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Views/Settings")
    }()

    private static func settingsSwiftSources() throws -> [URL: String] {
        let fm = FileManager.default
        guard let urls = fm.enumerator(at: settingsFolder, includingPropertiesForKeys: nil)?.allObjects as? [URL] else {
            return [:]
        }
        var out: [URL: String] = [:]
        for url in urls where url.pathExtension == "swift" {
            out[url] = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return out
    }

    @Test("the shared emptyState helper is defined exactly once in the root SettingsView.swift, never duplicated in the Settings folder")
    func emptyStateDefinedOnce() throws {
        // The shared helper must live in the root file (where SettingsCard and
        // SettingsRow live) and must NOT be re-declared per sub-view.
        let root = try RepoRoot.sourceText("myCoder/Sources/Views/SettingsView.swift")
        let rootDefs = root.ranges(of: "func settingsEmptyState(").count
        #expect(rootDefs == 1,
                "settingsEmptyState must be defined exactly once in SettingsView.swift (found \(rootDefs))")

        let sources = try Self.settingsSwiftSources()
        var folderDefs: [String] = []
        for (url, content) in sources {
            if content.contains("func settingsEmptyState(") || content.contains("func emptyState(") {
                folderDefs.append(url.lastPathComponent)
            }
        }
        #expect(folderDefs.isEmpty,
                "emptyState is still defined in the Settings folder: \(folderDefs) — must live only in SettingsView.swift")
    }

    @Test("no dead selectedProjectFilter state survives the split")
    func noDeadSelectedProjectFilter() throws {
        let sources = try Self.settingsSwiftSources()
        for (url, content) in sources {
            // A live @State var is referenced at least twice: its declaration
            // AND at least one read/write in body/functions. Exactly one
            // occurrence means declared-but-never-used = dead code.
            let uses = content.ranges(of: "selectedProjectFilter").count
            #expect(uses != 1,
                    "\(url.lastPathComponent) references selectedProjectFilter \(uses) time(s) — a @State var used only at its declaration is dead")
        }
    }
}
