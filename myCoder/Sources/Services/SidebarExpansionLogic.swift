import Foundation

enum SidebarExpansionLogic {
    /// Clicking the current row toggles; selecting a different row always
    /// expands so the user can immediately see its sessions.
    static func nextState(isAlreadySelected: Bool, isExpanded: Bool) -> Bool {
        isAlreadySelected ? !isExpanded : true
    }

    /// Переключение на чат в другом проекте раскрывает этот проект, но НЕ
    /// схлопывает остальные: раскрытие — пользовательское состояние, а не
    /// «аккордеон с одним открытым». Иначе при каждом переходе между
    /// проектами предыдущий список чатов исчезал.
    static func stateAfterSelection(workspaceID: String,
                                    selectedID: String?,
                                    isExpanded: Bool) -> Bool {
        workspaceID == selectedID ? true : isExpanded
    }
}
