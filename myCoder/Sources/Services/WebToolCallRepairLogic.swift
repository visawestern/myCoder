import Foundation

/// Stage-2 syntax repair for ambiguous or malformed tool-call blocks
/// (directive 2026-11-13, план п.8).
///
/// Purpose: deterministic parsers and `WebToolSchemaValidator` run first
/// without touching any model. Only when a response contains a tool-looking
/// block that failed deterministic parsing does this helper ask the internal
/// model (`InternalModelRunner`) to rewrite ONLY the syntax into canonical
/// ```tool JSON — never to decide execution or run tools itself.
///
/// Input: raw response text and an injectable completion closure (defaulting
/// to `InternalModelRunner.complete`).
/// Output: parsed `[WebToolCall]` if repair succeeded, otherwise `nil` (for
/// plain prose, already-parsed calls, or when the model emits no valid calls).
/// Dependencies: `WebToolProtocolEmulator`, `InternalModelRunner`.
enum WebToolCallRepairLogic {

    static let repairTimeout: TimeInterval = 45

    /// Repair syntax of an ambiguous/unparseable tool block via the internal model.
    ///
    /// Input: raw assistant response text + optional completion override for tests.
    /// Output: non-empty repaired `[WebToolCall]`, or `nil` when no repair is
    /// needed (plain prose or deterministic parse already succeeded) or failed.
    /// Dependencies: `WebToolProtocolEmulator`, `InternalModelRunner`.
    static func tryRepair(
        responseText: String,
        completion: ([DirectChatMessage]) async throws -> String = { messages in
            try await InternalModelRunner.complete(messages: messages, timeout: repairTimeout)
        }
    ) async -> [WebToolCall]? {
        // Stage 1 already succeeded — never invoke the model.
        guard WebToolProtocolEmulator.parseToolCalls(from: responseText).isEmpty else {
            return nil
        }
        // Plain prose must never trigger a model repair call.
        guard looksLikeToolCallAttempt(responseText) else {
            return nil
        }
        let messages = repairMessages(for: responseText)
        let raw: String
        do {
            raw = try await completion(messages)
        } catch {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let repaired = WebToolProtocolEmulator.parseToolCalls(from: trimmed)
        return repaired.isEmpty ? nil : repaired
    }

    /// True only when `text` contains a recognizable tool-call wrapper or marker
    /// (fenced ` ```tool `, XML/DSML/ERNIE/Anthropic tags, `[tool call: ...]`, etc.).
    static func looksLikeToolCallAttempt(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "```tool",
            "<tool_call",
            "<ernie:tool_call",
            "<function_calls",
            "<function_call",
            "<tool_use",
            "<invoke",
            "dsml| invoke",
            "dsml｜ invoke",
            "dsml invoke",
            "[tool call:",
            "<tool_name>",
            "⟨tool_name⟩"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func repairMessages(for rawResponse: String) -> [DirectChatMessage] {
        let toolNames = WebEmulatedTool.allCases.map(\.rawValue).joined(separator: ", ")
        let system = """
        You are a strict syntax repairer. Convert the broken or non-standard tool call block in the user message into valid ```tool JSON blocks ONLY, preserving the exact tool name and arguments.
        Format:
        ```tool
        {"name": "<tool_name>", "args": { ... }}
        ```
        Known tool names: \(toolNames).
        If there is no tool call intent, reply with NONE. Do not explain or add prose.
        """
        return [
            DirectChatMessage(role: "system", content: system),
            DirectChatMessage(role: "user", content: rawResponse)
        ]
    }
}
