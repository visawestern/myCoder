import Testing
import Foundation
@testable import myCoder

/// Contract tests for the paste-verify input protocol (audit 2026-09-08):
/// the bridge must tolerate an async composer render (Kimi ~300 ms) without
/// running the execCommand fallback too early (duplication) or failing the
/// whole insert (false elementNotFound).
@Suite("WebComposerInputPolicy (paste-verify window)")
struct WebComposerInputPolicyTests {

    @Test func verifyWindowCoversObservedAsyncRender() {
        // 6 attempts × 200 ms = 1.2 s ≥ the ~300 ms worst case seen on Kimi.
        #expect(WebComposerInputPolicy.verifyAttempts * WebComposerInputPolicy.verifyDelayMs >= 1200)
    }

    @Test func attemptsAreBounded() {
        // The window must stay small so a genuinely failed paste surfaces
        // quickly instead of stalling every send.
        #expect(WebComposerInputPolicy.verifyAttempts <= 10)
        #expect(WebComposerInputPolicy.verifyDelayMs >= 100)
    }
}

/// Byte-budget regression for the tool preamble (audit 2026-09-08): Kimi
/// converts pastes over ~4000 bytes into .txt attachments, so every chunk
/// must stay under the budget even for Cyrillic prompts (2 bytes/char).
@Suite("Preamble byte-budget (Kimi .txt-attachment regression)")
struct PreambleSizeAuditTests {

    private func makePreamble() -> String {
        WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: "Кириллическая система промпт для проверки байтового бюджета",
            projectRoot: RepoRoot.url.path,
            directory: RepoRoot.url.path,
            isGitRepo: true
        )
    }

    @Test func preambleChunksStayUnderByteBudget() {
        // Audit 2026-09-09 (Qwen live): the preamble (~1800 bytes) + a short
        // first question MUST travel as ONE message under the raised budget —
        // splitting it shipped the tool contract in a continuation part that
        // vendors lost in transit ("I have no list_dir tool"). A large prompt
        // (>> budget) still chunks, and every chunk stays within the budget.
        let message = makePreamble() + "\n\n---\n\n" + "Reply with exactly: TEST"
        let parts = WebPromptChunker.chunkedMessages(message)
        #expect(parts.count == 1, "a normal first turn must stay one message")
        let bigPrompt = makePreamble() + "\n\n---\n\n" + String(repeating: "проверка бюджетных границ. ", count: 400)
        let bigParts = WebPromptChunker.chunkedMessages(bigPrompt)
        #expect(bigParts.count > 1, "an oversized prompt must still chunk")
        for part in bigParts {
            let bytes = part.data(using: .utf8)?.count ?? 0
            #expect(bytes <= WebPromptChunker.defaultBudget,
                   "chunk of \(bytes) bytes exceeds the \(WebPromptChunker.defaultBudget)-byte paste budget")
        }
    }

    @Test func byteBudgetCountsCyrillicAsTwoBytes() {
        // 1500 Cyrillic chars = 3000 UTF-8 bytes — must be split at the byte
        // budget, not the character count.
        let cyrillic = String(repeating: "ж", count: 1500)
        let parts = WebPromptChunker.split(cyrillic)
        for part in parts {
            #expect((part.data(using: .utf8)?.count ?? 0) <= WebPromptChunker.defaultBudget)
        }
    }

    @Test func shortPromptStaysSingleChunk() {
        let parts = WebPromptChunker.split("just one short line")
        #expect(parts.count == 1)
    }
}

/// Audit 2026-09-08: Kimi's model menu navigates to /agent* (Kimi Agent, a
/// different product surface whose composer breaks the send flow). Turns must
/// run on the chat surface only.
@Suite("WebChatSurfaceLogic (chat vs agent surface)")
struct WebChatSurfaceLogicTests {

    @Test func kimiChatHomeIsChatSurface() {
        #expect(WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func kimiChatWithQueryIsChatSurface() {
        #expect(WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/?chat_enter_method=new_chat",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func kimiConversationIsChatSurface() {
        #expect(WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/chat/1a07fb7f-67f2-87c5-8000-09e874e746d5?chat_enter_method=new_chat",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func kimiAgentPageIsNotChatSurface() {
        #expect(!WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/agent?chat_enter_method=change_model",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func kimiAgentSwarmIsNotChatSurface() {
        #expect(!WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/agent-swarm?chat_enter_method=change_model",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func otherHostIsNotChatSurface() {
        #expect(!WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.com/",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func claudeChatPagesAreChatSurface() {
        #expect(WebChatSurfaceLogic.isChatSurface(
            urlString: "https://claude.ai/new",
            chatURL: "https://claude.ai/new", vendor: .claude))
        #expect(WebChatSurfaceLogic.isChatSurface(
            urlString: "https://claude.ai/chat/0738554f-539a-4a82-9a04-68941434fbed",
            chatURL: "https://claude.ai/new", vendor: .claude))
    }
}

