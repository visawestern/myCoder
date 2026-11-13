import AppKit
import SwiftUI
import Testing
import Foundation
@testable import myCoder

@MainActor
@Suite("Markdown render cache", .serialized)
struct ChatMarkdownCacheTests {

    private let sampleText = """
    # Заголовок

    Параграф с `инлайн-кодом` и **жирным** и *курсивом*.

    - пункт один
    - пункт два

    | A | B |
    |---|---|
    | 1 | 2 |
    """

    init() {
        MarkdownAttributedStringBuilder.clearCaches()
        MarkdownAttributedStringBuilder.resetStats()
    }

    @Test("cachedBuild возвращает тот же объект при повторе (hit)")
    func cachedBuildReturnsSameInstance() {
        let text = "cache-hit-\(UUID().uuidString)\n\nЧто-то важное."
        let a = MarkdownAttributedStringBuilder.cachedBuild(
            text: text, fontSize: 14, textColor: .black,
            codeSettings: .default, isLightInterface: true
        )
        let b = MarkdownAttributedStringBuilder.cachedBuild(
            text: text, fontSize: 14, textColor: .black,
            codeSettings: .default, isLightInterface: true
        )
        #expect(a === b)
    }

    @Test("cachedBuild идентичен build по содержимому")
    func cachedBuildMatchesBuild() {
        let plain = MarkdownAttributedStringBuilder.build(
            text: sampleText, fontSize: 14, textColor: .black,
            projectRoot: nil, codeSettings: .default, isLightInterface: true
        )
        let cached = MarkdownAttributedStringBuilder.cachedBuild(
            text: sampleText, fontSize: 14, textColor: .black,
            projectRoot: nil, codeSettings: .default, isLightInterface: true
        )
        #expect(cached.isEqual(to: plain))
    }

    @Test("Явная тема рендера не зависит от смены глобальной темы между build и cache")
    func explicitThemeIsStableAcrossGlobalThemeChanges() {
        let originalTheme: AppTheme = Color.mimo.isLightTheme ? .lightGlass : .dark
        defer { Color.mimo.setTheme(originalTheme) }
        let text = "theme-snapshot-\(UUID().uuidString)\n\n" + sampleText + "\n\n---\n\n1. шаг\n\n- [ ] задача"
        for isLight in [false, true] {
            Color.mimo.setTheme(.dark)
            let first = MarkdownAttributedStringBuilder.build(
                text: text, fontSize: 14, textColor: .black,
                codeSettings: .default, isLightInterface: isLight
            )
            let seeded = MarkdownAttributedStringBuilder.cachedBuild(
                text: text, fontSize: 14, textColor: .black,
                codeSettings: .default, isLightInterface: isLight
            )
            #expect(seeded.isEqual(to: first))
            Color.mimo.setTheme(.lightGlass)
            let afterThemeChange = MarkdownAttributedStringBuilder.build(
                text: text, fontSize: 14, textColor: .black,
                codeSettings: .default, isLightInterface: isLight
            )
            let hit = MarkdownAttributedStringBuilder.cachedBuild(
                text: text, fontSize: 14, textColor: .black,
                codeSettings: .default, isLightInterface: isLight
            )
            #expect(afterThemeChange.isEqual(to: first), "Explicit render profile owns every color")
            #expect(hit.isEqual(to: afterThemeChange), "Cache hits and direct rendering must stay identical")
        }
    }

    @Test("Фоновый prewarm использует явную тему независимо от глобального переключателя")
    func explicitPrewarmThemeIsStableAcrossGlobalThemeChanges() async {
        let originalTheme: AppTheme = Color.mimo.isLightTheme ? .lightGlass : .dark
        defer { Color.mimo.setTheme(originalTheme) }
        let text = "prewarm-snapshot-\(UUID().uuidString)\n\n" + sampleText + "\n\n---"
        Color.mimo.setTheme(.dark)
        let built = await Task.detached {
            MarkdownAttributedStringBuilder.prewarm(
                texts: [text], fontSize: 14, textColor: .black, projectRoot: nil,
                codeSettings: .default, isLightInterface: true, threshold: 1
            )
        }.value
        #expect(built == 1, "prewarm must build the explicit light profile even while the app theme is dark")
        Color.mimo.setTheme(.lightGlass)
        let direct = MarkdownAttributedStringBuilder.build(
            text: text, fontSize: 14, textColor: .black,
            codeSettings: .default, isLightInterface: true
        )
        // The shared cache may legitimately evict this entry while parallel
        // suites render, so compare the render result instead of requiring a
        // surviving cache slot. A hit and a rebuild must both equal `direct`.
        let cached = MarkdownAttributedStringBuilder.cachedBuild(
            text: text, fontSize: 14, textColor: .black,
            codeSettings: .default, isLightInterface: true
        )
        #expect(cached.isEqual(to: direct))
    }

