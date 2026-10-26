import Foundation

enum ProviderResponseValidationLogic {
    static let emptyCompletionMessage =
        "The provider returned an empty response. Check the selected model and retry."

    static func hasVisibleContent(_ content: String?) -> Bool {
        guard let content else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldReportEmptyCompletion(
        text: String?,
        reasoning: String?,
        hasToolActivity: Bool
    ) -> Bool {
        !hasVisibleContent(text) && !hasVisibleContent(reasoning) && !hasToolActivity
    }
}
