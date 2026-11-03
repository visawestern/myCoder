import Foundation

/// Идентификатор вкладки браузера, показываемой в мини-касте чата.
/// Тройка (provider, project, chat) маппится 1:1 на вкладку AntiBrowser
/// (`AntiBrowserTabManager.makeKey`): у каждого чата своя вкладка, и при
/// повторном входе в чат вкладка переиспользуется.
struct WebBrowserPanelConfig: Equatable {
    let providerID: String
    let providerName: String
    let projectID: String
    let chatID: String
}
