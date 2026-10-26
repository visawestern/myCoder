import Foundation
#if canImport(WebKit)
import WebKit

/// Round 30 — maximally permissive embedded-browser policy.
///
/// Vendors region-redirect their chat pages (kimi.com → kimi.ai outside China).
/// The embedded WKWebView previously had NO navigation/UI delegates, so:
///   • top-level redirects worked, but `window.open` / `target=_blank` hops —
///     the way kimi.ai handoff is often implemented — were silently dropped;
///   • a blocked JS alert/confirm/prompt could freeze page scripts.
/// This policy allows every navigation/response regardless of host or scheme,
/// re-loads popup requests in the SAME view (in-place redirect), adopts truly
/// unresolvable popups as new views instead of dropping them, and auto-answers
/// JS dialogs so automated pages never hang.

/// Pure decision logic (unit-testable without WebKit objects).
enum WebPopupPolicy {
    enum PopupAction: Equatable {
        /// Navigate the originating web view to this URL in place.
        case loadInPlace(String)
        /// No recoverable URL: adopt the popup as a real new view.
        case adoptNewView
        /// OAuth/identity popup: must open in a real VISIBLE window, never
        /// in-place (it would wipe the vendor page) and never as an
        /// unattached view (the user could not see or complete the login).
        case showInWindow(String?)
    }

    /// Identity/OAuth hosts whose popups are the actual login flow. Live
    /// evidence (2026-09-06, kimi.ai → Google sign-in): the Google button
    /// opens window.open('accounts.google.com/...') — an in-place load
    /// destroyed the Kimi page, and an unattached adopted view left the
    /// user with nothing to click.
    static let oauthHosts: Set<String> = [
        "accounts.google.com", "accounts.youtube.com",
        "appleid.apple.com", "id.microsoft.com", "login.microsoftonline.com",
        "login.live.com", "auth0.com", "auth.anthropic.com",
        "auth.openai.com", "auth.moonshot.cn", "platform.openai.com"
    ]

    static func isOAuthURL(_ raw: String?) -> Bool {
        guard let raw,
              let url = URL(string: raw),
              let host = url.host?.lowercased() else { return false }
        return oauthHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func popupAction(requestURL: String?) -> PopupAction {
        if isOAuthURL(requestURL) {
            return .showInWindow(requestURL)
        }
        guard let raw = requestURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme != nil, !url.scheme!.isEmpty else {
            return .adoptNewView
        }
        return .loadInPlace(raw)
    }

    static func promptResponse(defaultText: String?) -> String {
        defaultText ?? ""
    }
}

#if canImport(AppKit)
@MainActor
final class PermissiveWebNavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var ownerWebView: WKWebView?
    /// Visible popup windows created for OAuth flows; retained so they stay
    /// alive and cleaned up when closed.
    private var popupWindows: [NSWindow: WKWebView] = [:]

    init(ownerWebView: WKWebView? = nil) {
        self.ownerWebView = ownerWebView
        super.init()
    }

    // MARK: Navigation — allow everything

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }

    // MARK: Popups — OAuth in a VISIBLE window; same-view redirect otherwise

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        switch WebPopupPolicy.popupAction(requestURL: navigationAction.request.url?.absoluteString) {
        case .loadInPlace(let url):
            if let u = URL(string: url) {
                webView.load(URLRequest(url: u))
            }
            return nil
        case .showInWindow:
            // A real, visible, key window so the user can complete the
            // Google/Apple/Microsoft login. Cookies are shared through the
            // configuration's website data store, so finishing the popup
            // returns the vendor page already authenticated.
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: configuration)
            // Google refuses OAuth in embedded/unknown browsers ("This
            // browser or app may not be secure") — present the standard
            // desktop Safari identity, same engine family as WKWebView.
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            wv.navigationDelegate = self
            wv.uiDelegate = self
            // Do NOT manually load the URL: when a webview is returned from
            // createWebViewWith, WebKit performs the pending navigation itself;
            // a second manual load raced it and produced a blank page (live
            // evidence 2026-09-06). For nil-URL popups (window.open('') +
            // JS navigation — exactly how Google starts OAuth) the opener's
            // JS navigation must be the ONLY load.
            let window = NSWindow(contentRect: wv.frame,
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Login"
            window.contentView = wv
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.delegate = self
            popupWindows[window] = wv
            return wv
        case .adoptNewView:
            // Any popup WebKit could not resolve to a URL still deserves to
            // be VISIBLE: window.open('') + JS navigation is exactly how
            // Google starts its OAuth flow. An unattached webview is a black
            // hole the user can never reach.
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: configuration)
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            wv.navigationDelegate = self
            wv.uiDelegate = self
            let window = NSWindow(contentRect: wv.frame,
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Login"
            window.contentView = wv
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.delegate = self
            popupWindows[window] = wv
            return wv
        }
    }

    // MARK: JS dialogs — auto-answer so pages never hang

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(WebPopupPolicy.promptResponse(defaultText: defaultText))
    }
}

extension PermissiveWebNavigationPolicy: NSWindowDelegate {
    /// Tidy up when a login popup window closes.
    nonisolated func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        Task { @MainActor in
            if let window { _ = self.popupWindows.removeValue(forKey: window) }
        }
    }
}
#endif
#endif
