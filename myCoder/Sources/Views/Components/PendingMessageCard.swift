import SwiftUI
import AppKit

// MARK: - Pending Message Card

struct PendingMessageCard: View {
    let queued: QueuedMessage
    let index: Int
    let onForceSend: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Agent mode icon
            Image(systemName: queued.type.icon)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.brand)
                .frame(width: 14)
            
            // Text preview
            Text(queued.text)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Attachments preview (images + files)
            if !queued.images.isEmpty || !queued.files.isEmpty {
                HStack(spacing: 2) {
                    // Image thumbnails (max 3)
                    ForEach(queued.images.prefix(3), id: \.base64) { img in
                        if let data = Data(base64Encoded: img.base64),
                           let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .frame(width: 18, height: 18)
                                .cornerRadius(3)
                        }
                    }
                    // File icons (max 2)
                    ForEach(queued.files.prefix(2)) { file in
                        HStack(spacing: 2) {
                            Image(systemName: "doc.text")
                                .interfaceFont(size: 9)
                            Text(file.name)
                                .interfaceFont(size: 9)
                                .lineLimit(1)
                        }
                        .foregroundColor(Color.mimo.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.mimo.textMuted.opacity(0.1))
                        .cornerRadius(3)
                    }
                    
                    // Overflow count
                    let imageCount = min(queued.images.count, 3)
                    let fileCount = min(queued.files.count, 2)
                    let shown = imageCount + fileCount
                    let total = queued.images.count + queued.files.count
                    if total > shown {
                        Text("+\(total - shown)")
                            .interfaceFont(size: 9, weight: .medium)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                }
            }
            
            // Queue position
            Text("#\(index + 1)")
                .interfaceFont(size: 10, weight: .medium)
                .foregroundColor(Color.mimo.textMuted)
            
            // Force-send now (interrupts the current turn).
            Button(action: onForceSend) {
                Image(systemName: "paperplane.fill")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locSendNow))

            // Edit the queued message in the composer (draft is preserved).
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locEditQueuedMessage))

            // Cancel/remove this queued message.
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locDeleteQueuedMessage))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.mimo.brand.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

