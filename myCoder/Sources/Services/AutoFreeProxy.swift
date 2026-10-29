import Foundation
import Combine

/// Proxy protocol accepted by the OpenCode Zen free tier rotation.
///
/// `http` is the ordinary CONNECT proxy used for both http and https
/// destinations, `https` is the same proxy but only for https destinations,
/// and `socks5` is a SOCKS5 exit. Authentication is deliberately unsupported:
/// `URLSessionConfiguration.connectionProxyDictionary` cannot carry proxy
/// credentials, so accepting `user:pass@host` would silently connect without
/// the credentials instead of authenticating.
enum AutoFreeProxyScheme: String, CaseIterable {
    case http
    case https
    case socks5

    var displayName: String {
        switch self {
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .socks5: return "SOCKS5"
        }
    }
}

/// One exit point for a rate-limited Zen request.
///
/// Zen throttles the anonymous free tier per client/IP for the rest of the
/// UTC day. When a turn comes back 429, myCoder retries it through the next
/// enabled proxy instead of waiting for the bucket to reset.
struct AutoFreeProxy: Identifiable, Codable, Equatable, Hashable {
    var scheme: String
    var host: String
    var port: Int
    var isEnabled: Bool = true

    /// Canonical identity — one entry per `scheme://host:port`.
    var id: String { urlString }

    var urlString: String { "\(scheme)://\(host):\(port)" }

    var displayScheme: String {
        AutoFreeProxyScheme(rawValue: scheme)?.displayName ?? scheme.uppercased()
    }

    /// Keys of `URLSessionConfiguration.connectionProxyDictionary`. Apple
    /// documents these string keys explicitly; using them avoids importing
    /// CFNetwork just for the `kCFNetworkProxies…` constants.
    var connectionProxySettings: [String: Any] {
        switch AutoFreeProxyScheme(rawValue: scheme) {
        case .socks5:
            return [
                "SOCKSEnable": 1,
                "SOCKSProxy": host,
                "SOCKSPort": port
            ]
        case .https:
            return [
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        case .http, .none:
            return [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        }
    }
}

enum AutoFreeProxyValidationError: LocalizedError, Equatable {
    case empty
    case malformedURL
    case unsupportedScheme(String)
    case missingHost
    case invalidPort
    case credentialsUnsupported
    case duplicate

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a proxy address, for example socks5://127.0.0.1:1080."
        case .malformedURL:
            return "This is not a valid proxy address."
        case .unsupportedScheme(let scheme):
            let allowed = AutoFreeProxyScheme.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unsupported proxy scheme “\(scheme)”. Use \(allowed)."
        case .missingHost:
            return "The proxy address has no host."
        case .invalidPort:
            return "The proxy address needs a port between 1 and 65535."
        case .credentialsUnsupported:
            return "Authenticated proxies are not supported. Use an IP allow-list or an unauthenticated local proxy."
        case .duplicate:
            return "This proxy is already in the list."
        }
    }
}

extension AutoFreeProxy {
    /// Parse `http://host:port`, `https://host:port`, `socks5://host:port`, or
    /// the bare `host:port` shorthand (treated as HTTP).
    static func parse(_ raw: String) throws -> AutoFreeProxy {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AutoFreeProxyValidationError.empty }
        let normalized = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let components = URLComponents(string: normalized) else {
            throw AutoFreeProxyValidationError.malformedURL
        }
        guard let rawScheme = components.scheme?.lowercased(), !rawScheme.isEmpty else {
            throw AutoFreeProxyValidationError.malformedURL
        }
        guard let scheme = AutoFreeProxyScheme(rawValue: rawScheme) else {
            throw AutoFreeProxyValidationError.unsupportedScheme(rawScheme)
        }
        guard let host = components.host, !host.isEmpty else {
            throw AutoFreeProxyValidationError.missingHost
        }
        guard let port = components.port, (1...65535).contains(port) else {
            throw AutoFreeProxyValidationError.invalidPort
        }
        guard components.user == nil, components.password == nil else {
            throw AutoFreeProxyValidationError.credentialsUnsupported
        }
        guard components.path.isEmpty || components.path == "/" else {
            throw AutoFreeProxyValidationError.malformedURL
        }
        return AutoFreeProxy(scheme: scheme.rawValue, host: host.lowercased(), port: port)
    }
}