    @Test("Разные темы/настройки не путают кэш")
    func cacheDistinguishesSettings() {
        let text = "theme-\(UUID().uuidString)\n\nТело сообщения."
        let light = MarkdownAttributedStringBuilder.cachedBuild(
            text: text, fontSize: 14, textColor: .black,
            codeSettings: .default, isLightInterface: true
        )
        let dark = MarkdownAttributedStringBuilder.cachedBuild(
            text: text, fontSize: 14, textColor: .black,
            codeSettings: .default, isLightInterface: false
        )
        #expect(light !== dark)
    }

    @Test("Смена темы приложения очищает кэш markdown")
    func appThemeSwitchClearsCaches() {
        // Regression 2026-11-13: rows kept black surfaces / white text after
        // Dark → Light because the attributed strings and heights stayed in
        // the cache and the row bodies were not invalidated.
        let state = AppState()
        let original = state.appTheme
        defer {
            state.appTheme = original
            MarkdownAttributedStringBuilder.clearCaches()
        }
        MarkdownAttributedStringBuilder.clearCaches()
        let text = "theme-switch-\(UUID().uuidString)\n\nТело сообщения."
        _ = MarkdownAttributedStringBuilder.cachedBuild(
            text: text, fontSize: 14, textColor: .black,
            codeSettings: .default, isLightInterface: true
        )
        let seeded = MarkdownAttributedStringBuilder.cachedAttributedString(
            text: text,
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: .default,
            isLightInterface: true
        )
        #expect(seeded != nil)

        state.appTheme = original == .dark ? .lightGlass : .dark

        // The cache is process-wide and other suites render in parallel, so
        // assert on this exact render key instead of the global entry count.
        let evicted = MarkdownAttributedStringBuilder.cachedAttributedString(
            text: text,
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: .default,
            isLightInterface: true
        )
        #expect(evicted == nil)
    }

    @Test("prewarm ровно с профилем рендера заполняет кэш")
    func prewarmSeedsExactProfile() {
        let text = "prewarm-\(UUID().uuidString)\n\n" + String(repeating: "строка\n", count: 40)
        let settings = CodeDisplaySettings(
            lightThemeName: "GitHub Light",
            darkThemeName: "GitHub Dark",
            fontSize: 12,
            showLineNumbers: true,
            wrapLongLines: true
        )
        MarkdownAttributedStringBuilder.prewarm(
            texts: [text],
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: settings,
            isLightInterface: true,
            threshold: 1
        )
        let seeded = MarkdownAttributedStringBuilder.cachedAttributedString(
            text: text,
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: settings,
            isLightInterface: true
        )
        #expect(seeded != nil)
    }

    @Test("prewarm с чужим профилем не выдаёт себя за готовую разметку")
    func prewarmDoesNotPoisonOtherProfiles() {
        let text = "profile-\(UUID().uuidString)\n\n" + String(repeating: "строка\n", count: 40)
        let settings = CodeDisplaySettings(
            lightThemeName: "GitHub Light",
            darkThemeName: "GitHub Dark",
            fontSize: 12,
            showLineNumbers: true,
            wrapLongLines: true
        )
        MarkdownAttributedStringBuilder.prewarm(
            texts: [text],
            fontSize: 17,
            textColor: .black,
            projectRoot: nil,
            codeSettings: settings,
            isLightInterface: true,
            threshold: 1
        )
        let atRenderSize = MarkdownAttributedStringBuilder.cachedAttributedString(
            text: text,
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: settings,
            isLightInterface: true
        )
        #expect(atRenderSize == nil)
    }

