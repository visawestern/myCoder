import Foundation
import SwiftUI
#if canImport(WebKit)
import WebKit
import AppKit
#endif

/// Identity of the webview shown in the in-chat mini browser panel
/// (user directive 2026-09-09). The (project, chat, provider) triple maps
/// 1:1 to a pooled WKWebView — the same "several tabs of one site, one per
/// chat/project" model the browser pool already uses.
struct WebBrowserPanelConfig: Equatable {
    let providerID: String
    let providerName: String
    let projectID: String
    let chatID: String
}

#if canImport(WebKit)
/// Keeps offscreen WKWebViews alive when they are not attached to the
/// visible mini-browser panel. A WKWebView removed from any window stops
/// rendering and can be reclaimed; parking it in a borderless offscreen
/// host window preserves the live page (cookies, conversation, stream)
/// until the next web-provider turn re-parents it.
@MainActor
enum WebBrowserHostWindow {
    private static var host: NSWindow?

    static func park(_ webView: WKWebView) {
        ensureHost().contentView = webView
    }

    private static func ensureHost() -> NSWindow {
        if let host { return host }
        let window = NSWindow(
            contentRect: NSRect(x: -2000, y: 0, width: 1280, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        self.host = window
        return window
    }
}

/// SwiftUI wrapper that RE-PARENTS the pooled WKWebView into the visible
/// panel (user directive 2026-09-09). On disappear the webview is parked in
/// the hidden host window — never destroyed — so the vendor page keeps its
/// login/session/conversation between requests and chats.
struct WebProviderBrowserPanelRepresentable: NSViewRepresentable {
    let webView: WKWebView
    let config: WebBrowserPanelConfig

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.identifier = NSUserInterfaceItemIdentifier("mycoder-web-browser-panel")
        reattach(into: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        reattach(into: container)
    }

    /// Move the webview into this panel if it is not already here. Removing
    /// from the previous parent is safe: reparenting keeps the WKWebView
    /// instance (and its web content process) alive.
    private func reattach(into container: NSView) {
        if webView.superview === container { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        // Park every live webview child in the hidden host so its page
        // survives while the panel is not visible.
        for sub in container.subviews where sub is WKWebView {
            if let wv = sub as? WKWebView {
                WebBrowserHostWindow.park(wv)
            }
        }
    }
}
#endif
