import Foundation

/// App-state plumbing for the context-assembly log.
///
/// The composer status line is a spoiler over this log: every action keeps
/// what was requested, how it was processed and what came back. The send path
/// writes it through the pure logic, so the whole journal can be replayed in
/// tests without a UI. Each run is stored under the chat it belongs to (C1),
/// so a background chat never paints its journal into the visible one.
extension AppState {

    /// Open a new context-assembly run for one chat.
    ///
    /// Вход: `message` — запрос пользователя; `projectRoot` — проект чата;
    /// `sessionID` — чат, которому принадлежит отправка.
    /// Выход: нет; пустой id игнорируется (некому показывать журнал).
    /// Зависимости: `ContextAssemblyLogLogic.begin`, `ContextSessionStatusLogic`.
    func beginContextAssembly(message: String, projectRoot: String, sessionID: String?) {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return }
        contextAssemblyLogs[key] = ContextAssemblyLogLogic.begin(
            message: message,
            projectRoot: projectRoot
        )
    }

    /// Add or update one action in the chat's journal.
    ///
    /// Вход: `key` — стабильный ключ действия; `title`, `request`,
    /// `processing` — тексты действия; `sessionID` — чат сборки.
    /// Выход: нет.
    /// Зависимости: `ContextAssemblyLogLogic.start`.
    func startContextAction(key: String,
                            title: String,
                            request: String,
                            processing: String,
                            sessionID: String?) {
        let sessionKey = ContextSessionStatusLogic.key(sessionID)
        guard !sessionKey.isEmpty else { return }
        let log = contextAssemblyLogs[sessionKey] ?? .empty
        contextAssemblyLogs[sessionKey] = ContextAssemblyLogLogic.start(
            key: key,
            title: title,
            request: request,
            processing: processing,
            in: log
        )
    }

    /// Close one action in the chat's journal with its real outcome.
    ///
    /// Вход: `key` — ключ действия; `result` — что вернулось; `status`;
    /// `sessionID` — чат сборки.
    /// Выход: нет.
    /// Зависимости: `ContextAssemblyLogLogic.finish`.
    func finishContextAction(key: String,
                             result: String,
                             status: ContextAssemblyLogLogic.Status = .done,
                             sessionID: String?) {
        let sessionKey = ContextSessionStatusLogic.key(sessionID)
        guard !sessionKey.isEmpty else { return }
        let log = contextAssemblyLogs[sessionKey] ?? .empty
        contextAssemblyLogs[sessionKey] = ContextAssemblyLogLogic.finish(
            key: key,
            result: result,
            status: status,
            in: log
        )
    }

    /// Finalize the chat's journal with the facts of the completed run.
    ///
    /// Вход: `facts` — реальные итоги сборки; `sessionID` — чат сборки.
    /// Выход: нет.
    /// Зависимости: `ContextAssemblyLogLogic.finalize`.
    func completeContextAssembly(_ facts: ContextAssemblyLogLogic.Facts,
                                 sessionID: String?) {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return }
        let log = contextAssemblyLogs[key] ?? .empty
        contextAssemblyLogs[key] = ContextAssemblyLogLogic.finalize(
            log: log,
            facts: facts
        )
    }
}
