import Foundation

/// Rules for upgrading a standalone chat to a project chat (user directive
/// 2026-11-13: «он должен "обновить" текущий чат до проекта без смены
/// модели и продолжить в нём, изменив рабочую папку и поставив статус
/// открытого проекта, а также написав модели, что проект перенесен в папку
/// такую-то — продолжай работать»).
///
/// The current chat keeps its id, title, messages, model and provider; only
/// its working directory / owning project changes. The model receives a
/// notice that the project is bound so it continues in the same chain instead
/// of restarting searches.
///
/// Input: the old session and the project path.
/// Output: the bound session and the model notice text.
/// Dependencies: `ChatSession.normalizedPath`.
enum SessionProjectBindLogic {

    /// The session bound to a project folder (same id/title/model/provider).
    ///
    /// Input: original session, project path.
    /// Output: a copy whose `directory` (and the owning project) is the
    /// normalized project path.
    /// Dependencies: `ChatSession.normalizedPath`.
    static func boundSession(_ session: ChatSession, to path: String) -> ChatSession {
        var bound = session
        bound.directory = ChatSession.normalizedPath(path)
        return bound
    }

    /// Normalized owning-project id for a path.
    static func projectID(for path: String) -> String {
        ChatSession.normalizedPath(path)
    }

    /// The notice the model receives after the binding: it must continue in
    /// the project folder, not search files anew.
    ///
    /// Input: project path. Output: notice text.
    /// Dependencies: `ChatSession.normalizedPath`.
    static func modelNotice(projectPath: String) -> String {
        let normalized = ChatSession.normalizedPath(projectPath)
        return "Проект привязан к папке \(normalized). Рабочая папка этого чата изменена на проект. "
            + "Продолжай выполнение задачи прямо в ней: файлы теперь читаются и пишутся внутри проекта. "
            + "Не ищи файлы заново и не проси пользователя переносить что-либо."
    }

    /// The UI notice shown in the chat after the binding.
    static func uiNotice(projectPath: String) -> String {
        "Проект привязан: \(ChatSession.normalizedPath(projectPath)). Чат продолжает работать в этом проекте."
    }
}
