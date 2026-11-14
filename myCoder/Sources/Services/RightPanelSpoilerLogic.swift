import Foundation

/// Секции правой панели, которые пользователь может свернуть.
///
/// Порядок `allCases` — это порядок секций сверху вниз в панели, поэтому он же
/// используется как порядок отрисовки.
///
/// Значения `rawValue` — стабильные идентификаторы: они попадают в
/// `UserDefaults`, поэтому переименование сломает уже сохранённое состояние
/// пользователя. Добавлять новые секции можно только в конец.
enum RightPanelSection: String, CaseIterable, Hashable {
    /// Инструменты git: изменения, ветка, коммит, публикация.
    case git
    /// Живая картинка встроенного браузера (хромкаст).
    case chromecast
    /// Список запущенных субагентов.
    case subagents
    /// Фоновые команды терминала текущего чата.
    case terminal
    /// План (чеклист шагов) текущего чата.
    case plan
    /// Цели (ЦЕЛЬ) текущего чата.
    case goal
}

/// Чистая логика свёрнутости секций правой панели.
///
/// Единица хранения — чат: у каждого чата свой набор свёрнутых секций, поэтому,
/// вернувшись в чат, пользователь видит ровно ту раскладку, которую оставил.
/// Логика не знает ни о SwiftUI, ни о `UserDefaults`: она только считает ключи,
/// разбирает и сериализует наборы, поэтому её можно переносить и тестировать
/// отдельно от интерфейса.
///
/// Входы: идентификатор чата и текущий набор свёрнутых секций.
/// Выходы: ключ хранения, строковое представление набора, новый набор.
/// Зависимости: только `Foundation` (`Set`).
enum RightPanelSpoilerLogic {

    /// Префикс ключей в `UserDefaults`; за ним идёт идентификатор чата.
    static let storagePrefix = "com.mycoder.rightPanel.collapsed."

    /// Идентификатор области для состояния вне чата (панель открыта, но чат
    /// не выбран). Отдельное значение, чтобы не смешиваться с реальным
    /// идентификатором чата.
    static let anonymousScope = "no-chat"

    /// Секции, свёрнутые в чате, который ещё ничего не запомнил.
    ///
    /// Хромкаст — живая картинка: она дороже остальных секций по месту и по
    /// обновлениям, поэтому в новом чате панель остаётся компактной, пока
    /// пользователь сам не раскроет картинку. Список намеренно маленький:
    /// всё, чего здесь нет, стартует развёрнутым.
    static let defaultCollapsed: Set<RightPanelSection> = [.chromecast]

    /// Ключ хранения набора свёрнутых секций для чата.
    ///
    /// - Parameter chatID: идентификатор открытого чата или `nil`.
    /// - Returns: ключ `UserDefaults`, уникальный для чата.
    /// - Note: пустой идентификатор трактуется как обычный чат с пустым
    ///   именем и не совпадает с `anonymousScope`.
    static func scopeKey(chatID: String?) -> String {
        let scope = chatID ?? anonymousScope
        return storagePrefix + scope
    }

    /// Свёрнута ли секция в данном наборе.
    ///
    /// - Parameters:
    ///   - section: проверяемая секция.
    ///   - collapsed: набор свёрнутых секций чата.
    /// - Returns: `true`, если секция свёрнута.
    static func isCollapsed(_ section: RightPanelSection, in collapsed: Set<RightPanelSection>) -> Bool {
        collapsed.contains(section)
    }

    /// Новый набор после клика по заголовку секции.
    ///
    /// - Parameters:
    ///   - section: секция, которую пользователь свернул или развернул.
    ///   - collapsed: текущий набор свёрнутых секций.
    /// - Returns: набор с инвертированным состоянием этой секции; остальные
    ///   секции не меняются.
    static func toggled(
        _ section: RightPanelSection,
        in collapsed: Set<RightPanelSection>
    ) -> Set<RightPanelSection> {
        var result = collapsed
        if result.contains(section) {
            result.remove(section)
        } else {
            result.insert(section)
        }
        return result
    }

    /// Строка для `UserDefaults`: идентификаторы через запятую.
    ///
    /// - Parameter collapsed: набор свёрнутых секций.
    /// - Returns: стабильная строка; порядок задаётся `allCases`, поэтому один
    ///   и тот же набор всегда даёт одну и ту же строку.
    static func encode(_ collapsed: Set<RightPanelSection>) -> String {
        RightPanelSection.allCases
            .filter { collapsed.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    /// Разбор сохранённой строки.
    ///
    /// - Parameter raw: значение из `UserDefaults`; может быть `nil`, пустым
    ///   или содержать мусор от старой версии.
    /// - Returns: набор известных секций; неизвестные токены и пустые элементы
    ///   игнорируются, поэтому испорченное значение не ломает панель.
    static func decode(_ raw: String?) -> Set<RightPanelSection> {
        guard let raw else { return [] }
        let tokens = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(tokens.compactMap(RightPanelSection.init(rawValue:)))
    }
}
