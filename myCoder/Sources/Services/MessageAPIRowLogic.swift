import Foundation

/// Builds one `/api/messages` row from a stored message.
///
/// The context pipeline was unverifiable over HTTP: `contextSummary`, the
/// compiled point context and the raw wire responses all lived in the message
/// model but never reached the JSON. Anything the UI can show about how a turn
/// was assembled must also be readable through the API, otherwise "did the
/// system prompt and point context actually go out?" can only be answered by
/// clicking through the app.
enum MessageAPIRowLogic {

    /// The full row for one message. Always carries the base fields; the
    /// context fields appear only when they hold something, so an ordinary
    /// turn does not grow three null keys.
    static func row(for msg: Message) -> [String: Any] {
        var row: [String: Any] = [
            "id": msg.id,
            "role": msg.role == .user ? "user" : "assistant",
            "content": msg.content,
            "isFinished": msg.isFinished,
            "isStreaming": msg.isStreaming
        ]

        // Сколько вызовов было в этом ответе — видно и в API, чтобы можно
        // было проверить, что несколько вызовов собраны в одно сообщение.
        if msg.toolCallCount > 0 {
            row["toolCallCount"] = msg.toolCallCount
        }

        if let summary = msg.contextSummary, !summary.isEmpty {
            row["contextSummary"] = summary
        }

        // The compiled pack is stored as a part, not a field: it is the exact
        // text that went to the model (system prompt + point context + request).
        if let pack = compiledContext(in: msg.parts), !pack.isEmpty {
            row["compiledContext"] = pack
        }

        if let raw = msg.rawResponses, !raw.isEmpty {
            row["rawResponses"] = raw
        }

        return row
    }

    /// The compiled point context carried by a message, if any.
    static func compiledContext(in parts: [MessagePartContent]) -> String? {
        for part in parts {
            if case .compiledContext(let text) = part { return text }
        }
        return nil
    }
}
