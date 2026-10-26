import SwiftUI

struct PlusMenuView: View {
    @Binding var messageText: String
    @Binding var showFilePicker: Bool
    @Binding var isPresented: Bool
    var showPhotoPicker: Binding<Bool>? = nil
    var canUseTools: Bool = true

    private var visibleItems: [PlusMenuItem] {
        PlusMenuCapabilityLogic.visibleItems(PlusMenuItem.allCases, canUseTools: canUseTools)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleItems, id: \.self) { item in
                Button(action: {
                    isPresented = false
                    if item == .addAttachment {
                        showFilePicker = true
                    } else if item == .addPhoto {
                        showPhotoPicker?.wrappedValue = true
                    } else if let prefix = item.prefix {
                        messageText = prefix
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .interfaceFont(size: 12)
                            .frame(width: 16)
                        Text(item.label)
                            .interfaceFont(size: 13)
                    }
                    .foregroundColor(Color.mimo.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            if !canUseTools {
                Text(L.t(AppLocalizationKey.locToolsUnavailableForThisModel))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 200)
        .background(Color.mimo.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.mimo.shadow, radius: 8, x: 0, y: 4)
    }
}
