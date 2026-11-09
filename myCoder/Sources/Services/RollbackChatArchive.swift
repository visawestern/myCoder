import Foundation

/// Архив удаляемых при откате сообщений: перед тем как урезать диалог,
/// полная копия удаляемых сообщений сохраняется в глобальную корзину
/// (`~/.mycoder/deleted-backups/rollback-chats/`) — «удалять только в
/// корзину, а не насовсем».
enum RollbackChatArchive {

    /// Каталог архивов отката в корзине.
    static func directory(homeDirectory: URL) -> URL {
        ProjectAutoBackupLogic.deletedBackupsDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("rollback-chats", isDirectory: true)
    }

    /// Сохранить дамп сообщений и вернуть путь к файлу архива.
    @discardableResult
    static func archive(messages: [Message],
                        sessionID: String,
                        homeDirectory: URL) throws -> URL {
        let dir = directory(homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(sessionID)-\(stamp).json")

        let payload: [[String: Any]] = messages.map { message in
            [
                "id": message.id,
                "role": roleName(message.role),
                "content": message.content,
                "timestamp": message.timestamp.timeIntervalSince1970,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func roleName(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }
}
