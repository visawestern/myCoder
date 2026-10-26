import Testing
import Foundation
@testable import myCoder

@Suite(
    "OpenCode Auto Free Live Model",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["MYCODER_LIVE_TESTS"] == "1")
)
struct LiveAutoFreeModelTests {

    @Test("Direct Zen request carries the official contract and reaches the free model")
    func directZenRequestVerdict() async throws {
        let context = OpenCodeRequestContext(
            sessionID: OpenCodeRequestContext.sessionID(from: "live-probe-session"),
            projectID: OpenCodeRequestContext.projectID(fromPath: RepoRoot.url.path),
            requestID: OpenCodeRequestContext.requestID()
        )
        #expect(context.headers["x-opencode-session-id"]?.hasPrefix("ses_") == true)
        #expect(context.headers["x-opencode-request"]?.hasPrefix("msg_") == true)
        #expect(context.headers["User-Agent"] == OpenCodeRequestContext.userAgent)

        let client = MyCoderAutoFreeClient(session: .shared)
        do {
            var text = ""
            for try await event in client.chatCompletion(
                model: MyCoderAutoFreeClient.defaultModelID,
                messages: [.init(role: "user", content: "Reply with the single word OK")],
                context: context
            ) {
                if case .content(let chunk) = event {
                    text += chunk
                }
            }
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            print("[auto-free-live] PASS direct Zen — \(text.prefix(120))")
        } catch let error as MyCoderAutoFreeError {
            switch error {
            case .rateLimited:
                print("[auto-free-live] QUOTA direct Zen — \(error.localizedDescription)")
            case .freeTierBlocked:
                Issue.record("The upstream free tier rejected the request: \(error.localizedDescription)")
            default:
                Issue.record("unexpected upstream error: \(error.localizedDescription)")
            }
        }
    }

    @Test("Agent request with the native tool set reaches the free model")
    func agentRequestWithNativeTools() async throws {
        let context = OpenCodeRequestContext(
            sessionID: OpenCodeRequestContext.sessionID(from: "live-agent-session"),
            projectID: OpenCodeRequestContext.projectID(fromPath: RepoRoot.url.path),
            requestID: OpenCodeRequestContext.requestID()
        )
        let client = MyCoderAutoFreeClient(session: .shared)
        do {
            var text = ""
            var toolCallCount = 0
            for try await event in client.chatCompletion(
                model: MyCoderAutoFreeClient.defaultModelID,
                messages: [.init(role: "user", content: "List the files in the project root using your tools.")],
                context: context,
                tools: MyCoderAutoFreeClient.agentToolDefinitions(),
                toolChoice: "auto"
            ) {
                if case .content(let chunk) = event { text += chunk }
                if case .toolCall = event { toolCallCount += 1 }
            }
            print("[auto-free-live] PASS agent request — content=\(text.prefix(80)) toolCalls=\(toolCallCount)")
        } catch let error as MyCoderAutoFreeError {
            switch error {
            case .rateLimited:
                print("[auto-free-live] QUOTA agent request — \(error.localizedDescription)")
            case .freeTierBlocked:
                Issue.record("The upstream free tier rejected the agent request: \(error.localizedDescription)")
            default:
                Issue.record("unexpected upstream error: \(error.localizedDescription)")
            }
        }
    }

    @Test("big-pickle answers through a local opencode serve")
    func bigPickleThroughLocalOpenCode() async throws {
        let password = ProcessInfo.processInfo.environment["MYCODER_OPENCODE_PASSWORD"] ?? "mycoder-live"
        let authHeader = try #require(LocalProviderConfig.basicAuthHeader(username: "opencode", password: password))
        let headers = ["Authorization": authHeader]
        let baseURL = ProcessInfo.processInfo.environment["MYCODER_OPENCODE_URL"] ?? "http://127.0.0.1:4096"

        let result = try await OpenCodeServeClient.send(
            baseURL: baseURL,
            headers: headers,
            modelID: MyCoderAutoFreeClient.defaultModelID,
            text: "Reply with the single word OK",
            providerID: "opencode"
        )
        print("[auto-free-live] PASS local opencode serve — \(result.content.prefix(120))")
        #expect(!result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
