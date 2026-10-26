import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What a real health check does for an installed MCP server (Раздел 4 п.5):
/// - `.http(url:)` — probe the MCP endpoint URL over HTTP(S).
/// - `.stdio(command:args:)` — verify the launch command resolves on PATH.
struct MCPHealthProbe: Equatable {
    enum Kind: Equatable {
        case http(URL)
        case stdio(command: String, args: [String])
    }
    let kind: Kind
}

/// Result of a completed health check, surfaced by the UI dot (not the
/// enabled flag, which is a *preference*, not a liveness signal).
enum MCPHealthStatus: Equatable {
    case unknown
    case healthy
    case unhealthy
}

/// Pure, Foundation-only logic for MCP health: probe classification, PATH
/// resolution for stdio launch commands, and the UI status mapping.
enum MCPHealthCheckLogic {

    /// How long a stored health result stays "fresh" before the UI must
    /// re-probe instead of trusting an old timestamp.
    static let defaultMaxAgeSeconds: TimeInterval = 300

    /// Classify an installed MCP server entry into the probe it needs.
    /// An entry without both a URL and a command cannot be checked at all.
    static func probe(for entry: MCPServerEntry) -> MCPHealthProbe? {
        if let urlString = entry.url, let url = URL(string: urlString) {
            return MCPHealthProbe(kind: .http(url))
        }
        if let command = entry.command, !command.isEmpty {
            return MCPHealthProbe(kind: .stdio(command: command, args: entry.args))
        }
        return nil
    }

    /// Resolve a stdio launch command to an executable path, searching
    /// `searchPath` (the caller passes the app's PATH or a test fixture).
    /// Mirrors `which`: first the literal path if it is executable, then each
    /// PATH component in order. Returns nil when nothing resolves.
    static func resolveStdioCommand(_ command: String,
                                    searchPath: String?,
                                    fileManager: FileManager) -> String? {
        let candidates: [String]
        if command.contains("/") {
            candidates = [command]
        } else {
            let components = (searchPath ?? "").split(separator: ":").map(String.init)
            candidates = components.map { ($0 as NSString).appendingPathComponent(command) }
        }
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  fileManager.isExecutableFile(atPath: candidate) else { continue }
            return candidate
        }
        return nil
    }

    /// Map stored health state + staleness to the UI dot. `isEnabled` is a
    /// user preference, so a disabled server is always shown as unknown/gray
    /// regardless of what a probe once said.
    static func status(isEnabled: Bool,
                       lastCheck: Date?,
                       lastStatus: Bool?,
                       now: Date = Date(),
                       maxAge: TimeInterval = MCPHealthCheckLogic.defaultMaxAgeSeconds) -> MCPHealthStatus {
        guard isEnabled else { return .unknown }
        guard let lastCheck, let lastStatus else { return .unknown }
        guard now.timeIntervalSince(lastCheck) <= maxAge else { return .unknown }
        return lastStatus ? .healthy : .unhealthy
    }
}

/// HTTP transport for MCP health probes. The protocol exists so tests can
/// inject a deterministic prober; production uses `LiveMCPHTTPProber` which
/// performs a real bounded HTTP request.
protocol MCPHTTPProbing: Sendable {
    /// Returns the HTTP status code, or nil when the transport failed.
    func probe(url: URL, timeout: TimeInterval) async -> Int?
}

/// Real HTTP prober: a bounded GET with a short timeout. A 2xx/3xx status
/// means the endpoint is alive; 4xx/5xx or a transport error means it is not
/// healthy (the dot must not claim health for a dead or erroring server).
struct LiveMCPHTTPProber: MCPHTTPProbing {
    func probe(url: URL, timeout: TimeInterval) async -> Int? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        do {
            let (_, response): (Data, URLResponse)
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            (_, response) = try await URLSession.shared.data(for: request)
            #else
            (_, response) = try await withCheckedThrowingContinuation { continuation in
                URLSession.shared.dataTask(with: request) { data, resp, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data, let resp = resp {
                        continuation.resume(returning: (data, resp))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }.resume()
            }
            #endif
            guard let http = response as? HTTPURLResponse else { return nil }
            return http.statusCode
        } catch {
            return nil
        }
    }
}

/// Orchestrates a real health check for one installed MCP server: classify the
/// probe, run it over the real transport (HTTP GET or PATH resolution), and
/// persist the outcome (timestamp + status) into the MCP registry.
struct MCPHealthChecker {
    let httpProber: MCPHTTPProbing
    let searchPath: String?
    let fileManager: FileManager

    init(httpProber: MCPHTTPProbing = LiveMCPHTTPProber(),
         searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
         fileManager: FileManager = .default) {
        self.httpProber = httpProber
        self.searchPath = searchPath
        self.fileManager = fileManager
    }

    /// Probes a URL over the real HTTP transport. Returns true only for a
    /// 2xx/3xx response; a 4xx/5xx status or a transport failure means the
    /// server is not healthy (false) — a reachable-but-erroring server must
    /// never show a green dot.
    func probeHTTP(url: URL, timeout: TimeInterval = 5) async -> Bool {
        guard let status = await httpProber.probe(url: url, timeout: timeout) else { return false }
        return (200..<400).contains(status)
    }

    /// Runs the health check for `entry` and persists the result into the MCP
    /// registry. Returns the fresh status; nil when the server cannot be
    /// probed (no url/command) — in that case nothing is persisted.
    @discardableResult
    func check(_ entry: MCPServerEntry, homeDirectory: URL, now: Date = Date()) async throws -> Bool? {
        guard let probe = MCPHealthCheckLogic.probe(for: entry) else { return nil }
        let healthy: Bool
        switch probe.kind {
        case .http(let url):
            healthy = await probeHTTP(url: url)
        case .stdio(let command, _):
            healthy = MCPHealthCheckLogic.resolveStdioCommand(command, searchPath: searchPath, fileManager: fileManager) != nil
        }
        // Persist the outcome so the Settings UI dot reflects real liveness.
        if (try? MCPRegistryManager.updateHealthCheck(id: entry.id, at: now, homeDirectory: homeDirectory)) ?? false {
            _ = try? MCPRegistryManager.updateHealthStatus(id: entry.id, status: healthy, homeDirectory: homeDirectory)
        }
        return healthy
    }
}
