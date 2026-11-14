import SwiftUI

/// Заголовок-спойлер секции правой панели.
///
/// Рисует кликабельную строку «шеврон + иконка + название + счётчик» и
/// отдельный слот справа под кнопки самой секции (обновить, добавить,
/// развернуть в окно). Кнопки-аксессуары не входят в кнопку-заголовок,
/// поэтому клик по ним не сворачивает секцию.
///
/// Входы: секция (для доступности), название, иконка, цвет, состояние
/// свёрнутости, счётчик, размер шрифта, обработчик клика и аксессуары.
/// Выходы: строка заголовка; содержимое секции компонент не рисует.
/// Зависимости: только SwiftUI; состояние и хранение приходят снаружи.
struct RightPanelSpoilerHeader<Accessories: View>: View {
    /// Секция, которой принадлежит заголовок (для accessibility id).
    let section: RightPanelSection
    /// Локализованное название секции.
    let title: String
    /// SF Symbol секции.
    let icon: String
    /// Цвет иконки.
    let tint: Color
    /// Свёрнуто ли содержимое прямо сейчас.
    let isCollapsed: Bool
    /// Счётчик элементов; `nil` — счётчик не показывается.
    let count: Int?
    /// Размер шрифта названия (крупный для «главных» секций).
    let titleSize: CGFloat
    /// Клик по заголовку.
    let onToggle: () -> Void
    /// Кнопки секции, остающиеся видимыми в свёрнутом состоянии.
    let accessories: () -> Accessories

    /// Единый инициализатор с аксессуарами.
    ///
    /// - Parameters:
    ///   - section: секция панели.
    ///   - title: локализованное название.
    ///   - icon: SF Symbol.
    ///   - tint: цвет иконки.
    ///   - isCollapsed: свёрнуто ли содержимое.
    ///   - count: счётчик элементов или `nil`.
    ///   - titleSize: размер шрифта названия.
    ///   - onToggle: обработчик клика по заголовку.
    ///   - accessories: кнопки секции.
    init(
        section: RightPanelSection,
        title: String,
        icon: String,
        tint: Color,
        isCollapsed: Bool,
        count: Int? = nil,
        titleSize: CGFloat = 14,
        onToggle: @escaping () -> Void,
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.section = section
        self.title = title
        self.icon = icon
        self.tint = tint
        self.isCollapsed = isCollapsed
        self.count = count
        self.titleSize = titleSize
        self.onToggle = onToggle
        self.accessories = accessories
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .interfaceFont(size: 9, weight: .semibold)
                        .foregroundColor(Color.mimo.textMuted)
                        .frame(width: 9)
                    Image(systemName: icon)
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(tint)
                    Text(title)
                        .interfaceFont(size: titleSize, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                        .lineLimit(1)
                    if let count, count > 0 {
                        Text("\(count)")
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(isCollapsed ? L.t(AppLocalizationKey.locPanelExpandSection)
                              : L.t(AppLocalizationKey.locPanelCollapseSection))
            .accessibilityLabel(title)
            .accessibilityIdentifier("rightPanelSpoiler.\(section.rawValue)")

            Spacer(minLength: 0)
            accessories()
        }
    }
}

extension RightPanelSpoilerHeader where Accessories == EmptyView {
    /// Заголовок без аксессуаров: у секции нет своих кнопок.
    ///
    /// - Parameters: те же, что у основного инициализатора, без `accessories`.
    init(
        section: RightPanelSection,
        title: String,
        icon: String,
        tint: Color,
        isCollapsed: Bool,
        count: Int? = nil,
        titleSize: CGFloat = 14,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            section: section,
            title: title,
            icon: icon,
            tint: tint,
            isCollapsed: isCollapsed,
            count: count,
            titleSize: titleSize,
            onToggle: onToggle,
            accessories: { EmptyView() }
        )
    }
}

/// Обёртка содержимого спойлера: скрывает содержимое, когда секция свёрнута.
///
/// Входы: флаг свёрнутости и содержимое.
/// Выходы: содержимое либо пустое представление.
/// Зависимости: только SwiftUI.
struct RightPanelSpoilerBody<Content: View>: View {
    /// Свёрнута ли секция.
    let isCollapsed: Bool
    /// Содержимое секции.
    let content: () -> Content

    /// - Parameters:
    ///   - isCollapsed: свёрнута ли секция.
    ///   - content: содержимое, которое рисуется только в развёрнутом виде.
    init(isCollapsed: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isCollapsed = isCollapsed
        self.content = content
    }

    var body: some View {
        if !isCollapsed {
            content()
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
