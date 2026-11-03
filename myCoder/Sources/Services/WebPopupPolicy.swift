import Foundation

/// Решение о том, что делать с попапом:
/// - `.loadInPlace(url)` — грузить по этому URL в текущей вкладке;
/// - `.adoptNewView` — проигнорировать/открыть пустую вкладку (нет URL);
/// - `.showInWindow(url)` — открыть в отдельном видимом окне браузера
///   (identity-провайдеры: OAuth-окна, иначе затирается вендорская страница).
enum WebPopupAction: Equatable {
    case loadInPlace(String)
    case adoptNewView
    case showInWindow(String)
}

/// Чистая политика работы с попапами (без зависимости от WebKit).
enum WebPopupPolicy {

    /// Хосты identity-провайдеров, чьи попапы должны открываться в окне.
    static let oauthHostSuffixes: [String] = [
        "accounts.google.com",
        "appleid.apple.com",
        "login.microsoftonline.com",
    ]

    static func isOAuthURL(_ url: String?) -> Bool {
        guard let url,
              let host = URL(string: url)?.host?.lowercased() else {
            return false
        }
        if oauthHostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return true
        }
        // Auth0-тенанты: <tenant>.auth0.com
        return host.hasSuffix(".auth0.com")
    }

    static func popupAction(requestURL: String?) -> WebPopupAction {
        guard let raw = requestURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .adoptNewView
        }
        guard let url = URL(string: raw), url.scheme != nil else {
            return .adoptNewView
        }
        if isOAuthURL(raw) {
            return .showInWindow(raw)
        }
        return .loadInPlace(raw)
    }

    static func promptResponse(defaultText: String?) -> String {
        defaultText ?? ""
    }
}
