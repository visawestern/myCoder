import Testing
import AppKit
@testable import myCoder

@Suite("Paste Debug Trace")
struct PasteDebugTraceTests {

    @Test("Debug disabled unless MIMO_DEBUG_PASTE=1")
    func debugDisabledByDefault() {
        #expect(PasteDebugSettings.isEnabled == (ProcessInfo.processInfo.environment["MIMO_DEBUG_PASTE"] == "1"))
    }

    @Test("describePasteboard includes types")
    func describePasteboard() {
        PasteboardIsolation.withExclusiveAccess {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("hello", forType: .string)
            let description = PasteDebugTrace.describePasteboard(pb)
            #expect(description.contains("string"))
            #expect(description.contains("stringChars=5"))
        }
    }
}
