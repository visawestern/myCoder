import Foundation
import CryptoKit

/// Request context that mirrors the header contract of the official OpenCode
/// client for the `opencode` (Zen) provider.
///
/// Upstream reference: `packages/opencode/src/session/llm/request.ts`
/// (tag v1.19.4) — for OpenCode providers it sends `x-opencode-session-id`,
/// `x-opencode-session`, `x-opencode-request`, `x-opencode-client`,
/// `User-Agent`, and optionally `x-opencode-project` plus parent-session
/// headers. Session/message identifiers use the upstream `ses_`/`msg_` shape
/// (26 characters from the base62 alphabet); project identifiers are 40 hex
/// characters.
struct OpenCodeRequestContext: Equatable {
    static let clientName = "desktop"
    static let userAgent = "opencode/1.19.4 ai-sdk/provider-utils/4.0.23 runtime/bun/1.4.4"
    static let anonymousAuthorization = "Bearer public"

    static let identifierBodyLength = 26
    static let identifierTimeLength = 12
    static let identifierRandomLength = 14
    static let projectIdentifierLength = 40

    private static let identifierAlphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )

    var sessionID: String
    var parentSessionID: String?
    var projectID: String?
    var requestID: String?
    var additionalHeaders: [String: String]

    init(
        sessionID: String,
        parentSessionID: String? = nil,
        projectID: String? = nil,
        requestID: String? = nil,
        additionalHeaders: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.projectID = projectID
        self.requestID = requestID
        self.additionalHeaders = additionalHeaders
    }

    static func generated() -> OpenCodeRequestContext {
        OpenCodeRequestContext(sessionID: identifier(prefix: "ses", descending: true))
    }

    /// Stable per chat: the same raw session id always maps to the same
    /// upstream-shaped identifier, so session affinity survives restarts.
    static func sessionID(from rawID: String, defaults: UserDefaults = .standard) -> String {
        let normalized = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return identifier(prefix: "ses", descending: true)
        }
        if normalized.hasPrefix("ses_"), normalized.count == 4 + identifierBodyLength {
            return normalized
        }
        return OpenCodeSessionIdentifierStore.shared.identifier(for: normalized, defaults: defaults)
    }

    /// Upstream sends the user message id in `x-opencode-request`.
    static func requestID() -> String {
        identifier(prefix: "msg", descending: false)
    }

    /// Upstream sends an opaque 40 hex character project id, never a path.
    static func projectID(fromPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digest = Insecure.SHA1.hash(data: Data(trimmed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Upstream identifier format (`packages/schema/src/identifier.ts`, tag
    /// v1.19.4): 12 hex characters that encode the creation timestamp — the
    /// timestamp is bit-inverted for descending ids — followed by 14 random
    /// base62 characters. Sessions are descending, messages ascending.
    static func identifier(
        prefix: String,
        descending: Bool,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        counter: UInt64 = 1
    ) -> String {
        let current = UInt64(timestamp) * 0x1000 + counter
        let value = descending ? ~current : current
        var time = ""
        for index in 0..<(identifierTimeLength / 2) {
            let byte = UInt8((value >> UInt64(40 - 8 * index)) & 0xff)
            time += String(format: "%02x", byte)
        }
        return "\(prefix)_\(time)\(randomIdentifierSuffix())"
    }

    private static func randomIdentifierSuffix() -> String {
        var generator = SystemRandomNumberGenerator()
        var suffix = ""
        for _ in 0..<identifierRandomLength {
            let byte = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
            suffix += String(identifierAlphabet[Int(byte) % identifierAlphabet.count])
        }
        return suffix
    }

    var affinity: String { sessionID }

    var headers: [String: String] {
        var headers: [String: String] = [
            "x-opencode-session-id": sessionID,
            "x-opencode-session": sessionID,
            "x-opencode-client": Self.clientName,
            "User-Agent": Self.userAgent,
            "Authorization": Self.anonymousAuthorization
        ]
        if let projectID, !projectID.isEmpty {
            headers["x-opencode-project"] = projectID
        }
        if let requestID, !requestID.isEmpty {
            headers["x-opencode-request"] = requestID
        }
        if let parentSessionID, !parentSessionID.isEmpty {
            headers["x-opencode-parent-session-id"] = parentSessionID
            headers["x-parent-session-id"] = parentSessionID
        }
        for (field, value) in additionalHeaders where !field.isEmpty {
            headers[field] = value
        }
        return headers
    }

    func applying(to request: inout URLRequest) {
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    func withRequestID(_ requestID: String?) -> OpenCodeRequestContext {
        var copy = self
        copy.requestID = requestID
        return copy
    }

    func withSessionID(_ sessionID: String) -> OpenCodeRequestContext {
        var copy = self
        copy.sessionID = sessionID
        return copy
    }
}

/// Persisted mapping from a myCoder chat id to the upstream-shaped session id.
/// The upstream reads the creation time out of the identifier itself, so one
/// chat must always reuse the very same session id — a new id would start a
/// new upstream session and lose the conversation context.
final class OpenCodeSessionIdentifierStore: @unchecked Sendable {
    struct Entry: Codable, Equatable {
        var raw: String
        var identifier: String
    }

    static let shared = OpenCodeSessionIdentifierStore()

    private static let defaultsSuffix = "opencode.sessionIdentifiers"
    private static let capacity = 256
    private let lock = NSLock()

    func identifier(for rawID: String, defaults: UserDefaults = .standard) -> String {
        lock.lock()
        defer { lock.unlock() }
        var entries = load(defaults)
        if let existing = entries.first(where: { $0.raw == rawID }) {
            return existing.identifier
        }
        let created = OpenCodeRequestContext.identifier(prefix: "ses", descending: true)
        entries.append(Entry(raw: rawID, identifier: created))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        save(entries, defaults: defaults)
        return created
    }

    /// Replace a session identifier the upstream refused with a fresh one.
    /// The upstream keeps a rate-limited session id blocked for the rest of
    /// the UTC day, so the chat would stay broken until the id changes.
    func rotate(identifier: String, defaults: UserDefaults = .standard) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var entries = load(defaults)
        guard let index = entries.firstIndex(where: { $0.identifier == identifier }) else {
            return nil
        }
        let created = OpenCodeRequestContext.identifier(prefix: "ses", descending: true)
        entries[index].identifier = created
        save(entries, defaults: defaults)
        return created
    }

    private func load(_ defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: MyCoderDefaults.key(Self.defaultsSuffix)),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    private func save(_ entries: [Entry], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: MyCoderDefaults.key(Self.defaultsSuffix))
    }
}