/// Pure rotation arithmetic, unit-tested without I/O.
enum AutoFreeProxyRotation {
    /// Enabled proxies in the order they must be tried, starting at `cursor`
    /// and wrapping around once.
    static func order(_ proxies: [AutoFreeProxy], cursor: Int) -> [AutoFreeProxy] {
        guard !proxies.isEmpty else { return [] }
        let start = ((cursor % proxies.count) + proxies.count) % proxies.count
        return Array(proxies[start...]) + Array(proxies[..<start])
    }

    /// Cursor after `attempted` proxies of a `count`-sized list were tried, so
    /// the next rate limit starts with a different exit point.
    static func advancedCursor(_ cursor: Int, attempted: Int, count: Int) -> Int {
        guard count > 0, attempted > 0 else { return max(cursor, 0) }
        return (((cursor + attempted) % count) + count) % count
    }
}

/// Persisted proxy list for OpenCode Zen. The list and the rotation cursor live
/// in UserDefaults so a restart keeps the same order and exit point.
///
/// The store is read by the streaming client on a background task while the
/// settings UI mutates it on the main thread, so the list itself is guarded by
/// a lock and changes are announced through `objectWillChange`.
final class AutoFreeProxyStore: ObservableObject {
    static let shared = AutoFreeProxyStore()

    private static let listSuffix = "autoFree.proxies"
    private static let cursorSuffix = "autoFree.proxyCursor"

    let objectWillChange = ObservableObjectPublisher()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var storedProxies: [AutoFreeProxy]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storedProxies = Self.load(defaults)
    }

    /// Snapshot of every configured proxy (enabled and disabled).
    var proxies: [AutoFreeProxy] {
        lock.lock()
        defer { lock.unlock() }
        return storedProxies
    }

    var enabledProxies: [AutoFreeProxy] {
        proxies.filter(\.isEnabled)
    }

    var isEmpty: Bool { proxies.isEmpty }

    @discardableResult
    func add(_ raw: String) throws -> AutoFreeProxy {
        var proxy = try AutoFreeProxy.parse(raw)
        proxy.isEnabled = true

        lock.lock()
        guard !storedProxies.contains(where: { $0.id == proxy.id }) else {
            lock.unlock()
            throw AutoFreeProxyValidationError.duplicate
        }
        storedProxies.append(proxy)
        let snapshot = storedProxies
        lock.unlock()

        persist(snapshot)
        objectWillChange.send()
        return proxy
    }

    func remove(id: String) {
        update { $0.removeAll { $0.id == id } }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        update { entries in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].isEnabled = enabled
        }
    }

    /// Enabled proxies starting at the persisted rotation cursor.
    func rotationOrder() -> [AutoFreeProxy] {
        AutoFreeProxyRotation.order(enabledProxies, cursor: rotationCursor)
    }

    /// Advance the persisted cursor after `attempted` proxied requests so the
    /// next rate limit does not hammer the same exit point first.
    func advanceRotation(attempted: Int) {
        let count = enabledProxies.count
        guard count > 0, attempted > 0 else { return }
        let next = AutoFreeProxyRotation.advancedCursor(
            rotationCursor,
            attempted: attempted,
            count: count
        )
        defaults.set(next, forKey: MyCoderDefaults.key(Self.cursorSuffix))
    }

    private var rotationCursor: Int {
        max(defaults.integer(forKey: MyCoderDefaults.key(Self.cursorSuffix)), 0)
    }

    private func update(_ transform: (inout [AutoFreeProxy]) -> Void) {
        lock.lock()
        var entries = storedProxies
        transform(&entries)
        let changed = entries != storedProxies
        if changed {
            storedProxies = entries
        }
        lock.unlock()

        guard changed else { return }
        persist(entries)
        objectWillChange.send()
    }

    private func persist(_ entries: [AutoFreeProxy]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: MyCoderDefaults.key(Self.listSuffix))
    }

    private static func load(_ defaults: UserDefaults) -> [AutoFreeProxy] {
        guard let data = defaults.data(forKey: MyCoderDefaults.key(listSuffix)),
              let entries = try? JSONDecoder().decode([AutoFreeProxy].self, from: data) else {
            return []
        }
        return entries
    }
}
