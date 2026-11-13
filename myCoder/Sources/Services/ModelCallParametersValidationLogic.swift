import Foundation

enum ModelCallParametersValidationLogic {
    static func parse(temperature: String,
                      maxTokens: String,
                      topP: String,
                      systemPrompt: String,
                      requestLimit: String = "",
                      tokenQuota: String = "") -> ModelCallParameters? {
        let temperatureValue = tryParseDouble(temperature)
        let maxTokensValue = tryParsePositiveInt(maxTokens)
        let topPValue = tryParseDouble(topP)
        let requestLimitValue = tryParseNonNegativeInt(requestLimit)
        let tokenQuotaValue = tryParseNonNegativeInt(tokenQuota)

        if temperatureValue.map({ !(0.0...2.0).contains($0) }) == true { return nil }
        if topPValue.map({ !(0.0...1.0).contains($0) }) == true { return nil }
        if !maxTokens.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && maxTokensValue == nil { return nil }
        if !temperature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && temperatureValue == nil { return nil }
        if !topP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && topPValue == nil { return nil }
        // Blank quota fields mean "inherit/provider default" — only reject a
        // non-empty field that is not a non-negative integer.
        if !requestLimit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && requestLimitValue == nil { return nil }
        if !tokenQuota.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tokenQuotaValue == nil { return nil }

        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = trimmedPrompt.isEmpty ? nil : trimmedPrompt
        return ModelCallParameters(
            temperature: temperatureValue,
            maxTokens: maxTokensValue,
            topP: topPValue,
            systemPrompt: prompt,
            requestLimitPerMinute: requestLimitValue,
            tokenQuotaPerMinute: tokenQuotaValue
        )
    }

    private static func tryParseDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else { return nil }
        return parsed
    }

    private static func tryParsePositiveInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Int(trimmed), parsed > 0 else { return nil }
        return parsed
    }

    /// 0 allowed (unlimited); any non-negative integer accepted.
    private static func tryParseNonNegativeInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Int(trimmed), parsed >= 0 else { return nil }
        return parsed
    }
}
