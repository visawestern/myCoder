import Testing
import Foundation
@testable import myCoder

/// Round 30 — live finding: route discovery picked `/api/v2/users/status`
/// (telemetry, relative URL) as a "chat API" and DirectWebAPIClient then failed
/// with `unsupported URL` (-1002). Discovery must (a) ignore obvious non-chat
/// endpoints and (b) only propose ABSOLUTE http(s) endpoints.
@Suite("Round 30 — network route discovery quality")
struct NetworkInterceptorRouteQualityTests {

    private func req(url: String, body: String? = nil,
                     contentType: String = "application/json") -> CapturedRequest {
        CapturedRequest(url: url, method: "POST",
                        headers: ["Content-Type": contentType],
                        body: body, timestamp: Date(),
                        requestID: UUID().uuidString)
    }

    @Test("telemetry/users/status endpoints are never proposed as chat APIs")
    func junkPathsFiltered() {
        let requests = [
            req(url: "https://chat.qwen.ai/api/v2/users/status",
                body: "{\"typarms\":{\"typarm4\":\"qwen_chat\"}}"),
            req(url: "https://x.io/api/telemetry", body: "{\"message\":\"x\"}"),
            req(url: "https://x.io/api/tracking", body: "{\"content\":\"x\"}"),
            req(url: "https://x.io/api/log", body: "{\"prompt\":\"x\"}")
        ]
        #expect(NetworkInterceptor.findChatAPI(requests: requests) == nil)
    }

    @Test("relative URLs are not proposed (URLSession would fail -1002)")
    func relativeURLRejected() {
        let requests = [
            req(url: "/api/v1/chat/completion", body: "{\"message\":\"hi\"}")
        ]
        #expect(NetworkInterceptor.findChatAPI(requests: requests) == nil)
    }

    @Test("absolute chat endpoint still wins")
    func absoluteChatAccepted() {
        let requests = [
            req(url: "https://chat.qwen.ai/api/v2/chat/completions",
                body: "{\"message\":\"hi\",\"content\":\"x\"}")
        ]
        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)
        #expect(endpoint != nil)
        #expect(endpoint?.url.hasPrefix("https://") == true)
    }

    @Test("auth/token/refresh endpoints are never proposed as chat APIs")
    func authEndpointsFiltered() {
        // Audit 2026-09-09 (Kimi live): the account RefreshToken endpoint
        // won scoring via /api/ + Bearer and SmartSend POSTed chat bodies
        // at it (HTTP 520) twice per turn.
        let requests = [
            req(url: "https://auth.kimi.ai/api/account.gateway.v1.AuthService/RefreshToken",
                body: "{\"message\":\"x\",\"content\":\"y\"}")
        ]
        #expect(NetworkInterceptor.findChatAPI(requests: requests) == nil)
    }

    @Test("telemetry endpoints are never proposed even with HTTP-200-shaped bodies")
    func telemetryEndpointsFiltered() {
        // Audit 2026-09-09 (ChatGPT live): chatgpt.com/ces/v1/t (Segment.io)
        // returned HTTP 200 for a chat POST and SmartSend declared success
        // while nothing reached the model.
        let requests = [
            req(url: "https://chatgpt.com/ces/v1/t",
                body: "{\"timestamp\":\"2026-09-09\",\"event\":\"Location\",\"integrations\":{\"Segment.io\":true}}")
        ]
        #expect(NetworkInterceptor.findChatAPI(requests: requests) == nil)
    }

    @Test("endpoint without a substitutable message field is never proposed")
    func messageLessBodiesRejected() {
        // A candidate that cannot carry our text must not win no matter its
        // score: buildDirectRequest would POST the template verbatim.
        let requests = [
            req(url: "https://chat.qwen.ai/api/v2/chat/completions",
                body: "{\"session_id\":\"abc\",\"flags\":[1,2]}")
        ]
        #expect(NetworkInterceptor.findChatAPI(requests: requests) == nil)
    }
}
