import Foundation

/// Detects when a web model refuses to use tools without trying — e.g. Kimi
/// live 2026-09-11: "инструменты недоступны в этом окружении", "у меня нет
/// доступа к вашему компьютеру". Such a refusal would otherwise be accepted
/// as the final answer and the turn dies. Matched case-insensitively as
/// substrings; every marker names tool/computer access denial or context
/// loss explicitly, so ordinary clarification questions do not match.
enum WebRefusalLogic {
    static let refusalMarkers: [String] = [
        // RU: tool-availability denial.
        "не могу выполнить эти вызовы",
        "не могу выполнить вызовы",
        "недоступны в этом окружении",
        "инструменты недоступны",
        "инструменты не доступны",
        "нет доступа к вашему компьютеру",
        "нет доступа к вашим файлам",
        "нет доступа к вашей файловой",
        "у меня нет доступа к файлам",
        "у меня нет доступа к компьютеру",
        // RU: Kimi-identity refusal (live 2026-09-12: "я не Claude Code… у
        // меня другой набор инструментов… песочнице с /mnt/agents… мои тулзы
        // не имеют доступа к вашей файловой системе"). None of the older
        // markers matched — the detector was blind and the turn died.
        "не claude code",
        "другой набор инструментов",
        "не имеют доступа к ваш",
        "испускать блоки",
        "/mnt/agents",
        // RU: context loss.
        "нет контекста задачи",
        "нет контекста прошлого",
        "контекст не сохранился",
        "не сохранился контекст",
        // EN: tool-availability denial.
        "don't have access to your computer",
        "do not have access to your computer",
        "don't have access to your files",
        "do not have access to your files",
        "don't have access to the file system",
        "do not have access to the file system",
        "no file system access",
        "no filesystem access",
        "tools are not available",
        "tools aren't available",
        "no tools available",
        "tools unavailable",
        "tool is not available",
        "i cannot execute tools",
        "i can't execute tools",
        "cannot run tools",
        "can't run tools",
        "sandboxed model",
        "sandboxed chat model",
        // EN: Kimi-identity refusal (mirrors the RU class above).
        "i am not claude code",
        "i'm not claude code",
        "different set of tools",
        "have access to your machine",
        "my tools run in",
        // EN: context loss.
        "lost the context",
        "context was lost",
        "have no context from",
        "no context from last",
    ]

    /// True when the text refuses tool use (or reports lost context) instead
    /// of answering or emitting tool calls.
    static func isToolRefusal(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        let lower = trimmed.lowercased()
        return refusalMarkers.contains { lower.contains($0) }
    }
}
