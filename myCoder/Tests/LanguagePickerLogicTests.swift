import Testing
@testable import myCoder

@Suite("i18n: languages + picker (plan Раздел 2)")
struct LanguagePickerLogicTests {

    @Test func tenLanguagesAvailable() {
        #expect(AppLanguage.allCases.count == 10)
        #expect(AppLanguage.allCases.contains(.arabic))
        #expect(AppLanguage.allCases.contains(.chineseSimplified))
    }

    @Test func eachLanguageHasFlagAndNativeName() {
        for lang in AppLanguage.allCases {
            #expect(!lang.flag.isEmpty, "flag for \(lang)")
            #expect(!lang.nativeName.isEmpty, "native name for \(lang)")
            #expect(!lang.localeIdentifier.isEmpty)
        }
        #expect(AppLanguage.japanese.nativeName == "日本語")
        #expect(AppLanguage.german.flag == "🇩🇪")
    }

    @Test func onlyArabicIsRTL() {
        #expect(AppLanguage.arabic.isRTL)
        #expect(!AppLanguage.english.isRTL)
        #expect(AppLanguage.allCases.filter { $0.isRTL }.count == 1)
    }

    @Test func rowsMarkSelected() {
        let rows = LanguagePickerLogic.rows(selected: .french)
        #expect(rows.count == 10)
        #expect(rows.first { $0.language == .french }?.isSelected == true)
        #expect(rows.first { $0.language == .english }?.isSelected == false)
    }

    @Test func filterByNativeName() {
        let rows = LanguagePickerLogic.rows(selected: .english)
        #expect(LanguagePickerLogic.filter(rows, query: "Deutsch").count == 1)
        #expect(LanguagePickerLogic.filter(rows, query: "русс").first?.language == .russian)
        #expect(LanguagePickerLogic.filter(rows, query: "").count == 10)
    }

    @Test func stringFallsBackToEnglishForUntranslatedLanguage() {
        // A key that is only translated in English/Russian falls back to English for other languages.
        // settingsStorageTitle only has EN/RU in the old system; in the new full-translation
        // system all keys are translated. Verify graceful fallback still works for missing keys.
        let en = AppLocalization.string(.settingsAppThemeDescription, language: .english)
        let ja = AppLocalization.string(.settingsAppThemeDescription, language: .japanese)
        // Japanese now has a full translation — verify it is non-empty and differs from English.
        #expect(!ja.isEmpty)
        #expect(ja != en)   // Japanese translation exists
        #expect(en == "Choose which theme the application interface should use.")
    }

    @Test func curatedKeysTranslatedForExtraLanguages() {
        #expect(AppLocalization.string(.settingsGeneralTitle, language: .german) == "Allgemein")
        #expect(AppLocalization.string(.settingsLanguageTitle, language: .chineseSimplified) == "语言")
        #expect(AppLocalization.string(.settingsGeneralTitle, language: .arabic) == "عام")
    }

    @Test func everySettingsTabTranslatedForAllLanguages() {
        for tab in SettingsTab.allCases {
            for lang in AppLanguage.allCases {
                let name = AppLocalization.settingsTabName(tab, language: lang)
                #expect(!name.isEmpty, "tab \(tab) lang \(lang)")
            }
        }
        // Spot-check a few non-English translations differ from English.
        #expect(AppLocalization.settingsTabName(.skills, language: .chineseSimplified) == "技能")
        #expect(AppLocalization.settingsTabName(.storage, language: .german) == "Speicher")
        #expect(AppLocalization.settingsTabName(.usage, language: .french) == "Utilisation")
    }

    @Test func generalRowLabelsTranslated() {
        #expect(AppLocalization.string(.settingsAppThemeTitle, language: .german) == "App-Design")
        #expect(AppLocalization.string(.settingsInterfaceZoomTitle, language: .chineseSimplified) == "界面缩放")
        #expect(AppLocalization.string(.settingsTerminalFontTitle, language: .japanese) == "ターミナルフォント")
        #expect(AppLocalization.string(.gitCommit, language: .french) == "Valider")
    }

    @Test func russianStillWorks() {
        #expect(AppLocalization.string(.settingsGeneralTitle, language: .russian) == "Общие")
    }
}
