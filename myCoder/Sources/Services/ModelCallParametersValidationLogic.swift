import Foundation

enum ModelCallParametersValidationLogic {
    static func parse(temperature: String,
                      maxTokens: String,
                      topP: String,
                      systemPrompt: String) -> ModelCallParameters? {
        let temperatureValue = tryParseDouble(temperature)
        let maxTokensValue = tryParsePositiveInt(maxTokens)
        let topPValue = tryParseDouble(topP)

        if temperatureValue.map({ !(0.0...2.0).contains($0) }) == true { return nil }
        if topPValue.map({ !(0.0...1.0).contains($0) }) == true { return nil }
        if !maxTokens.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && maxTokensValue == nil { return nil }
        if !temperature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && temperatureValue == nil { return nil }
        if !topP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && topPValue == nil { return nil }

        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = trimmedPrompt.isEmpty ? nil : trimmedPrompt
        return ModelCallParameters(
            temperature: temperatureValue,
            maxTokens: maxTokensValue,
            topP: topPValue,
            systemPrompt: prompt
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
}
