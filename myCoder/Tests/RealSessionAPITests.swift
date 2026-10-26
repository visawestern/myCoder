import Testing
import Foundation
@testable import myCoder

@Suite("Real Session API")
struct RealSessionAPITests {

    @Test("Session create response decodes")
    func sessionCreateDecodes() throws {
        let json = """
        {"id":"ses_123","slug":"test","projectID":"global","directory":"/tmp","title":"Hello"}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoSessionCreateResponse.self, from: json)
        #expect(response.id == "ses_123")
        #expect(response.title == "Hello")
    }

    @Test("Message response decodes with text part")
    func messageResponseDecodes() throws {
        let json = """
        {
            "info": {"role": "assistant", "modelID": "mycoder-auto-free"},
            "parts": [
                {"type": "text", "text": "4"}
            ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoMessageResponse.self, from: json)
        #expect(response.textContent == "4")
        #expect(response.info?.role == "assistant")
    }

    @Test("Message response decodes with multiple parts")
    func messageMultipleParts() throws {
        let json = """
        {
            "info": {"role": "assistant"},
            "parts": [
                {"type": "reasoning", "text": "thinking..."},
                {"type": "text", "text": "The answer is 4"}
            ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoMessageResponse.self, from: json)
        #expect(response.textContent == "The answer is 4")
    }

    @Test("Message response decodes real API format")
    func messageRealAPIFormat() throws {
        let json = """
        {"info":{"parentID":"msg_abc","role":"assistant","mode":"build","agent":"build","path":{"cwd":"/tmp","root":"/"},"cost":0,"tokens":{"total":19065,"input":2669,"output":4,"reasoning":8,"cache":{"write":0,"read":16384}},"modelID":"mycoder-auto-free","providerID":"mimo","time":{"created":123,"completed":456},"finish":"stop","id":"msg_def","sessionID":"ses_ghi","agentID":"main"},"parts":[{"type":"step-start","id":"p1","sessionID":"ses_ghi","messageID":"msg_def"},{"type":"reasoning","text":"thinking","time":{"start":1,"end":2},"id":"p2","sessionID":"ses_ghi","messageID":"msg_def"},{"type":"text","text":"4","time":{"start":3,"end":4},"id":"p3","sessionID":"ses_ghi","messageID":"msg_def"},{"reason":"stop","type":"step-finish","tokens":{"total":100,"input":50,"output":4,"reasoning":8,"cache":{"write":0,"read":50}},"cost":0,"id":"p4","sessionID":"ses_ghi","messageID":"msg_def"}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MimoMessageResponse.self, from: json)
        #expect(response.textContent == "4")
    }

    @Test("Endpoint paths for session API")
    func sessionEndpointPaths() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        #expect(client.url(for: .createSession).path == "/session")
        #expect(client.url(for: .sessionMessages("ses_123")).path == "/session/ses_123/message")
        #expect(client.url(for: .sessionPrompt("ses_123")).path == "/session/ses_123/message")
    }
}
