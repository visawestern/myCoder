import SwiftUI

/// Custom language dropdown with flag emoji + native name + search (plan Раздел 2
/// Блок 4). Replaces the system Menu picker.
struct LanguagePickerDropdown: View {
    let selected: AppLanguage
    let onSelect: (AppLanguage) -> Void

    @State private var isOpen = false
    @State private var query = ""

    var body: some View {
        Button(action: { isOpen.toggle() }) {
            HStack(spacing: 6) {
                Text(selected.flag)
                Text(selected.nativeName)
                    .interfaceFont(size: 12, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.mimo.surface)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(HandCursorButtonStyle())
        .popover(isPresented: $isOpen) {
            dropdownContent
        }
    }

    private var dropdownContent: some View {
        let rows = LanguagePickerLogic.filter(LanguagePickerLogic.rows(selected: selected), query: query)
        return VStack(alignment: .leading, spacing: 4) {
            TextField(L.t(AppLocalizationKey.locSearchLanguage), text: $query)
                .zcodeTextFieldStyle()
                .interfaceFont(size: 12)
                .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.language) { row in
                        Button(action: {
                            onSelect(row.language)
                            isOpen = false
                        }) {
                            HStack(spacing: 8) {
                                Text(row.flag)
                                Text(row.nativeName)
                                    .interfaceFont(size: 13)
                                    .foregroundColor(Color.mimo.textPrimary)
                                Spacer()
                                if row.isSelected {
                                    Image(systemName: "checkmark")
                                        .interfaceFont(size: 11)
                                        .foregroundColor(Color.mimo.brand)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(row.isSelected ? Color.mimo.brand.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .accessibilityLabel(row.accessibilityLabel)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(12)
        .frame(width: 240)
    }
}
