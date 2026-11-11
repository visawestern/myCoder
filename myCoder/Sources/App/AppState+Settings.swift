import Foundation
import SwiftUI
import AppKit

/// Язык и обновление настроек.
extension AppState {
    var appLanguage: AppLanguage {
        AppLanguage.from(stored: settings.language)
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    func setLanguage(_ language: AppLanguage) {
        updateSettings { $0.language = language.rawValue }
        LocalizationRuntime.currentLanguage = language
        // Force UI refresh by bumping the language counter
        objectWillChange.send()
    }
}
