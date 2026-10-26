import Foundation

/// Pure validation for a remote browser conversation identity. A remote chat
/// binding may be persisted only after one of these values is observed from the
/// provider's current page; local UUIDs and page headings are never accepted.
enum WebRemoteChatIdentityLogic {
    static func firstValid(_ candidates: [String]) -> String? {
        var seen = Set<String>()
        for raw in candidates {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  value.count >= 4,
                  value.count <= 200,
                  value.rangeOfCharacter(from: .letters) != nil,
                  !value.contains("/"),
                  !value.contains("?"),
                  !value.contains("#"),
                  // Audit 2026-09-08: Kimi sidebar/DOM exposed URL query
                  // fragments ("chat_enter_method=history") as candidate ids;
                  // a conversation id never carries query syntax.
                  !value.contains("="),
                  !value.contains("&"),
                  !value.contains("%"),
                  // Audit 2026-09-08 (ChatGPT): per-turn client keys
                  // ("WEB:<uuid>", "request-WEB:<uuid>-0") leaked from turn
                  // containers into candidates. A conversation id is a URL
                  // path segment — it never contains a colon.
                  !value.contains(":"),
                  !isPlaceholder(value),
                  seen.insert(value).inserted else { continue }
            return value
        }
        return nil
    }

    /// Extract the conversation id from a vendor URL string (`/chat/{id}`,
    /// `/c/{id}`), or nil. Pure counterpart of the driver's URL branch —
    /// callers that already approved the URL must derive the id from THAT
    /// SAME string instead of re-reading the live URL (audit 2026-09-08: two
    /// separate `currentURL()` reads raced across a SPA navigation commit —
    /// the gate saw `/c/{uuid}` while the extractor saw `""` and fell back
    /// to a stale sidebar DOM id).
    static func chatIDFromURL(_ urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        for pattern in ["/chat/", "/c/"] {
            guard let range = urlString.range(of: pattern) else { continue }
            let after = urlString[range.upperBound...]
            let part = after.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
                .first.map(String.init) ?? ""
            if let chatID = firstValid([part]) { return chatID }
        }
        return nil
    }

    static func canonicalURL(baseURL: String, vendor: WebChatVendor, chatID: String) -> String? {        guard firstValid([chatID]) != nil,
              var components = URLComponents(string: baseURL),
              components.scheme != nil,
              components.host != nil else { return nil }
        let escapedID = chatID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chatID
        components.path = vendor == .chatgpt ? "/c/\(escapedID)" : "/chat/\(escapedID)"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let lower = value.lowercased()
        // Audit 2026-09-08: live Kimi exposed the history list page
        // (/chat/history); taking the trailing path segment as the "chat id"
        // bound every future send to a non-conversation URL. Route literals
        // and navigation destinations are never conversation identities.
        let placeholders = ["chat", "conversation", "session", "undefined", "null",
                            "none", "new-chat", "new conversation",
                            "history", "new", "search", "settings", "login",
                            "auth", "profile", "pricing", "upgrade", "premium"]
        return placeholders.contains(lower)
    }
}
