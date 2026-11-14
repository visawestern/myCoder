import Foundation

/// Хранилище состояния свёрнутости секций правой панели.
///
/// Каждый чат хранит свой набор свёрнутых секций в `UserDefaults`, поэтому
/// переключение чатов возвращает ровно ту раскладку, которую пользователь
/// оставил. Чтение идёт из `UserDefaults` при каждом обращении — это дёшево и
/// исключает рассинхронизацию между окнами.
///
/// Входы: идентификатор чата и операция над секцией.
/// Выходы: текущий набор свёрнутых секций.
/// Зависимости: `RightPanelSpoilerLogic` (ключи и сериализация), `UserDefaults`.
@MainActor
final class RightPanelSpoilerStore: ObservableObject {

    /// Уведомление об изменении состояния; объект уведомления — сам store.
    static let didChangeNotification = Notification.Name("myCoderRightPanelSpoilerChanged")

    /// Счётчик изменений. SwiftUI не умеет наблюдать `UserDefaults` напрямую,
    /// поэтому каждая запись увеличивает это опубликованное значение и
    /// перерисовывает панель.
    @Published private(set) var revision = 0

    private let defaults: UserDefaults

    /// - Parameter defaults: хранилище настроек; в тестах подменяется
    ///   изолированным suite, в приложении используется `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Текущий набор свёрнутых секций чата.
    ///
    /// - Parameter chatID: идентификатор чата или `nil`, если чат не выбран.
    /// - Returns: набор свёрнутых секций. Чат, который ещё ничего не запомнил,
    ///   получает `RightPanelSpoilerLogic.defaultCollapsed`; пустой набор
    ///   означает «всё развёрнуто» и хранится как пустая строка.
    func collapsed(in chatID: String?) -> Set<RightPanelSection> {
        let key = RightPanelSpoilerLogic.scopeKey(chatID: chatID)
        guard let raw = defaults.string(forKey: key) else {
            return RightPanelSpoilerLogic.defaultCollapsed
        }
        return RightPanelSpoilerLogic.decode(raw)
    }

    /// Свернуть или развернуть секцию чата и сохранить результат.
    ///
    /// - Parameters:
    ///   - section: секция, по заголовку которой кликнули.
    ///   - chatID: чат, которому принадлежит состояние.
    /// - Side effects: пишет в `UserDefaults` и рассылает
    ///   `didChangeNotification`.
    func toggle(_ section: RightPanelSection, in chatID: String?) {
        let updated = RightPanelSpoilerLogic.toggled(section, in: collapsed(in: chatID))
        write(updated, for: chatID)
    }

    /// Свернуть или развернуть секцию явным значением.
    ///
    /// Нужен там, где состояние меняется не кликом, а программно (например,
    /// «свернуть все» в меню панели).
    ///
    /// - Parameters:
    ///   - collapsed: целевое состояние секции.
    ///   - section: изменяемая секция.
    ///   - chatID: чат, которому принадлежит состояние.
    func setCollapsed(_ collapsed: Bool, for section: RightPanelSection, in chatID: String?) {
        var updated = self.collapsed(in: chatID)
        if collapsed {
            updated.insert(section)
        } else {
            updated.remove(section)
        }
        write(updated, for: chatID)
    }

    /// Очистить сохранённое состояние одного чата.
    ///
    /// - Parameter chatID: чат, состояние которого нужно забыть; `nil` —
    ///   состояние вне чата.
    func reset(chatID: String?) {
        defaults.removeObject(forKey: RightPanelSpoilerLogic.scopeKey(chatID: chatID))
        revision += 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Private

    /// Записать набор в `UserDefaults` и уведомить подписчиков.
    ///
    /// - Parameters:
    ///   - collapsed: новый набор свёрнутых секций.
    ///   - chatID: чат, которому принадлежит набор.
    /// - Side effects: запись в `UserDefaults`, рассылка уведомления.
    private func write(_ collapsed: Set<RightPanelSection>, for chatID: String?) {
        defaults.set(
            RightPanelSpoilerLogic.encode(collapsed),
            forKey: RightPanelSpoilerLogic.scopeKey(chatID: chatID)
        )
        revision += 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
