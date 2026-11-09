import Foundation

/// Почему вызов инструмента был прописан моделью, но так и не исполнен.
///
/// Требование владельца 2026-11-09: каждый вызов из ответа модели обязан
/// попасть под спойлер. Если он не исполнен — с конкретной причиной, как это
/// уже делается для ошибки валидации (`validation error: …`). Иначе вызов
/// молча исчезает: пользователь видит прозу без спойлера и не понимает, что
/// модель просила инструмент, а он не сработал.
enum ToolCallSkipReason: Equatable, Sendable {
    /// Цикл дошёл до лимита итераций и остановился до исполнения.
    case iterationLimit(Int)
    /// Пользователь остановил генерацию.
    case cancelled
    /// Блок вызова не удалось разобрать (битый JSON / обрезанный поток).
    case malformedBlock(String)
    /// Ход закончился, пока вызов ждал подтверждения пользователя.
    case awaitingApproval

    var text: String {
        switch self {
        case .iterationLimit(let limit):
            return "not executed: the turn reached its tool-iteration limit (\(limit)) before this call could run."
        case .cancelled:
            return "not executed: the turn was stopped before this call could run."
        case .malformedBlock(let problem):
            return "not executed: the tool block could not be parsed (\(problem))."
        case .awaitingApproval:
            return "not executed: the call was still waiting for user approval when the turn ended."
        }
    }
}

/// Строит tool-call части для вызовов, которые не были исполнены.
enum UnexecutedToolCallLogic {

    static func part(name: String,
                     arguments: [String: String],
                     callID: String,
                     reason: ToolCallSkipReason) -> MessagePartContent {
        let args = arguments.keys.sorted()
            .map { "\($0)=\(arguments[$0] ?? "")" }
            .joined(separator: " ")
        return .toolCall(name: name, args: args, result: reason.text, callID: callID)
    }

    /// Части для набора вызовов, до которых цикл не дошёл.
    static func parts(for calls: [WebToolCall],
                      reason: ToolCallSkipReason,
                      callID: (WebToolCall) -> String = { _ in UUID().uuidString }) -> [MessagePartContent] {
        calls.map { call in
            part(name: call.name,
                 arguments: call.arguments,
                 callID: callID(call),
                 reason: reason)
        }
    }
}
