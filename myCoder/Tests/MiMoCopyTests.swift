import Testing
@testable import myCoder

@Suite("MiMo Copy")
struct MiMoCopyTests {
    
    @Test("Prompt placeholder uses myCoder branding")
    func promptPlaceholder() {
        // Round 7: rebrand — the placeholder now reads "Ask myCoder anything…".
        #expect(MiMoCopy.promptPlaceholder(language: .english).contains("Ask myCoder anything"))
        #expect(!MiMoCopy.promptPlaceholder(language: .english).contains("ZCode"))
        #expect(!MiMoCopy.promptPlaceholder(language: .english).contains("Ask MiMo"))
    }
    
    @Test("Follow-up placeholder is set")
    func followUpPlaceholder() {
        #expect(MiMoCopy.followUpPlaceholder(language: .english) == "Ask for follow-up changes")
    }
    
    @Test("Watermark text is mi")
    func watermark() {
        #expect(MiMoCopy.watermarkText == "mi")
    }
    
    @Test("Empty state title includes workspace name")
    func emptyStateTitle() {
        #expect(MiMoCopy.emptyStateTitle(workspaceName: "mimo-macos", language: .english) == "Start a new task in mimo-macos")
    }
}
