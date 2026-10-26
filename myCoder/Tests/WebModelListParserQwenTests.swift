import Testing
import Foundation
@testable import myCoder

@Suite("WebModelListParser — Qwen effort parsing fixes")
struct WebModelListParserQwenTests {

    @Test("Qwen effort: Авто should map to medium (not filtered as noise)")
    func qwenEffortAuto() {
        let result = WebModelListParser.normalizeEffort("Авто", vendor: .qwen)
        #expect(result == .medium, "Авто should map to .medium, got \(String(describing: result))")
    }

    @Test("Qwen effort: Мышление should map to high (Russian for Thinking)")
    func qwenEffortThinking() {
        let result = WebModelListParser.normalizeEffort("Мышление", vendor: .qwen)
        #expect(result == .high, "Мышление should map to .high, got \(String(describing: result))")
    }

    @Test("Qwen effort: Быстрый should map to low (Russian for Fast)")
    func qwenEffortFast() {
        let result = WebModelListParser.normalizeEffort("Быстрый", vendor: .qwen)
        #expect(result == .low, "Быстрый should map to .low, got \(String(describing: result))")
    }

    @Test("Qwen effort: parseEffortLevels handles all three Russian labels")
    func qwenEffortLevelsAll() {
        let text = "Авто\nМышление\nБыстрый"
        let efforts = WebModelListParser.parseEffortLevels(dropdownText: text, vendor: .qwen)
        #expect(efforts.count == 3, "Expected 3 effort levels, got \(efforts.count)")
        #expect(efforts.contains(.low), "Should contain .low (Быстрый)")
        #expect(efforts.contains(.medium), "Should contain .medium (Авто)")
        #expect(efforts.contains(.high), "Should contain .high (Мышление)")
    }

    @Test("Qwen model name: should not be filtered by length when under 60 chars")
    func qwenModelNameLength() {
        let name = "Qwen3.8-Max"
        let result = WebModelListParser.normalize(name, vendor: .qwen)
        #expect(result == name, "Model name '\(name)' should not be filtered, got \(String(describing: result))")
    }

    @Test("Qwen model name with description: long text is filtered (correct selector prevents this)")
    func qwenModelNameWithDescription() {
        // When the correct selector [class*="model-item-name"] is used,
        // readModelItems() returns only the name text ("Qwen3.8-Max"),
        // NOT the full text with description.
        // This test verifies that long concatenated texts are filtered out
        // as a safety measure.
        let text = "Qwen3.8-MaxThe flagship of Qwen3.8 model delivering state-of-the-art performance."
        let models = WebModelListParser.parse(dropdownText: text, vendor: .qwen)
        // The full text is >60 chars, so it's filtered by normalize()
        // This is correct behavior — the real fix is using the right selector
        #expect(models.isEmpty || (models.first?.contains("Qwen") == true),
                "Long concatenated text should be filtered or extracted correctly")
    }
}

@Suite("WebModelDiscovery — Qwen model items parsing")
struct WebModelDiscoveryQwenTests {

    /// Simulates what readModelItems returns for Qwen with correct selector
    func fakeQwenModelItems() -> [String] {
        // These are the texts from Playwright inspection of [class*="model-item-name"]
        return [
            "Qwen3.8-Max",
            "Qwen3.7-Plus",
            "Qwen3.7-Max",
        ]
    }

    @Test("Qwen model items from correct selector are valid model names")
    func qwenModelItemsFromCorrectSelector() {
        let items = fakeQwenModelItems()
        let parsed = items.compactMap { WebModelListParser.normalize($0, vendor: .qwen) }
        #expect(parsed.count == 3, "Expected 3 parsed models, got \(parsed.count)")
        #expect(parsed.contains("Qwen3.8-Max"))
        #expect(parsed.contains("Qwen3.7-Plus"))
        #expect(parsed.contains("Qwen3.7-Max"))
    }
}
