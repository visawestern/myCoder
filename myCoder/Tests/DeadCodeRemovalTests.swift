import Testing
import Foundation
@testable import myCoder

@Suite("Dead Code Removal")
struct DeadCodeRemovalTests {

    @Test("GoalPanelView (dead view with zero call sites) is removed from Sources")
    func goalPanelViewRemoved() throws {
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        var offenders: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if content.contains("GoalPanelView") {
                offenders.append(url.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty, "GoalPanelView still referenced in: \(offenders)")
    }
}
