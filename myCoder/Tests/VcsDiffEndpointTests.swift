import Testing
import Foundation
@testable import myCoder

@Suite("VCS diff endpoint URL")
struct VcsDiffEndpointTests {

    @Test("Includes required mode=git query parameter")
    func includesModeGit() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .vcsDiff(directory: nil, mode: .git))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(where: { $0.name == "mode" && $0.value == "git" }))
    }

    @Test("Includes directory when provided")
    func includesDirectory() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .vcsDiff(directory: "/Users/test/repo", mode: .git))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(where: { $0.name == "directory" && $0.value == "/Users/test/repo" }))
    }
}
