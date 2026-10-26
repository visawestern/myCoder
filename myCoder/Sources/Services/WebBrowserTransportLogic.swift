import Foundation

enum WebBrowserTransportLogic {
    enum NavigationOutcome: Equatable {
        case ready
        case timedOut
    }

    static let navigationTimeoutMessage =
        "The browser page did not become ready before the navigation timeout."

    static func navigationOutcome(documentReady: Bool) -> NavigationOutcome {
        documentReady ? .ready : .timedOut
    }
}

enum WebCookieRestoreLogic {
    struct Attributes: Equatable {
        let secure: Bool
        let httpOnly: Bool
    }

    static func attributes(for cookie: BrowserCookie) -> Attributes {
        Attributes(secure: cookie.secure, httpOnly: cookie.httpOnly)
    }
}
