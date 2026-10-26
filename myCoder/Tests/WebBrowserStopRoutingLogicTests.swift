import Testing
@testable import myCoder

@Suite("WEB-05 active browser stop routing")
struct WebBrowserStopRoutingLogicTests {
    @Test("stop target preserves the active project/chat/provider/session identity")
    func stopTargetPreservesActiveIdentity() {
        let key = WebBrowserStopRoutingLogic.targetKey(
            projectID: "project-1",
            chatID: "chat-9",
            providerID: "qwen",
            activeSessionID: "login-2"
        )
        #expect(key == WebBrowserInstanceKey(
            projectID: "project-1",
            chatID: "chat-9",
            providerID: "qwen",
            activeSessionID: "login-2"
        ))
    }

    @Test("stop target never falls back to provider-default when active chat exists")
    func stopTargetDoesNotUseProviderDefault() {
        let key = WebBrowserStopRoutingLogic.targetKey(
            projectID: "project-1",
            chatID: "chat-9",
            providerID: "qwen",
            activeSessionID: "default"
        )
        #expect(key.chatID != "provider-default")
        #expect(key.projectID == "project-1")
    }
}
