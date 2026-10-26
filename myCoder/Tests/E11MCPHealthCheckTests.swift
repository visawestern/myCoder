import Testing
import Foundation
@testable import myCoder

@Suite("E11 — real MCP health check (Раздел 4 п.5): probe classification, stdio resolution, HTTP probe, registry persistence, status mapping")
struct E11MCPHealthCheckTests {

    // MARK: - Probe classification

    @Test("HTTP server entry (url) yields an http probe")
    func httpEntryYieldsHTTPProbe() {
        let entry = MCPServerEntry(id: "figma", name: "Figma", command: "https://api.figma.com/mcp",
                                   isEnabled: true, url: "https://api.figma.com/mcp", args: [])
        let probe = MCPHealthCheckLogic.probe(for: entry)
        guard case .http(let url)? = probe?.kind else {
            Issue.record("expected .http probe, got \(String(describing: probe))")
            return
        }
        #expect(url.absoluteString == "https://api.figma.com/mcp")
    }

    @Test("stdio server entry (command) yields a stdio probe")
    func stdioEntryYieldsStdioProbe() {
        let entry = MCPServerEntry(id: "filesystem", name: "Filesystem", command: "npx",
                                   isEnabled: true, url: nil, args: ["-y", "@modelcontextprotocol/server-filesystem"])
        let probe = MCPHealthCheckLogic.probe(for: entry)
        guard case .stdio(let command, let args)? = probe?.kind else {
            Issue.record("expected .stdio probe, got \(String(describing: probe))")
            return
        }
        #expect(command == "npx")
        #expect(args == ["-y", "@modelcontextprotocol/server-filesystem"])
    }

    @Test("entry without command or url yields no probe")
    func entryWithoutCommandOrURLHasNoProbe() {
        let entry = MCPServerEntry(id: "ghost", name: "Ghost", command: nil, isEnabled: true)
        #expect(MCPHealthCheckLogic.probe(for: entry) == nil)
    }

    // MARK: - stdio command resolution (real PATH lookup, like `which`)

    @Test("stdio probe resolves the binary when it is on PATH")
    func stdioResolvesBinaryOnPath() throws {
        let bin = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-e11-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bin) }
        let tool = bin.appendingPathComponent("mcp-dummy")
        try "#!/bin/sh\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let resolved = MCPHealthCheckLogic.resolveStdioCommand("mcp-dummy", searchPath: bin.path, fileManager: .default)
        #expect(resolved == tool.path)
    }

    @Test("stdio probe returns nil when the binary is not on PATH")
    func stdioMissingBinaryReturnsNil() {
        let resolved = MCPHealthCheckLogic.resolveStdioCommand("definitely-not-a-real-binary-xyz",
                                                               searchPath: "/usr/bin", fileManager: .default)
        #expect(resolved == nil)
    }

    // MARK: - HTTP probe via injected transport (real URLSession in production)

    @Test("http probe healthy on 2xx response")
    func httpProbeHealthyOn2xx() async {
        let checker = MCPHealthChecker(httpProber: FakeHTTPProber(statusCode: 200))
        let healthy = await checker.probeHTTP(url: URL(string: "https://example.com/mcp")!)
        #expect(healthy == true)
    }

    @Test("http probe unhealthy on 5xx response")
    func httpProbeUnhealthyOn5xx() async {
        let checker = MCPHealthChecker(httpProber: FakeHTTPProber(statusCode: 503))
        let healthy = await checker.probeHTTP(url: URL(string: "https://example.com/mcp")!)
        #expect(healthy == false)
    }

    @Test("http probe unhealthy on transport failure")
    func httpProbeUnhealthyOnTransportFailure() async {
        let checker = MCPHealthChecker(httpProber: FakeHTTPProber(error: URLError(.cannotConnectToHost)))
        let healthy = await checker.probeHTTP(url: URL(string: "https://example.com/mcp")!)
        #expect(healthy == false)
    }

    // MARK: - End-to-end checker persists registry result

    @Test("check writes lastHealthCheck + lastHealthStatus into the registry")
    func checkPersistsRegistryResult() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-e11-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let record = InstalledMCPRecord(id: "figma", version: "1.0.0", installedAt: Date(),
                                        source: .mimo, isEnabled: true, transport: .http,
                                        lastHealthCheck: nil, lastHealthStatus: nil)
        try MCPRegistryManager.upsert(record, homeDirectory: home)

        let checker = MCPHealthChecker(httpProber: FakeHTTPProber(statusCode: 200))
        let entry = MCPServerEntry(id: "figma", name: "Figma", command: "https://api.figma.com/mcp",
                                   isEnabled: true, url: "https://api.figma.com/mcp", args: [])
        let result = try await checker.check(entry, homeDirectory: home)

        #expect(result == true)
        let loaded = MCPRegistryManager.load(homeDirectory: home)
        #expect(loaded.first?.lastHealthCheck != nil)
        #expect(loaded.first?.lastHealthStatus == true)
    }

    // MARK: - UI status mapping

    @Test("disabled server shows unknown (gray) regardless of stored health")
    func disabledServerIsUnknown() {
        let status = MCPHealthCheckLogic.status(isEnabled: false, lastCheck: Date(), lastStatus: true)
        #expect(status == .unknown)
    }

    @Test("enabled server with healthy recent check shows healthy")
    func healthyRecentCheckIsHealthy() {
        let status = MCPHealthCheckLogic.status(isEnabled: true, lastCheck: Date(), lastStatus: true)
        #expect(status == .healthy)
    }

    @Test("enabled server with unhealthy recent check shows unhealthy")
    func unhealthyRecentCheckIsUnhealthy() {
        let status = MCPHealthCheckLogic.status(isEnabled: true, lastCheck: Date(), lastStatus: false)
        #expect(status == .unhealthy)
    }

    @Test("enabled server with stale check falls back to unknown (needs re-probe)")
    func staleCheckIsUnknown() {
        let stale = Date(timeIntervalSinceNow: -3600)
        let status = MCPHealthCheckLogic.status(isEnabled: true, lastCheck: stale, lastStatus: true, maxAge: 300)
        #expect(status == .unknown)
    }

    @Test("enabled server that never had a check shows unknown")
    func neverCheckedIsUnknown() {
        let status = MCPHealthCheckLogic.status(isEnabled: true, lastCheck: nil, lastStatus: nil)
        #expect(status == .unknown)
    }
}

// MARK: - Test double for the HTTP transport (real URLSession lives in production)

private final class FakeHTTPProber: MCPHTTPProbing, @unchecked Sendable {
    let statusCode: Int?
    let error: Error?

    init(statusCode: Int? = nil, error: Error? = nil) {
        self.statusCode = statusCode
        self.error = error
    }

    func probe(url: URL, timeout: TimeInterval) async -> Int? {
        if error != nil { return nil }
        return statusCode
    }
}