@Suite("WebChatSurfaceLogic.isProductDetour (same-host product switch)")
struct WebChatSurfaceDetourTests {
    @Test func kimiAgentAfterMenuClickIsDetour() {
        #expect(WebChatSurfaceLogic.isProductDetour(
            afterURL: "https://www.kimi.ai/agent?chat_enter_method=change_model",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func kimiChatPageIsNotDetour() {
        #expect(!WebChatSurfaceLogic.isProductDetour(
            afterURL: "https://www.kimi.ai/chat/1a07fb7f-67f2-87c5-8000-09e874e746d5",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func hostChangeIsNotDetour() {
        // Region setups legitimately differ — never force-navigate there.
        #expect(!WebChatSurfaceLogic.isProductDetour(
            afterURL: "https://kimi.com/chat",
            chatURL: "https://www.kimi.ai/", vendor: .kimi))
    }

    @Test func emptyChatURLNeverDetours() {
        #expect(!WebChatSurfaceLogic.isProductDetour(
            afterURL: "https://example.com/agent",
            chatURL: "", vendor: .custom))
    }

    @Test func otherVendorsNeverDetour() {
        #expect(!WebChatSurfaceLogic.isProductDetour(
            afterURL: "https://claude.ai/agent",
            chatURL: "https://claude.ai/new", vendor: .claude))
    }
}

/// Audit 2026-09-09 (Kimi live): K3/K3 Swarm live on /agent (the model menu
/// navigates there AND commits the choice; the /agent composer honors the
/// same send contract). Surface checks are model-aware: /agent is home for
/// agent models and drift for chat models.
@Suite("WebChatSurfaceLogic model-aware Kimi surfaces")
struct WebChatSurfaceModelAwareTests {
    @Test func kimiAgentIsChatSurfaceForK3() {
        #expect(WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/agent?chat_enter_method=change_model",
            chatURL: "https://www.kimi.ai/", vendor: .kimi, selectedModel: "K3"))
    }

    @Test func kimiAgentIsChatSurfaceForK3Swarm() {
        #expect(WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/agent-swarm",
            chatURL: "https://www.kimi.ai/", vendor: .kimi, selectedModel: "K3 Swarm"))
    }

    @Test func kimiAgentIsDriftForFastModel() {
        #expect(!WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/agent",
            chatURL: "https://www.kimi.ai/", vendor: .kimi, selectedModel: "Быстрый"))
    }

    @Test func kimiChatPageIsDriftForK3() {
        #expect(!WebChatSurfaceLogic.isChatSurface(
            urlString: "https://www.kimi.ai/chat/1a07fb7f-67f2-87c5-8000-09e874e746d5",
            chatURL: "https://www.kimi.ai/", vendor: .kimi, selectedModel: "K3"))
    }

    @Test func kimiAgentIsNotDetourForK3() {
        #expect(!WebChatSurfaceLogic.isProductDetour(
            afterURL: "https://www.kimi.ai/agent?chat_enter_method=change_model",
            chatURL: "https://www.kimi.ai/", vendor: .kimi, selectedModel: "K3"))
    }

    @Test func targetSurfaceURLPointsK3ToAgent() {
        #expect(WebChatSurfaceLogic.targetSurfaceURL(
            chatURL: "https://www.kimi.ai/", vendor: .kimi,
            selectedModel: "K3") == "https://www.kimi.ai/agent")
    }

    @Test func targetSurfaceURLKeepsChatForFast() {
        #expect(WebChatSurfaceLogic.targetSurfaceURL(
            chatURL: "https://www.kimi.ai/", vendor: .kimi,
            selectedModel: "Быстрый") == "https://www.kimi.ai/")
    }
}

/// Audit 2026-09-08 (Kimi): while waiting, the DOM can stabilize on our own
/// just-sent message (renders before generation starts). That echo must not
/// finalize the turn before generation is observed.
@Suite("WebChatEchoLogic (own-message echo guard)")
struct WebChatEchoLogicTests {

