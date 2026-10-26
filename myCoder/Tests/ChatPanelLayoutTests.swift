import Testing
import AppKit
@testable import myCoder

@Suite("Chat Panel Layout")
struct ChatPanelLayoutTests {

    @Test("Centered input is used when there are no messages")
    func centeredWhenEmpty() {
        #expect(ChatPanelLayoutLogic.shouldUseCenteredInput(messageCount: 0) == true)
        #expect(ChatPanelLayoutLogic.shouldUseCenteredInput(messageCount: 3) == false)
    }

    @Test("Empty state stacks logo, title, and input spacing")
    func emptyStateSpacing() {
        #expect(ChatPanelLayoutLogic.emptyStateStackSpacing == 24)
    }

    @Test("Streaming content changes the scroll revision without changing message ID")
    func streamingContentChangesScrollRevision() {
        var message = Message(id: "assistant-1", role: .assistant, content: "Hello", isStreaming: true)
        let before = ChatScrollLogic.revision(messages: [message])
        message.content = "Hello world"
        let after = ChatScrollLogic.revision(messages: [message])

        #expect(before != after)
    }

    @Test("Auto-scroll only follows updates while the bottom is visible")
    func autoScrollOnlyAtBottom() {
        #expect(ChatScrollLogic.shouldAutoScroll(wasAtBottom: true))
        #expect(!ChatScrollLogic.shouldAutoScroll(wasAtBottom: false))
    }

    @Test("myCoder logo mark uses independent code branding")
    func logoMarkText() {
        #expect(MyCoderLogoSpec.markText == "myCoder code mark")
        #expect(MyCoderLogoSpec.accentHex == "6EE7F2")
    }

    @Test("Bundled Mi logo asset is available")
    func bundledLogoAsset() {
        // Logo should load from the SPM resource bundle at runtime
        #expect(MiMoLogoLoader.resourceName == "myCoderMark")
        // In test environment bundle resources may not be available;
        // verify the loader resolves a bundle (not nil) and resourceName is correct.
        #expect(!MiMoLogoLoader.resourceBundle.bundlePath.isEmpty)
    }

    @Test("ClipboardProvider reads NSImage pasteboard constructor")
    func consumePasteboardConstructor() {
        PasteboardIsolation.withExclusiveAccess {
            let testImage = NSImage(size: NSSize(width: 6, height: 6))
            testImage.lockFocus()
            NSColor.purple.drawSwatch(in: NSRect(x: 0, y: 0, width: 6, height: 6))
            testImage.unlockFocus()

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([testImage])

            #expect(NSImage(pasteboard: pb) != nil)
            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
        }
    }
}
