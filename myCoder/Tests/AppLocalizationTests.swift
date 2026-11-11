import Testing
@testable import myCoder

@MainActor
@Suite("App localization")
struct AppLocalizationTests {

    @Test("English and Russian differ for settings title")
    func localizedSettingsTitle() {
        let en = AppLocalization.string(.settingsGeneralTitle, language: .english)
        let ru = AppLocalization.string(.settingsGeneralTitle, language: .russian)
        #expect(en == "General")
        #expect(ru == "Общие")
        #expect(en != ru)
    }

    @Test("Prompt placeholder switches with language")
    func localizedPrompt() {
        let en = MiMoCopy.promptPlaceholder(language: .english)
        let ru = MiMoCopy.promptPlaceholder(language: .russian)
        #expect(en.contains("Ask myCoder"))
        #expect(ru.contains("Спросите"))
    }

    @Test("Parses stored language")
    func parsesLanguage() {
        #expect(AppLanguage.from(stored: "Russian") == .russian)
        #expect(AppLanguage.from(stored: "unknown") == .english)
    }

    @Test("Every key has a translation entry for all 10 languages")
    func everyKeyHasAllLanguages() {
        let languageKeys = ["en", "ru", "es", "fr", "de", "zh", "ja", "ko", "pt", "ar"]
        let gaps: [String] = AppLocalizationKey.allCases.compactMap { key in
            guard let entry = AppLocalization.translations[key.rawValue] else {
                return "\(key.rawValue) has no dict entry"
            }
            let missing = languageKeys.filter { entry[$0] == nil || entry[$0]!.isEmpty }
            return missing.isEmpty ? nil : "\(key.rawValue) missing: \(missing)"
        }
        #expect(gaps.isEmpty, "Translation gaps: \(gaps)")
    }

    @Test("Every translation uses only valid language keys")
    func onlyValidLanguageKeys() {
        let valid = Set(["en", "ru", "es", "fr", "de", "zh", "ja", "ko", "pt", "ar"])
        let invalid = AppLocalization.translations.values.flatMap { Array($0.keys) }.filter { !valid.contains($0) }
        #expect(invalid.isEmpty, "Invalid language keys: \(invalid)")
    }

    @Test("Every string-table entry has all 10 languages")
    func everyTableEntryHasAllLanguages() {
        let languageKeys = ["en", "ru", "es", "fr", "de", "zh", "ja", "ko", "pt", "ar"]
        let gaps: [String] = AppLocalization.translations.compactMap { key, entry in
            let missing = languageKeys.filter { entry[$0]?.isEmpty != false }
            return missing.isEmpty ? nil : "\(key) missing: \(missing)"
        }
        #expect(gaps.isEmpty, "Translation gaps: \(gaps)")
    }

    @Test("Translation parts do not overlap")
    func translationPartsDoNotOverlap() {
        let parts = [
            Set(AppLocalization.translationsPart1().keys),
            Set(AppLocalization.translationsPart2().keys),
            Set(AppLocalization.translationsPart3().keys),
        ]
        for i in parts.indices {
            for j in parts.indices where j > i {
                let overlap = parts[i].intersection(parts[j])
                #expect(overlap.isEmpty, "Parts \(i + 1) and \(j + 1) overlap: \(overlap.sorted())")
            }
        }
    }

    @Test("Late hardcoded strings are translated")
    func lateHardcodedStringsTranslated() {
        for key in ["Chat title", "Save title", "Delete this chat?", "Open", "Export", "Import",
                    "Language Servers (LSP)", "Routing mode", "Rollback complete"] {
            for language in AppLanguage.allCases {
                let value = AppLocalization.string(forEnglish: key, language: language)
                #expect(value != key || language == .english,
                        "\(key) is not translated for \(language)")
            }
        }
    }

    @Test("GitHub publish wizard strings localized in both languages")
    func gitPublishWizardStrings() {
        let keys: [AppLocalizationKey] = [
            .gitInstallGHTitle, .gitInstallGHSubtitle, .gitInstallGHButton,
            .gitSignInTitle, .gitSignInSubtitle, .gitSignInButton,
            .gitCreateAndPush, .gitCancel, .gitInitSubtitle,
            .gitReviewComment, .gitReviewCommentPlaceholder, .gitReviewSummary,
            .gitCommitAndPush, .gitOpenGitHubDocs,
        ]
        for key in keys {
            let en = AppLocalization.string(key, language: .english)
            let ru = AppLocalization.string(key, language: .russian)
            #expect(!en.isEmpty)
            #expect(!ru.isEmpty)
        }
        #expect(AppLocalization.string(.gitSignInButton, language: .english) == "Sign in with browser")
        #expect(AppLocalization.string(.gitCommitAndPush, language: .russian) == "Коммит и пуш")
    }
}