    @Test("prewarm получает ровно prose-сегменты, которые рендерит чат")
    func prewarmUsesRenderedProseSegments() {
        let first = "# Ответ\n\nПервый абзац."
        let code = "```swift\nlet x = 1\n```"
        let second = "Второй абзац после кода."
        let message = [first, code, second].joined(separator: "\n\n")

        let prose = MarkdownCodeSegmentLogic.proseTexts(from: message)
        #expect(prose == [first, second])

        let settings = CodeDisplaySettings.default
        MarkdownAttributedStringBuilder.prewarm(
            texts: prose,
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: settings,
            isLightInterface: true,
            threshold: 1
        )
        for renderedText in prose {
            let seeded = MarkdownAttributedStringBuilder.cachedAttributedString(
                text: renderedText,
                fontSize: 14,
                textColor: .black,
                projectRoot: nil,
                codeSettings: settings,
                isLightInterface: true
            )
            #expect(seeded != nil, "prose-сегмент должен быть предзагружен")
        }
        // Сырой текст с fences не рендерится ни одним text view.
        #expect(MarkdownAttributedStringBuilder.cachedAttributedString(
            text: message,
            fontSize: 14,
            textColor: .black,
            projectRoot: nil,
            codeSettings: settings,
            isLightInterface: true
        ) == nil)
    }

    @Test("Кэш высоты измеряет один раз на тот же профиль и ширину")
    func heightCacheMeasuresOnce() {
        let text = "height-\(UUID().uuidString)\n\n" + String(repeating: "абзац текста\n\n", count: 20)
        var measurements = 0
        func measure() -> CGFloat {
            measurements += 1
            return 123.5
        }

        let first = MarkdownAttributedStringBuilder.cachedMeasuredHeight(
            text: text, fontSize: 14, textColor: .black,
            projectRoot: nil, codeSettings: .default, isLightInterface: true,
            width: 720, measure: measure
        )
        let second = MarkdownAttributedStringBuilder.cachedMeasuredHeight(
            text: text, fontSize: 14, textColor: .black,
            projectRoot: nil, codeSettings: .default, isLightInterface: true,
            width: 720, measure: measure
        )
        #expect(first == 123.5)
        #expect(second == 123.5)
        #expect(measurements == 1, "одинаковая ширина должна давать hit")
    }

    @Test("Кэш высоты пересчитывает при реальной смене ширины")
    func heightCacheInvalidatesOnWidthChange() {
        let text = "height-width-\(UUID().uuidString)\n\n" + String(repeating: "абзац текста\n\n", count: 20)
        var measurements = 0
        func measure() -> CGFloat {
            measurements += 1
            return CGFloat(100 + measurements)
        }

        _ = MarkdownAttributedStringBuilder.cachedMeasuredHeight(
            text: text, fontSize: 14, textColor: .black,
            projectRoot: nil, codeSettings: .default, isLightInterface: true,
            width: 600, measure: measure
        )
        let second = MarkdownAttributedStringBuilder.cachedMeasuredHeight(
            text: text, fontSize: 14, textColor: .black,
            projectRoot: nil, codeSettings: .default, isLightInterface: true,
            width: 701, measure: measure
        )
        #expect(measurements == 2)
        #expect(second == 102)
    }

    @Test("Кэш разметки ограничен по числу записей")
    func cacheIsBounded() {
        for index in 0..<150 {
            _ = MarkdownAttributedStringBuilder.cachedBuild(
                text: "bounded-\(index)-\(UUID().uuidString)",
                fontSize: 14,
                textColor: .black,
                codeSettings: .default,
                isLightInterface: true
            )
        }
        #expect(MarkdownAttributedStringBuilder.statsSnapshot().cacheEntries <= 120)
    }

    @Test("Параллельные чтения и записи кэша не ломают результат")
    func cacheIsThreadSafe() async {
        let texts = (0..<24).map { "parallel-\($0)-\(UUID().uuidString)\n\nТело \($0)." }
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var ok = true
                    for text in texts {
                        let value = MarkdownAttributedStringBuilder.cachedBuild(
                            text: text,
                            fontSize: 14,
                            textColor: .black,
                            codeSettings: .default,
                            isLightInterface: true
                        )
                        ok = ok && value.length > 0
                    }
                    for text in texts {
                        _ = MarkdownAttributedStringBuilder.cachedMeasuredHeight(
                            text: text,
                            fontSize: 14,
                            textColor: .black,
                            projectRoot: nil,
                            codeSettings: .default,
                            isLightInterface: true,
                            width: 720
                        ) { CGFloat(40 + text.count) }
                    }
                    return ok
                }
            }
            for await ok in group {
                #expect(ok)
            }
        }
        #expect(MarkdownAttributedStringBuilder.statsSnapshot().cacheEntries <= 120)
    }

    @Test("MessageStore ставит в prewarm только prose и профиль панели")
    func storePrewarmsProseWithPanelProfile() throws {
        let store = try RepoRoot.sourceText("myCoder/Sources/Services/MessageStore.swift")
        #expect(store.contains("MarkdownMediaSegmentLogic.proseTexts"))
        #expect(store.contains("markdownPrewarmFontSize"))
        #expect(store.contains("markdownPrewarmIsLightInterface"))
        #expect(store.contains("markdownPrewarmTask?.cancel()"))

        let panel = try RepoRoot.chatPanelSourceText
        #expect(panel.contains("prepareMarkdownPrewarmProfile()"))
        #expect(panel.contains("InterfaceTypography.scaled("))
        #expect(panel.contains("CodeDisplaySettings(settings: appState.settings)"))
    }

    @Test("API отдаёт счётчики кэша для живого замера")
    func apiExposesCacheStats() throws {
        let server = try RepoRoot.apiServerSourceText
        #expect(server.contains("/api/markdown-perf"))
        #expect(server.contains("statsSnapshot().dictionary"))
    }
}
