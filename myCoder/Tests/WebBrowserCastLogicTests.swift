import Testing
import Foundation
import CoreGraphics
@testable import myCoder

/// CHROMECAST must stay on after the browser panel is hidden: the right-panel
/// PiP thumbnail keeps showing the last live tab. These pure rules decide
/// which tab to cast, when the controller must be replaced, and the thumbnail
/// geometry.
@Suite("Browser cast — always-on tab and PiP thumbnail")
struct WebBrowserCastLogicTests {

    private func config(
        _ provider: String,
        project: String = "p1",
        chat: String = "c1"
    ) -> WebBrowserPanelConfig {
        WebBrowserPanelConfig(
            providerID: provider,
            providerName: provider,
            projectID: project,
            chatID: chat
        )
    }

    @Test("The visible panel tab wins over the remembered cast tab")
    func visiblePanelWins() {
        let visible = config("qwen")
        let remembered = config("kimi")
        #expect(WebBrowserCastLogic.displayConfig(
            panelConfig: visible,
            castConfig: remembered
        ) == visible)
    }

    @Test("A hidden panel keeps the remembered cast tab")
    func hiddenPanelKeepsCasting() {
        let remembered = config("kimi")
        #expect(WebBrowserCastLogic.displayConfig(
            panelConfig: nil,
            castConfig: remembered
        ) == remembered)
        #expect(WebBrowserCastLogic.shouldCast(castConfig: remembered))
        #expect(!WebBrowserCastLogic.shouldCast(castConfig: nil))
    }

    @Test("A new controller is created only when the tab actually changes")
    func controllerReuse() {
        let tab = config("kimi")
        #expect(WebBrowserCastLogic.needsNewController(current: nil, requested: tab))
        #expect(!WebBrowserCastLogic.needsNewController(current: tab, requested: tab))
        #expect(WebBrowserCastLogic.needsNewController(
            current: tab,
            requested: config("kimi", chat: "c2")
        ))
        #expect(WebBrowserCastLogic.needsNewController(current: tab, requested: nil))
    }

    @Test("The PiP thumbnail keeps a 16:9 frame")
    func pipAspectRatio() {
        let size = WebBrowserCastLogic.thumbnailSize(width: 220)
        #expect(size.width == 220)
        #expect(abs(size.height - 123.75) < 0.001)
    }

    @Test("The cast uses the same tab key as the chat bridge")
    func sameTabKey() {
        let tab = config("kimi", project: "proj", chat: "chat")
        #expect(WebBrowserCastLogic.tabKey(for: tab)
                == AntiBrowserTabManager.makeKey(providerID: "kimi",
                                                 projectID: "proj",
                                                 chatID: "chat"))
    }
}
