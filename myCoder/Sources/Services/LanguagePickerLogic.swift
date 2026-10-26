import Foundation

/// Pure logic backing the custom language dropdown with flags (plan Раздел 2 Блок 4).
enum LanguagePickerLogic {
    /// All selectable languages in display order.
    static var allLanguages: [AppLanguage] { AppLanguage.allCases }

    /// A dropdown row: flag + native name + selected check (plan Блок 4 п.34).
    struct Row: Equatable {
        let language: AppLanguage
        let flag: String
        let nativeName: String
        let isSelected: Bool
        /// VoiceOver label combines flag meaning + name (plan Блок 4 п.39).
        var accessibilityLabel: String { "\(nativeName) language" }
    }

    static func rows(selected: AppLanguage) -> [Row] {
        allLanguages.map {
            Row(language: $0, flag: $0.flag, nativeName: $0.nativeName, isSelected: $0 == selected)
        }
    }

    /// Filter rows by a search query over native name or raw key (plan Блок 4 п.35).
    static func filter(_ rows: [Row], query: String) -> [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter {
            $0.nativeName.lowercased().contains(q) || $0.language.rawValue.lowercased().contains(q)
        }
    }
}
