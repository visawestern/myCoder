import Testing
import Foundation
@testable import myCoder

// ═══════════════════════════════════════════════════════════════════════════
// Devil's-advocate Round 8 — RED regression tests for the "sending a message
// does nothing, no error, no thinking" bug cluster.
//
// Every test here pins down a specific failure mode in the send chain that
// turns "send" into a silent no-op:
//   P1  send button is disabled with ZERO feedback (reason never shown)
//   P3  SendRouteResolver.route(.none) falls through into the serve branch
//   P2  web-turn status/error events are lost (empty assistant bubble)
//   P4  no visible "waiting/thinking" state while a provider answers
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Send chain — no silent no-op (Round 8)")
struct SendChainRegressionTests {
    init() { LocalizationRuntime.currentLanguage = .english }

    // MARK: - P1: the disabled send button must expose WHY it is disabled

    @Test("P1 empty text yields an actionable reason")
    func p1EmptyTextReason() {
        let reason = SendReadinessReason.reason(
            text: "   ",
            images: [],
            files: [],
            modelID: "m",
            providerID: "p",
            serverConnected: true,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: []
        )
        #expect(reason != nil, "An empty-text send must not be a silent no-op")
        #expect(reason?.contains("message") == true)
    }

    @Test("P1 missing model yields 'select a model' reason")
    func p1MissingModelReason() {
        let reason = SendReadinessReason.reason(
            text: "hello",
            images: [],
            files: [],
            modelID: "",
            providerID: "p",
            serverConnected: true,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: []
        )
        #expect(reason?.contains("model") == true)
    }

    @Test("P1 missing provider yields 'select a provider' reason")
    func p1MissingProviderReason() {
        let reason = SendReadinessReason.reason(
            text: "hello",
            images: [],
            files: [],
            modelID: "m",
            providerID: nil,
            serverConnected: true,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: []
        )
        #expect(reason?.contains("provider") == true)
    }

    @Test("P1 server provider selected while server is disconnected yields readiness error")
    func p1DisconnectedServerProviderReason() {
        // A provider id that is NOT a web/local/custom id while the server is
        // down must not be treated as ready.
        let reason = SendReadinessReason.reason(
            text: "hello",
            images: [],
            files: [],
            modelID: "m",
            providerID: "server-only-provider",
            serverConnected: false,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: []
        )
        #expect(reason != nil, "Server-only provider with server down must be reported, not silently blocked")
        #expect(reason?.contains("No provider") == true)
    }

    @Test("P1 custom provider missing API key yields actionable reason")
    func p1MissingAPIKeyReason() {
        let custom = CustomProvider(id: "c1", name: "Cloud", type: .openAI,
                                    baseURL: "https://api.example.com/v1", apiKey: "",
                                    models: ["m"], requiresAPIKey: true)
        let reason = SendReadinessReason.reason(
            text: "hello",
            images: [],
            files: [],
            modelID: "m",
            providerID: "c1",
            serverConnected: false,
            customProviders: [custom],
            localProviderIDs: [],
            webProviderIDs: []
        )
        #expect(reason?.contains("API key") == true)
    }

    @Test("P1 fully ready configuration yields no reason")
    func p1ReadyYieldsNil() {
        let custom = CustomProvider(id: "c1", name: "Cloud", type: .openAI,
                                    baseURL: "https://api.example.com/v1", apiKey: "k",
                                    models: ["m"], requiresAPIKey: true)
        let reason = SendReadinessReason.reason(
            text: "hello",
            images: [],
            files: [],
            modelID: "m",
            providerID: "c1",
            serverConnected: false,
            customProviders: [custom],
            localProviderIDs: [],
            webProviderIDs: []
        )
        #expect(reason == nil)
    }

    // MARK: - P3: SendRoute .none must be handled explicitly, never fall into serve

    @Test("P3 route is .none when nothing is configured")
    func p3NoneWhenNothingConfigured() {
        let route = SendRouteResolver.route(
            selectedProviderID: "", selectedModel: "", serverConnected: false, isACP: false,
            customProviders: [], localProviders: [], webProviderIDs: []
        )
        #expect(route == .none)
    }

