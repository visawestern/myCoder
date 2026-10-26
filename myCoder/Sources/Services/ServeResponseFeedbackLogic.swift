enum ServeResponseFeedbackLogic {
    static func failureMessage(responseCount: Int,
                               text: String?,
                               reasoning: String?,
                               hasToolActivity: Bool) -> String? {
        guard responseCount > 0 else {
            return ProviderResponseValidationLogic.emptyCompletionMessage
        }
        return failureMessage(
            text: text ?? "",
            reasoning: reasoning ?? "",
            hasToolActivity: hasToolActivity
        )
    }

    static func failureMessage(text: String,
                               reasoning: String,
                               hasToolActivity: Bool) -> String? {
        guard ProviderResponseValidationLogic.shouldReportEmptyCompletion(
            text: text,
            reasoning: reasoning,
            hasToolActivity: hasToolActivity
        ) else { return nil }
        return ProviderResponseValidationLogic.emptyCompletionMessage
    }
}
