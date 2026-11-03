import Testing
@testable import myCoder

struct ContextInspectionTabsTests {
    @Test func groupsFilesAndSkillsWhilePreservingEveryBody() {
        let text = "## Системная инструкция\nsystem\n\n## A.swift\nalpha\n\n## B.swift — зависимость\nbeta\n\n## Скилл: swift\nconcurrency\n\n## Скилл: sql\ntransactions\n\n## Запрос\nrequest"
        let tabs = TurnPresentation.inspectionTabs(text)
        #expect(tabs.map(\.title) == ["Инструкции", "Навыки", "Файлы", "Запрос"])
        #expect(tabs.first?.body.contains("system") == true)
        #expect(tabs.first { $0.title == "Файлы" }?.body.contains("alpha") == true)
        #expect(tabs.first { $0.title == "Файлы" }?.body.contains("beta") == true)
        #expect(tabs.first { $0.title == "Навыки" }?.body.contains("transactions") == true)
    }
}
