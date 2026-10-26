import Testing
@testable import myCoder

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
