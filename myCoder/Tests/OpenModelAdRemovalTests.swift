import Testing
import Foundation
@testable import myCoder

@Suite("OpenModel Advertising Removal")
struct OpenModelAdRemovalTests {

    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private static func allSwiftSources() throws -> [(path: String, contents: String)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            result.append((url.path, contents))
        }
        return result
    }

    @Test("No OpenModel promo strings remain anywhere in Sources")
    func noPromoStringsInSources() throws {
        let forbidden = [
            "openmodel.ai/event",
            "free on OpenModel",
            "OpenModel event",
            "selectOpenModelDeepSeekPreset",
            "openModelDeepSeekV4FlashID",
            "CustomProviderPresets",
            "ensureBundledCustomProviders",
        ]
        for (path, contents) in try Self.allSwiftSources() {
            for needle in forbidden {
                #expect(
                    !contents.contains(needle),
                    "Promo remnant \"\(needle)\" found in \(path)"
                )
            }
        }
    }

    @Test("defaultModel does not promote deepseek-v4-flash")
    func defaultModelHasNoPromotedModel() {
        let custom = CustomProvider(
            id: "custom-1",
            name: "Custom",
            type: .openAI,
            baseURL: "https://example.com/v1",
            isEnabled: true,
            models: ["deepseek-v4-flash", "alpha-model"]
        )
        let result = ProviderSettingsLogic.defaultModel(
            for: "custom-1",
            in: [],
            customProviders: [custom]
        )
        #expect(result == "alpha-model")
    }

    @Test("defaultModel picks the first sorted custom model")
    func defaultModelPicksFirstSortedCustomModel() {
        let custom = CustomProvider(
            id: "custom-1",
            name: "Custom",
            type: .openAI,
            baseURL: "https://example.com/v1",
            isEnabled: true,
            models: ["deepseek-v4-flash", "big-pickle", "alpha-model"]
        )
        let result = ProviderSettingsLogic.defaultModel(
            for: "custom-1",
            in: [],
            customProviders: [custom]
        )
        #expect(result == "alpha-model")
    }
}
