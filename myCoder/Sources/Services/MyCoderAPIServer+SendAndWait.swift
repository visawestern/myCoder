import Foundation

extension MyCoderAPIServer {
    /// Sends a message like /api/send, then polls the target session's
    /// messages until the assistant turn finishes (bounded wait) and returns
    /// the conversation tail. This is the debug contract for "ask every
    /// provider a question and compare the answer".
    func handleSendAndWait(body: String) async -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            return jsonResponse(["error": "message is required"])
        }
        guard let appState = await Self.mainRead({ __myCoderAppState }) else {
            return jsonResponse(["error": "app not ready"])
        }
        let providerId = json["providerId"] as? String
        let modelId = json["modelId"] as? String
        let timeoutSec = (json["timeoutSec"] as? Int) ?? 180

        // Resolve target + post the send exactly like /api/send.
        let target = await Self.mainRead {
            let target = Self.resolveSendTargets(appState: appState,
                                                 providerId: providerId,
                                                 modelId: modelId,
                                                 chatId: json["chatId"] as? String,
                                                 message: message)
            NotificationCenter.default.post(
                name: Notification.Name("apiSendRequested"),
                object: nil,
                userInfo: ["message": message, "chatId": target.chatID]
            )
            return target
        }

        // Poll messages until the last assistant message finishes.
        // Audit 2026-09-08: internal UI status lines ("Thinking…", "Sent via …",
        // captcha/session notices) are NOT answers. Only content the vendor
        // actually produced completes the turn — the same contract the chat UI
        // enforces via WebSendCompletionLogic.
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSec))
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let messages = DatabaseBridge.shared.loadMessages(sessionId: target.chatID)
            if let last = messages.last,
               last.role == .assistant,
               last.isFinished,
               !last.content.isEmpty,
               SendWaitAnswerLogic.isRealAnswer(last.content) {
                let tail = messages.suffix(4).map { msg in
                    [
                        "role": msg.role == .user ? "user" : "assistant",
                        "content": String(msg.content.prefix(2000)),
                        "isFinished": msg.isFinished
                    ] as [String: Any]
                }
                return jsonResponse([
                    "status": "answered",
                    "chatId": target.chatID,
                    "providerId": target.providerID,
                    "modelId": target.modelID,
                    "messages": tail
                ])
            }
            // A visible error message also completes the turn.
            if let last = messages.last, last.role == .assistant, last.isFinished,
               last.content.hasPrefix("OpenCode Zen error:")
                   || last.content.hasPrefix("Web chat was not sent")
                   || last.content.hasPrefix("Web provider error:") {
                return jsonResponse([
                    "status": "error",
                    "chatId": target.chatID,
                    "providerId": target.providerID,
                    "modelId": target.modelID,
                    "error": String(last.content.prefix(1000)),
                    "messages": messages.suffix(2).map { ["role": $0.role == .user ? "user" : "assistant", "content": String($0.content.prefix(1000))] as [String: Any] }
                ])
            }
        }
        return jsonResponse([
            "status": "timeout",
            "chatId": target.chatID,
            "providerId": target.providerID,
            "modelId": target.modelID,
            "note": "no finished assistant message within \(timeoutSec)s — check /api/messages and /api/webviews"
        ])
    }
}
