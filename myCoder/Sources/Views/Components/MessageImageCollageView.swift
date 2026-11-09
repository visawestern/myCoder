import SwiftUI

/// Коллаж картинок одного сообщения (C5).
///
/// Одна картинка остаётся обычным предпросмотром, две рисуются парой, три и
/// больше — большая картинка слева + колонка миниатюр справа. Лишние
/// миниатюры сворачиваются в счётчик `+N` на последней плитке, поэтому
/// сообщение с семью вложениями больше не растягивается на семь экранов.
struct MessageImageCollageView: View {
    let images: [ClipboardImage]

    /// Размер большой картинки. Высота совпадает с колонкой из трёх
    /// миниатюр (3×64 + 2×6 = 204), чтобы коллаж был ровным прямоугольником.
    private let featuredSize = CGSize(width: 210, height: 204)
    /// Размер одной миниатюры боковой колонки.
    private let sideSize = CGSize(width: 64, height: 64)
    /// Размер картинки в паре.
    private let pairSize = CGSize(width: 150, height: 120)

    private var layout: MessageImageCollageLayout {
        MessageImageCollageLogic.layout(imageCount: images.count)
    }

    var body: some View {
        switch layout {
        case .empty:
            EmptyView()
        case .single:
            TappableChatImage(image: images[0])
        case .pair:
            HStack(spacing: 6) {
                TappableChatImage(image: images[0], fixedSize: pairSize)
                TappableChatImage(image: images[1], fixedSize: pairSize)
            }
        case .featured(let sideCount, let hiddenCount):
            HStack(alignment: .top, spacing: 6) {
                featuredTile(hiddenCount: sideCount == 0 ? hiddenCount : 0)
                if sideCount > 0 {
                    VStack(spacing: 6) {
                        ForEach(0..<sideCount, id: \.self) { index in
                            sideTile(
                                image: images[index + 1],
                                hiddenCount: index == sideCount - 1 ? hiddenCount : 0
                            )
                        }
                    }
                }
            }
        }
    }

    /// Большая картинка коллажа.
    ///
    /// Вход: `hiddenCount` — сколько картинок свернуть в счётчик поверх
    /// большой (используется только когда боковая колонка отключена).
    /// Выход: плитка с картинкой и, при необходимости, затемнением `+N`.
    /// Зависимости: `TappableChatImage`.
    @ViewBuilder
    private func featuredTile(hiddenCount: Int) -> some View {
        ZStack {
            TappableChatImage(image: images[0], fixedSize: featuredSize)
            if hiddenCount > 0 {
                overflowBadge(count: hiddenCount, size: featuredSize, cornerRadius: 8)
            }
        }
    }

    /// Миниатюра боковой колонки.
    ///
    /// Вход: `image` — картинка; `hiddenCount` — сколько вложений скрыто
    /// (рисуется затемнением `+N` поверх последней миниатюры).
    /// Выход: плитка миниатюры.
    /// Зависимости: `TappableChatImage`.
    @ViewBuilder
    private func sideTile(image: ClipboardImage, hiddenCount: Int) -> some View {
        ZStack {
            TappableChatImage(image: image, fixedSize: sideSize)
            if hiddenCount > 0 {
                overflowBadge(count: hiddenCount, size: sideSize, cornerRadius: 8)
            }
        }
    }

    /// Затемнение со счётчиком скрытых картинок.
    ///
    /// Вход: `count` — число скрытых; `size` — размер плитки; `cornerRadius`.
    /// Выход: полупрозрачный слой `+N`, не перехватывающий клик (клик
    /// открывает последнюю видимую картинку).
    /// Зависимости: `Color.mimo`.
    private func overflowBadge(
        count: Int,
        size: CGSize,
        cornerRadius: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.6))
                .frame(width: size.width, height: size.height)
            Text("+\(count)")
                .interfaceFont(size: min(20, max(12, size.height / 4)), weight: .semibold)
                .foregroundColor(.white)
        }
        .allowsHitTesting(false)
    }
}
