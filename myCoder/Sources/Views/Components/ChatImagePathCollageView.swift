import SwiftUI
import AppKit

/// Inline image previews for image paths found in a message's text (plan item
/// 13.1). Shows small, size-bounded thumbnails under the message; a left click
/// opens the full image in a sheet, a right click offers a menu: copy the
/// image, copy its path, reveal in Finder, or open with the default app.
///
/// Input: resolved absolute image paths.
/// Output: thumbnail grid (bounded size, not full-chat).
/// Dependencies: `ChatThumbnailCache` (off-main load/scale), `ChatFileOpenLogic`,
/// `NSPasteboard`.
struct ChatImagePathCollageView: View {
    let paths: [String]

    /// Bounded thumbnail side (points) so previews never fill the chat width.
    static let thumbnailSide: CGFloat = 150
    static let maxCollageWidth: CGFloat = 330

    @State private var previewItem: PreviewItem?

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Self.thumbnailSide, maximum: Self.thumbnailSide), spacing: 8)],
            spacing: 8
        ) {
            ForEach(paths, id: \.self) { path in
                ThumbnailCell(path: path, side: Self.thumbnailSide) { path in
                    previewItem = PreviewItem(path: path)
                }
            }
        }
        .frame(maxWidth: Self.maxCollageWidth, alignment: .leading)
        .sheet(item: $previewItem) { item in
            InlineImagePreviewSheet(path: item.path)
        }
    }
}

/// One thumbnail tile: loads and scales the image through the shared off-main
/// store, shows a placeholder until ready, and reacts to left/right clicks.
///
/// Input: an absolute image path, the maximum side, and a preview callback.
/// Output: the tile view (placeholder / image with actions).
/// Dependencies: `ChatThumbnailCache`, `HandCursorButtonStyle`, `L` (i18n).
private struct ThumbnailCell: View {
    let path: String
    let side: CGFloat
    let onPreview: (String) -> Void

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                tile(image)
            } else if failed {
                placeholder(symbol: "exclamationmark.triangle")
            } else {
                ProgressView()
                    .frame(width: side, height: side)
            }
        }
        .task(id: path) {
            guard image == nil, !failed else { return }
            let loaded = await ChatThumbnailCache.shared.thumbnail(for: path, side: side)
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
    }

    private func tile(_ image: NSImage) -> some View {
        Button {
            onPreview(path)
        } label: {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mimo.border.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(HandCursorButtonStyle())
        .contextMenu { contextMenuItems(image: image) }
    }

    @ViewBuilder
    private func placeholder(symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.mimo.subtleFill)
            .frame(width: side, height: side)
            .overlay(Image(systemName: symbol).foregroundColor(Color.mimo.textMuted))
    }

    /// Right-click menu: copy image, copy path, reveal in Finder, open with
    /// the default application.
    @ViewBuilder
    private func contextMenuItems(image: NSImage) -> some View {
        Button {
            copyImage(image)
        } label: {
            Label(L.t("Скопировать картинку"), systemImage: "doc.on.doc")
        }
        Button {
            copyPath(path)
        } label: {
            Label(L.t("Скопировать путь"), systemImage: "link")
        }
        Divider()
        Button {
            ChatFileOpenLogic.revealInFinder(fileURL: URL(fileURLWithPath: path))
        } label: {
            Label(L.t("Открыть в Finder"), systemImage: "folder")
        }
        Button {
            ChatFileOpenLogic.open(fileURL: URL(fileURLWithPath: path), applicationURL: nil)
        } label: {
            Label(L.t("Открыть с помощью…"), systemImage: "arrow.right.circle")
        }
    }

    private func copyImage(_ image: NSImage) {
        guard let data = image.pngData() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    private func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}

/// Full-image preview sheet for an inline thumbnail click.
struct InlineImagePreviewSheet: View {
    let path: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 720, maxHeight: 640)
            } else {
                Text(L.t("Не удалось открыть картинку"))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.error)
            }
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textSecondary)
            Button(L.t("Закрыть")) { dismiss() }
                .buttonStyle(HandCursorButtonStyle())
                .foregroundColor(Color.mimo.brand)
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 300)
    }
}

extension NSImage {
    /// Best-effort PNG representation for clipboard copy.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation else { return nil }
        let rep = NSBitmapImageRep(data: tiff)
        return rep?.representation(using: .png, properties: [:])
    }
}

/// Sheet identity for one inline preview item.
private struct PreviewItem: Identifiable {
    let id = UUID()
    let path: String
}
