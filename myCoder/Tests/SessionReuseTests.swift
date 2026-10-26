import Testing
import Foundation
@testable import myCoder

@Suite("Session Send Logic")
struct SessionReuseTests {
    
    @Test("Uses selected session ID when present")
    func usesSelectedSession() {
        #expect(SessionSendLogic.shouldCreateNewSession(selectedSessionID: "ses_abc") == false)
        #expect(SessionSendLogic.resolvedSessionID(selectedSessionID: "ses_abc", newlyCreatedID: "ses_new") == "ses_abc")
    }
    
    @Test("Creates new session when none selected")
    func createsWhenNoneSelected() {
        #expect(SessionSendLogic.shouldCreateNewSession(selectedSessionID: nil) == true)
        #expect(SessionSendLogic.shouldCreateNewSession(selectedSessionID: "") == true)
        #expect(SessionSendLogic.resolvedSessionID(selectedSessionID: nil, newlyCreatedID: "ses_new") == "ses_new")
    }
    
    @Test("Follow-up does not switch to new session ID")
    func followUpKeepsSession() {
        let first = SessionSendLogic.resolvedSessionID(selectedSessionID: nil, newlyCreatedID: "ses_1")
        #expect(first == "ses_1")
        let followUp = SessionSendLogic.resolvedSessionID(selectedSessionID: "ses_1", newlyCreatedID: "ses_2")
        #expect(followUp == "ses_1")
    }
    
    @Test("Agent mode maps to API send mode")
    func agentModeMapping() {
        #expect(SessionSendLogic.sendMode(for: .build) == "build")
        #expect(SessionSendLogic.sendMode(for: .plan) == "plan")
        #expect(SessionSendLogic.sendMode(for: .compose) == "compose")
    }
    
    @Test("Reconciles server message ID")
    func reconcileMessageID() {
        #expect(SessionSendLogic.reconcileAssistantMessageID(localID: "local", serverID: "server") == "server")
        #expect(SessionSendLogic.reconcileAssistantMessageID(localID: nil, serverID: "server") == "server")
    }

    @Test("Keeps the local assistant placeholder as the live update key")
    func assistantUpdateIDKeepsLocalPlaceholder() {
        #expect(SessionSendLogic.assistantUpdateID(localID: "local", serverID: "server") == "local")
        #expect(SessionSendLogic.assistantUpdateID(localID: "", serverID: "server") == "server")
        #expect(SessionSendLogic.assistantUpdateID(localID: nil, serverID: "server") == "server")
    }

    @Test("Selects assistant response instead of echoed user message")
    func selectsAssistantResponse() throws {
        let data = """
        [
          {
            "info": {"id": "user-1", "role": "user"},
            "parts": [{"type": "text", "text": "hello"}]
          },
          {
            "info": {"id": "assistant-1", "role": "assistant"},
            "parts": [{"type": "text", "text": "reply"}]
          }
        ]
        """.data(using: .utf8)!
        let messages = try JSONDecoder().decode([MimoMessageResponse].self, from: data)

        let response = SessionSendLogic.assistantResponse(from: messages)

        #expect(response?.info?.id == "assistant-1")
        #expect(response?.textContent == "reply")
    }

    @Test("Accepted empty POST response keeps waiting for SSE")
    func emptyPostResponseAwaitsSSE() {
        #expect(
            SessionSendLogic.shouldAwaitSSE(
                responseMessages: [],
                hasPendingQuestion: false
            )
        )
    }
    
    @Test("Worked duration label formats seconds")
    func workedDuration() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 11)
        #expect(SessionSendLogic.workedDurationLabel(since: start, until: end) == "Worked for 11s")
    }
}

@Suite("ChatSession Duration")
struct ChatSessionDurationTests {
    
    @Test("Duration label formats minutes")
    func minutes() {
        let date = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 9 * 60)
        #expect(ChatSession.durationLabel(since: date, now: now) == "9m")
    }
    
    @Test("Duration label formats hours")
    func hours() {
        let date = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 2 * 3600)
        #expect(ChatSession.durationLabel(since: date, now: now) == "2h")
    }
    
    @Test("Duration label formats days")
    func days() {
        let date = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 3 * 86400)
        #expect(ChatSession.durationLabel(since: date, now: now) == "3d")
    }
    
    @Test("Sessions filter by workspace directory")
    func workspaceFilter() {
        let ws = Workspace(id: "1", name: "tm3", path: "/Users/test/tm3")
        let match = ChatSession(id: "a", title: "A", directory: "/Users/test/tm3")
        let other = ChatSession(id: "b", title: "B", directory: "/Users/test/other")
        #expect(match.belongs(to: ws))
        #expect(!other.belongs(to: ws))
    }
}
