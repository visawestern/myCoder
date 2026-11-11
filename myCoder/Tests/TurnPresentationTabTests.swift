import Foundation
import Testing
@testable import myCoder

/// User directive 2026-11-03 (п.1): the compiled context is shown as separate
/// tabs — system instruction, request, plan, memory, skills, graph, files,
/// gaps. The tab order must match the assembly order the model receives, so a
/// reader never has to guess where a section came from.
@MainActor
@Suite("Вкладки просмотра собранного контекста")
struct TurnPresentationTabTests {

    /// Same shape the viewer receives: `CompiledContextPack.auditText` — the
    /// system instruction followed by the wire text (which already starts with
    /// the request section).
    private func fullPayload() -> String {
        let system = "Ты агент. Инструменты: read_file, write_file."
        let context = """
        ## Запрос
        удали запись кадров в файлы

        ## План запроса
        источник: внутренняя модель; намерение: refactor

        ## Память проекта
        - [решение] кадры хранятся в памяти

        ## Инструкции проекта (AGENTS.md)
        Use TDD.

        ## Скилл: swift
        Swift concurrency review

        ## Граф кода
        - func save — FrameStore.swift:1-3
          ← calls chooseFolder — SettingsView.swift:10

        ## Вопросы харнесса о зависимостях
        Связи и их судьба:
          - chooseFolder — SettingsView.swift:10: обновить / удалить / оставить

        ## FrameStore.swift
        ### FrameStore.swift:1-3 (save)
        func save() {}

        ## Пробелы
        - граф кода недоступен: нет индекса
        """
        return "## Системная инструкция\n\(system)\n\n\(context)"
    }

    @Test("Системная инструкция — первая вкладка")
    func systemInstructionIsFirstTab() {
        let tabs = TurnPresentation.sections(fullPayload())
        #expect(tabs.first?.title == "Системная инструкция")
    }

    @Test("Порядок вкладок совпадает с порядком сборки")
    func tabOrderMatchesAssembly() {
        let titles = TurnPresentation.sections(fullPayload()).map(\.title)
        let expected = [
            "Системная инструкция",
            "Запрос",
            "План запроса",
            "Память проекта",
            "Инструкции проекта (AGENTS.md)",
            "Скилл: swift",
            "Граф кода",
            "Вопросы харнесса о зависимостях",
            "FrameStore.swift",
            "Пробелы"
        ]
        #expect(titles == expected)
    }

    @Test("Пустых вкладок нет")
    func noEmptyTabs() {
        for tab in TurnPresentation.sections(fullPayload()) {
            #expect(!tab.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test("Заголовок без тела не превращается в пустую вкладку")
    func headerWithoutBodyIsDropped() {
        let text = "## Запрос\nсделай\n\n## Пустая\n\n## Хвост\nконец"
        let titles = TurnPresentation.sections(text).map(\.title)
        #expect(titles == ["Запрос", "Хвост"])
    }

    @Test("Текст без заголовков остаётся одной вкладкой")
    func plainTextIsOneTab() {
        let tabs = TurnPresentation.sections("просто текст без разметки")
        #expect(tabs.count == 1)
        #expect(tabs[0].title == "Контекст")
        #expect(tabs[0].body == "просто текст без разметки")
    }

    @Test("Пустой текст не даёт вкладок")
    func emptyTextHasNoTabs() {
        #expect(TurnPresentation.sections("").isEmpty)
    }
}
