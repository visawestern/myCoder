import Testing
import Foundation
@testable import myCoder

@MainActor
@Suite("Dead Code Removal")
struct DeadCodeRemovalTests {

    @Test("GoalPanelView (dead view with zero call sites) is removed from Sources")
    func goalPanelViewRemoved() throws {
        let offenders = try RepoRoot.allSwiftSourceTexts()
            .filter { $0.contents.contains("GoalPanelView") }
            .map { URL(fileURLWithPath: $0.path).lastPathComponent }
        #expect(offenders.isEmpty, "GoalPanelView still referenced in: \(offenders)")
    }
}
