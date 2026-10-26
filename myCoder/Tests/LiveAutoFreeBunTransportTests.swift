import Testing
import Foundation
@testable import myCoder

/// Live verification (MYCODER_LIVE_TESTS=1): the same request that returns
/// 429 FreeUsageLimitError through Swift URLSession must succeed when the
/// HTTPS leg is delegated to the local bun runtime (BoringSSL stack, the only
/// stack upstream serves the anonymous free tier to).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MYCODER_LIVE_TESTS"] == "1"))
struct LiveAutoFreeBunTransportTests {

    @Test("Direct Zen chat completion via bun transport returns model content")
    func bunTransportCompletes() async throws {
        guard let bunPath = MyCoderAutoFreeClient.bunExecutablePath() else {
            Issue.record("bun is not installed; transport cannot be verified live")
            return
        }
        let context = OpenCodeRequestContext.generated()
        var emitted = ""
        let stream = MyCoderAutoFreeClient.shared.chatCompletion(
            model: "big-pickle",
            messages: [MyCoderAutoFreeClient.Message(role: "user", content: "Reply with exactly OK.")],
            parameters: ModelCallParameters(),
            context: context,
            tools: MyCoderAutoFreeClient.gateToolDefinitions(),
            toolChoice: "none",
            projectRoot: "/Users/apple/projects",
            isGitRepo: true
        )
        for try await event in stream {
            switch event {
            case .content(let text):
                emitted += text
            case .reasoning, .toolCall:
                break
            }
        }
        #expect(emitted.uppercased().contains("OK"))
        _ = bunPath
    }
}
