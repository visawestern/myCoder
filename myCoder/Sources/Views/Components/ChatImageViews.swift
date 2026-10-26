import SwiftUI
import AppKit

struct TappableChatImage: View {
    let image: ClipboardImage
    var maxWidth: CGFloat = 300
    var maxHeight: CGFloat = 200
    var fillThumbnail: Bool = false
    var thumbnailSize: CGFloat = 80

    @State private var previewImage: ClipboardImage?

    var body: some View {
        Group {
            if let data = Data(base64Encoded: image.base64),
               let nsImage = NSImage(data: data) {
                Button {
                    previewImage = image
                } label: {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: fillThumbnail ? thumbnailSize : nil,
                            height: fillThumbnail ? thumbnailSize : nil
                        )
                        .frame(maxWidth: fillThumbnail ? thumbnailSize : maxWidth, maxHeight: fillThumbnail ? thumbnailSize : maxHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mimo.border.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locViewImage))
            }
        }
        .sheet(item: $previewImage) { img in
            SentImagePreviewSheet(image: img)
        }
    }
}

struct SentImagePreviewSheet: View {
    let image: ClipboardImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let data = Data(base64Encoded: image.base64),
           let nsImage = NSImage(data: data) {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Text(L.t(AppLocalizationKey.locImagePreview))
                        .interfaceFont(size: 14, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .interfaceFont(size: 18)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ScrollView {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 720)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                }

                Button(action: { dismiss() }) {
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
        } else {
            VStack(spacing: 12) {
                Text(L.t(AppLocalizationKey.locCannotPreviewImage))
                    .foregroundColor(Color.mimo.textMuted)
                Button(L.t(AppLocalizationKey.locClose)) { dismiss() }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.brand)
            }
            .frame(width: 300, height: 200)
            .background(Color.mimo.background)
        }
    }
}

struct ComposerAttachmentPreview: View {
    @ObservedObject var store: MessageAttachmentStore

    private var hasAttachments: Bool {
        !store.attachedImages.isEmpty || !store.attachedFiles.isEmpty
    }

    var body: some View {
        if hasAttachments || store.lastImportError != nil {
            VStack(spacing: 0) {
                ImagePreviewStrip(attachedImages: store.imagesBinding)
                AttachedFilesStrip(attachedFiles: store.filesBinding)
                AttachmentImportErrorBanner(store: store)
            }
        }
    }
}
