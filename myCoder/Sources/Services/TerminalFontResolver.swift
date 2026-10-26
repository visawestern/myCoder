import AppKit
import SwiftUI

enum TerminalFontResolver {

    static func resolvedFontName(settings: AppSettings) -> String {
        let override = settings.terminalFont.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            return override
        }
        if settings.inheritTerminalProfile, let inherited = inheritedTerminalFontName() {
            return inherited
        }
        return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
    }

    static func displayLabel(settings: AppSettings, language: AppLanguage) -> String {
        let effective = resolvedFontName(settings: settings)
        let override = settings.terminalFont.trimmingCharacters(in: .whitespacesAndNewlines)
        if override.isEmpty && settings.inheritTerminalProfile {
            return String(format: AppLocalization.string(.settingsTerminalFontCurrentInherited, language: language), effective)
        }
        return String(format: AppLocalization.string(.settingsTerminalFontCurrentOverride, language: language), effective)
    }

    static func resolvedNSFont(size: CGFloat, settings: AppSettings) -> NSFont {
        let name = resolvedFontName(settings: settings)
        if let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func swiftUIFont(size: CGFloat, settings: AppSettings) -> Font {
        Font(resolvedNSFont(size: size, settings: settings))
    }

    static func inheritedTerminalFontName() -> String? {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.Terminal.plist")

        if let data = FileManager.default.contents(atPath: plistURL.path),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let defaultProfile = plist["Default Window Settings"] as? String,
           let windowSettings = plist["Window Settings"] as? [String: Any],
           let profile = windowSettings[defaultProfile] as? [String: Any],
           let fontData = profile["Font"] as? Data,
           let font = unarchiveFont(from: fontData) {
            return font.fontName
        }

        return NSFont.userFixedPitchFont(ofSize: 12)?.fontName
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
    }

    private static func unarchiveFont(from data: Data) -> NSFont? {
        if let font = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: data) {
            return font
        }
        // Terminal.app may store legacy NSFont archives.
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: "NSFont") as? NSFont
    }
}
