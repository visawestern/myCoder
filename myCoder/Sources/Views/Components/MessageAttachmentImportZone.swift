import SwiftUI
import UniformTypeIdentifiers

struct MessageAttachmentImportZone: ViewModifier {
    @ObservedObject var store: MessageAttachmentStore
    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.mimo.brand, lineWidth: 2)
                        .background(Color.mimo.brand.opacity(0.06))
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: FileDropLogic.swiftUIUTTypes, isTargeted: $isDropTargeted) { providers in
                guard !providers.isEmpty else { return false }
                Task {
                    await MessageInputDropSupport.applyDrop(to: store, providers: providers)
                }
                return true
            }
            .onPasteCommand(of: MessageInputPasteSupport.pasteTypes) { _ in
                PasteDebugTrace.log(
                    "swiftui-onPasteCommand",
                    PasteDebugTrace.describePasteboard(),
                    store: store
                )
                if AttachmentImportExecutor.tryImportFromPasteboard(into: store) {
                    PasteDebugTrace.log("swiftui-onPasteCommand", "import OK", store: store)
                    return
                }
                store.importResult(ClipboardPasteResult(), showErrorOnEmpty: true)
                PasteDebugTrace.log("swiftui-onPasteCommand", "import failed", store: store)
            }
    }
}

extension View {
    func messageAttachmentImportZone(store: MessageAttachmentStore) -> some View {
        modifier(MessageAttachmentImportZone(store: store))
    }
}

struct AttachmentImportErrorBanner: View {
    @ObservedObject var store: MessageAttachmentStore

    var body: some View {
        VStack(spacing: 4) {
            if PasteDebugSettings.isEnabled, let debugLine = store.lastPasteDebugLine {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.brand)
                    Text(debugLine)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .background(Color.mimo.brand.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 6)
            }

            if let error = store.lastImportError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.warning)
                    Text(error)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                    Spacer()
                    Button(action: { store.clearImportError() }) {
                        Image(systemName: "xmark")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.vertical, 6)
                .background(Color.mimo.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.mimo.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
    }
}
