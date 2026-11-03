import Foundation

/// Единственный производственный транспорт myCoder — AntiBrowser
/// (CDP 9222 + REST 5390). Поле `WebTransport` в конфиге осталось от старой
/// конфигурации WKWebView; фактический движок всегда один, поэтому метки
/// честно отражают AntiBrowser.
enum WebTransportRuntimeLogic {
    static func effectiveTransport(for requested: WebTransport) -> WebTransport {
        .cdpCookies
    }

    static func label(for requested: WebTransport) -> String {
        switch requested {
        case .playwrightMCP, .cdpCookies:
            return "AntiBrowser (CDP + REST)"
        }
    }
}
