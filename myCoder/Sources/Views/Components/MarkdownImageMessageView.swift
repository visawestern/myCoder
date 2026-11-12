import SwiftUI
import AppKit

/// Рендерит инлайн-картинку markdown `![alt](source)` как тапабельный
/// превью с действиями: превью-лист, «Показать в Finder», «Копировать»
/// (запрос 2026-11-13). Ненайденный файл показывается как пометка с alt,
/// чтобы намерение модели не терялось молча.
struct MarkdownImageMessageView: View {
    let source: String
    let alt: String
    var projectRoot: String? = nil
    var maxWidth: CGFloat = 260
    var maxHeight: CGFloat = 200

    @State private var showPreview = false
    @State private var copied = false

    private var resolvedPath: String? {
        MarkdownLinkLogic.resolveFile(source, projectRoot: projectRoot)
    }

    private var nsImage: NSImage? {
        guard let path = resolvedPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var fallbackTitle: String {
        guard let path = resolvedPath else { return alt }
        return alt.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : alt
    }

    var body: some View {
        Group {
            if let image = nsImage, let path = resolvedPath {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        showPreview = true
                    } label: {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.mimo.border.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t(AppLocalizationKey.locViewImage))

                    HStack(spacing: 12) {
                        actionButton(icon: "eye", title: L.t(AppLocalizationKey.locImagePreview)) {
                            showPreview = true
                        }
                        actionButton(icon: "folder", title: L.t(AppLocalizationKey.locShowInFinder)) {
                            ChatFileOpenLogic.revealInFinder(fileURL: URL(fileURLWithPath: path))
                        }
                        actionButton(
                            icon: copied ? "checkmark" : "doc.on.doc",
                            title: L.t(copied ? AppLocalizationKey.locCopied : AppLocalizationKey.locCopy)
                        ) {
                            copy(path: path, image: image)
                        }
                    }
                }
                .sheet(isPresented: $showPreview) {
                    MarkdownImagePreviewSheet(path: path, title: fallbackTitle)
                }
            } else if !alt.isEmpty {
                Text("[картинка: \(alt)]")
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .interfaceFont(size: 11)
                Text(title)
                    .interfaceFont(size: 11)
            }
            .foregroundColor(Color.mimo.textSecondary)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func copy(path: String, image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { copied = false }
        }
    }
}

/// Превью картинки из файла (аналог `SentImagePreviewSheet` для markdown).
struct MarkdownImagePreviewSheet: View {
    let path: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Text(title)
                    .interfaceFont(size: 14, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .interfaceFont(size: 18)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 720)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                } else {
                    Text(L.t(AppLocalizationKey.locCannotPreviewImage))
                        .foregroundColor(Color.mimo.textMuted)
                }
            }

            Button {
                dismiss()
            } label: {
                Text(L.t(AppLocalizationKey.locClose))
                    .interfaceFont(size: 12, weight: .medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.mimo.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(HandCursorButtonStyle())
            .padding(.bottom, 16)
        }
        .frame(width: 760, height: 620)
        .background(Color.mimo.background)
    }
}