    @Test func exactEchoMatches() {
        #expect(WebChatEchoLogic.isEcho("Reply with exactly: TEST-OK-QWEN", of: "Reply with exactly: TEST-OK-QWEN"))
    }

    @Test func identicalTextsMatch() {
        #expect(WebChatEchoLogic.isEcho("hello world", of: "hello world"))
    }

    @Test func unrelatedAnswerIsNotEcho() {
        #expect(!WebChatEchoLogic.isEcho("Need output exactly string", of: "Reply with exactly: TEST-OK-KIMI-FINAL3"))
    }

    @Test func exactStringAnswerIsNotEcho() {
        // Live 2026-09-08 (Claude): the model answered the exact requested
        // string, which a containment guard wrongly classified as our own
        // message echo and stalled the turn. Echo requires full equality.
        #expect(!WebChatEchoLogic.isEcho("TEST-OK-CLAUDE", of: "Reply with exactly: TEST-OK-CLAUDE"))
    }

    @Test func shortFragmentsNeverMatch() {
        #expect(!WebChatEchoLogic.isEcho("Need", of: "Reply with exactly: TEST-OK-KIMI-FINAL3"))
        #expect(!WebChatEchoLogic.isEcho("", of: "something"))
        #expect(!WebChatEchoLogic.isEcho("abc", of: "def"))
    }

    @Test func whitespaceDifferencesIgnored() {
        #expect(WebChatEchoLogic.isEcho("  hello\nworld  ", of: "Hello World"))
    }
}

/// Audit 2026-09-08: binding must derive the id from the SAME url string the
/// gate approved — two separate live URL reads raced a SPA navigation commit
/// (gate saw /c/{uuid}, extractor saw "" and fell back to a stale sidebar id).
@Suite("WebRemoteChatIdentityLogic.chatIDFromURL")
struct ChatIDFromURLTests {

    @Test func extractsChatGPTConversationID() {
        #expect(WebRemoteChatIdentityLogic.chatIDFromURL(
            "https://chatgpt.com/c/6a9ff33c-fba8-83ec-b488-69781fb84bc4")
            == "6a9ff33c-fba8-83ec-b488-69781fb84bc4")
    }

    @Test func extractsKimiChatIDWithQuery() {
        #expect(WebRemoteChatIdentityLogic.chatIDFromURL(
            "https://www.kimi.ai/chat/1a0808b4-5f22-8942-8000-09e8df26d2a7?chat_enter_method=new_chat")
            == "1a0808b4-5f22-8942-8000-09e8df26d2a7")
    }

    @Test func homePageHasNoID() {
        #expect(WebRemoteChatIdentityLogic.chatIDFromURL("https://chatgpt.com/") == nil)
        #expect(WebRemoteChatIdentityLogic.chatIDFromURL("https://www.kimi.ai/?chat_enter_method=new_chat") == nil)
    }

    @Test func historyPageHasNoID() {
        #expect(WebRemoteChatIdentityLogic.chatIDFromURL("https://www.kimi.ai/chat/history") == nil)
    }

    @Test func emptyURLHasNoID() {
        #expect(WebRemoteChatIdentityLogic.chatIDFromURL("") == nil)
    }
}

/// Audit 2026-09-08 (ChatGPT): per-turn client keys ("WEB:<uuid>") must never
/// bind as the conversation id.
@Suite("RemoteChatIdentity colon rejection")
struct RemoteChatColonRejectionTests {

    @Test func webPrefixedTurnKeyRejected() {
        #expect(WebRemoteChatIdentityLogic.firstValid(["WEB:4e9d1312-dcb3-4146-863e-733ee9830179"]) == nil)
    }

    @Test func requestPrefixedTurnKeyRejected() {
        #expect(WebRemoteChatIdentityLogic.firstValid(["request-WEB:4e9d1312-dcb3-4146-863e-733ee9830179-0"]) == nil)
    }

    @Test func plainUUIDStillAccepted() {
        let id = "6a9ff33c-fba8-83ec-b488-69781fb84bc4"
        #expect(WebRemoteChatIdentityLogic.firstValid([id]) == id)
    }

    @Test func rejectionFallsThroughToNextCandidate() {
        let real = "6a9ff33c-fba8-83ec-b488-69781fb84bc4"
        #expect(WebRemoteChatIdentityLogic.firstValid(["WEB:4e9d1312-dcb3-4146-863e-733ee9830179", real]) == real)
    }
}
