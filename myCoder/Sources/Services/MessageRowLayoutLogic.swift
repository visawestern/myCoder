import Foundation

/// Telegram-style chat layout: user messages hug the trailing edge with a
/// width-capped bubble and their action bar attached right under the bubble;
/// assistant/system messages stay on the leading side at full width.
enum MessageRowLayoutLogic {
    static let userBubbleMaxWidth: CGFloat = 480
    static let actionBarSpacing: CGFloat = 4

    static func isTrailing(role: MessageRole) -> Bool {
        role == .user
    }
}
