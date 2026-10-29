import Foundation

enum SessionReloadLogic {
    /// Whether selecting a chat should re-read its history from the server or
    /// the database.
    ///
    /// The message store keeps one feed per session, so a chat that has already
    /// been loaded is shown instantly and must **not** be re-read: a model turn
    /// may still be streaming into it, and its newest chunks can be ahead of
    /// the last database write.
    ///
    /// This used to be blocked whenever *any* send was in flight, which meant
    /// switching chats during a generation left the previous chat's messages
    /// under the newly selected title. Background turns make that condition
    /// invalid: the in-flight turn belongs to another session and has its own
    /// feed.
    static func shouldReloadMessages(hasCachedMessages: Bool) -> Bool {
        !hasCachedMessages
    }
}
