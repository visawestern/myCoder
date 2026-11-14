import SwiftUI

/// Состояние свёрнутости, которое панель передаёт каждой секции.
///
/// Секция не знает, где хранится состояние: она только спрашивает
/// «я свёрнута?» и сообщает о клике. Благодаря этому любую секцию можно
/// отрисовать отдельно (в превью, тесте или другом окне) — достаточно передать
/// `nil`, и она будет всегда развёрнута.
///
/// Входы: текущий набор свёрнутых секций и обработчик переключения.
/// Выходы: ответ «свёрнута ли секция» и вызов переключения.
/// Зависимости: `RightPanelSection`.
struct RightPanelSpoilerBinding {
    /// Свёрнутые секции текущего чата.
    private let collapsed: Set<RightPanelSection>
    /// Переключение секции; вызывается по клику на заголовок.
    private let onToggle: (RightPanelSection) -> Void

    /// - Parameters:
    ///   - collapsed: набор свёрнутых секций.
    ///   - onToggle: обработчик переключения секции.
    init(collapsed: Set<RightPanelSection>, onToggle: @escaping (RightPanelSection) -> Void) {
        self.collapsed = collapsed
        self.onToggle = onToggle
    }

    /// Свёрнута ли секция.
    ///
    /// - Parameter section: проверяемая секция.
    /// - Returns: `true`, если содержимое нужно скрыть.
    func isCollapsed(_ section: RightPanelSection) -> Bool {
        RightPanelSpoilerLogic.isCollapsed(section, in: collapsed)
    }

    /// Сообщить о клике по заголовку секции.
    ///
    /// - Parameter section: секция, которую нужно свернуть или развернуть.
    func toggle(_ section: RightPanelSection) {
        onToggle(section)
    }
}
