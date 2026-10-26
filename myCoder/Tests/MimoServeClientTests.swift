import Testing
import Foundation
@testable import myCoder

@Suite("MimoServeClient")
struct MimoServeClientTests {

    // MARK: - URL Construction

    @Test("Client constructs correct base URL")
    func baseURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        #expect(client.baseURL.absoluteString == "http://127.0.0.1:8080")
    }

    @Test("Client constructs URL with custom host")
    func customHost() {
        let client = MimoServeClient(host: "192.168.1.100", port: 9090)
        #expect(client.baseURL.absoluteString == "http://192.168.1.100:9090")
    }

    @Test("Client default URL")
    func defaultURL() {
        let client = MimoServeClient()
        #expect(client.baseURL.absoluteString == "http://127.0.0.1:0")
    }

    // MARK: - Endpoint URLs

    @Test("Health endpoint URL")
    func healthURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .health)
        #expect(url.path == "/global/health")
    }

    @Test("Sessions endpoint URL")
    func sessionsURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .sessions)
        #expect(url.path == "/experimental/session")
    }

    @Test("Session status endpoint URL")
    func sessionStatusURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .sessionStatus("ses_123"))
        #expect(url.path == "/session/status/ses_123")
    }

    @Test("Project current endpoint URL")
    func projectCurrentURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .projectCurrent)
        #expect(url.path == "/project/current")
    }

    @Test("Config providers endpoint URL")
    func configProvidersURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .configProviders)
        #expect(url.path == "/config/providers")
    }

    @Test("File content endpoint URL")
    func fileContentURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .fileContent("/src/main.swift"))
        #expect(url.path == "/file/content")
        #expect(url.query?.contains("path=") == true)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathParam = components?.queryItems?.first(where: { $0.name == "path" })?.value
        #expect(pathParam == "/src/main.swift")
    }

    @Test("Sync start endpoint URL")
    func syncStartURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .syncStart)
        #expect(url.path == "/sync/start")
    }

    @Test("Paginated messages endpoint requests a bounded recent history")
    func paginatedMessagesURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .sessionMessagesPage("ses_123", limit: 20))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        #expect(url.path == "/session/ses_123/message")
        #expect(components?.queryItems == [URLQueryItem(name: "limit", value: "20")])
    }

    @Test("Question reply endpoint URL")
    func questionReplyURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .questionReply("req_abc"))
        #expect(url.path == "/question/req_abc/reply")
    }
}

@Suite("MimoServeClient Endpoint Enumeration")
struct EndpointTests {

    @Test("All endpoints have valid paths")
    func allEndpoints() {
        let endpoints: [MimoEndpoint] = [
            .health, .projectCurrent, .sessions, .sessionStatus("test"),
            .configProviders, .fileContent("/test"), .fileStatus("/test"),
            .syncStart, .syncReplay, .syncHistory, .vcsDiff(directory: nil, mode: .git)
        ]

        for endpoint in endpoints {
            let client = MimoServeClient()
            let url = client.url(for: endpoint)
            #expect(url.scheme == "http")
            #expect(url.host != nil)
        }
    }
}
