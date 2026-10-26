import Foundation

enum WebTransportRuntimeLogic {
    static func effectiveTransport(for requested: WebTransport) -> WebTransport {
        // The production send path is backed by an isolated WKWebView. CDP is
        // retained only for decoding older configurations and cannot claim that
        // an external Chrome instance is attached.
        .playwrightMCP
    }

    static func label(for requested: WebTransport) -> String {
        switch requested {
        case .playwrightMCP:
            return "In-app WKWebView"
        case .cdpCookies:
            return "In-app WKWebView (Chrome CDP unavailable)"
        }
    }
}