    @Test("P3 guard reports a user-facing error for .none, and only for .none")
    func p3GuardMessages() {
        #expect(SendRouteGuard.errorMessage(for: .none, serverConnected: false) != nil)
        #expect(SendRouteGuard.errorMessage(for: .none, serverConnected: true) != nil)
        #expect(SendRouteGuard.errorMessage(for: .mimoServe, serverConnected: false) == nil)
        #expect(SendRouteGuard.errorMessage(for: .acp, serverConnected: false) == nil)
        #expect(SendRouteGuard.errorMessage(for: .web(configID: "x"), serverConnected: false) == nil)
        #expect(SendRouteGuard.errorMessage(for: .openAICompatible(baseURL: "u", apiKey: nil, model: "m"), serverConnected: false) == nil)
    }

    @Test("P3 guard message mentions provider setup")
    func p3GuardMessageIsActionable() {
        let msg = SendRouteGuard.errorMessage(for: .none, serverConnected: false)
        #expect(msg?.contains("provider") == true)
    }

    // MARK: - P2: web-turn events must persist into the assistant message

    @Test("P2 final answer replaces content and finishes")
    func p2FinalAnswerMutation() {
        let m = WebChatTurnMutation.mutation(for: .answer("done"))
        guard case .replaceText(let text, let finished, let streaming) = m else {
            Issue.record("expected replaceText, got \(m)"); return
        }
        #expect(text == "done")
        #expect(finished)
        #expect(!streaming)
    }

    @Test("P2 error replaces content with visible error and finishes")
    func p2ErrorMutation() {
        let m = WebChatTurnMutation.mutation(for: .error("boom"))
        guard case .replaceText(let text, let finished, _) = m else {
            Issue.record("expected replaceText, got \(m)"); return
        }
        #expect(text.contains("boom"))
        #expect(finished)
    }

    @Test("P2 logout/iteration-limit status is NOT lost — it appends to the message")
    func p2StatusPersistsIntoMessage() {
        for presentation in [
            WebChatEventPresenter.Presentation.status("Session expired — log in again to continue."),
            WebChatEventPresenter.Presentation.status("Reached the tool-iteration limit for this turn."),
        ] {
            let m = WebChatTurnMutation.mutation(for: presentation)
            guard case .appendStatus(let line) = m else {
                Issue.record("status must append into the message, got \(m)"); return
            }
            #expect(!line.isEmpty)
        }
    }

    @Test("P2 captcha appends into the message and does NOT finish the turn")
    func p2CaptchaAppends() {
        let m = WebChatTurnMutation.mutation(
            for: .captcha(pngBase64: "AAAA", note: "Solve the captcha below")
        )
        guard case .appendStatus(let line) = m else {
            Issue.record("captcha must be visible in the message, got \(m)"); return
        }
        #expect(line.contains("captcha") || line.contains("AAAA"))
    }

    @Test("P2 suppressed streaming produces no mutation")
    func p2StreamingSuppressed() {
        #expect(WebChatTurnMutation.mutation(for: .none) == .none)
    }

    // MARK: - P4: visible waiting/thinking state while a provider answers

    @Test("P4 waiting text names the selected model")
    func p4WaitingText() {
        let t = SendStatusText.waitingForResponse(modelID: "gpt-4o", providerName: "OpenAI")
        #expect(t.contains("gpt-4o"))
        #expect(!t.isEmpty)
    }

    @Test("P4 empty streaming bubble gets a thinking placeholder")
    func p4ThinkingPlaceholder() {
        let t = SendStatusText.thinkingPlaceholder(modelID: "llama3")
        #expect(t.contains("Thinking"))
        #expect(t.contains("llama3"))
    }

    // MARK: - Round 2 edge cases (devil's-advocate re-analysis)

    @Test("R2 an empty web-model answer is surfaced, not shown as an empty bubble")
    func r2EmptyAnswerIsVisible() {
        let m = WebChatTurnMutation.mutation(for: .answer("   "))
        guard case .replaceText(let text, let finished, _) = m else {
            Issue.record("expected replaceText, got \(m)"); return
        }
        #expect(text.contains("empty response"), "An empty model answer must be reported, got \(text)")
        #expect(finished)
    }

    @Test("R2 waiting text handles a missing model id without awkward double spaces")
    func r2WaitingWithoutModelID() {
        let t = SendStatusText.waitingForResponse(modelID: "", providerName: nil)
        #expect(t.contains("Waiting"))
        #expect(!t.contains("  "), "No double space when the model id is empty: \(t)")
    }

    @Test("R2 a web route whose config was deleted must not silently fall into serve")
    func r2MissingWebConfigIsReported() {
        #expect(SendRouteGuard.webConfigMissingMessage(configID: "gone") != nil)
        let msg = SendRouteGuard.webConfigMissingMessage(configID: "gone")
        #expect(msg?.contains("web provider") == true)
    }
}
