import Foundation

enum WebBrowserStopRoutingLogic {
    static func targetKey(projectID: String,
                          chatID: String,
                          providerID: String,
                          activeSessionID: String) -> WebBrowserInstanceKey {
        WebBrowserInstanceKey(
            projectID: projectID,
            chatID: chatID,
            providerID: providerID,
            activeSessionID: activeSessionID
        )
    }
}
