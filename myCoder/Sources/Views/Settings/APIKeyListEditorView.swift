import SwiftUI

/// Список API-ключей провайдера: одно поле на ключ, кнопка «+» добавляет
/// пустое поле, корзина удаляет. Первое поле — основной ключ провайдера,
/// остальные — резервные (пул).
///
/// Модуль не знает о хранилище: он только показывает и меняет массив строк
/// и сообщает о каждом изменении через `onCommit`. Чистая логика
/// (сборка/разбор списка, трим, дедупликация) живёт в
/// `ProviderAPIKeyListLogic` и покрыта тестами.
///
/// Входы: `$keys` — массив строк полей; `onCommit` — сохранение.
/// Выходы: изменённый массив; вызов `onCommit` после каждого изменения.
/// Зависимости: только SwiftUI и локализация `AppLocalizationKey`.
struct APIKeyListEditorView: View {
    /// Строки полей; первая — основной ключ.
    @Binding var keys: [String]
    /// Сохранение после изменения (коммит draft'а провайдера).
    var onCommit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($keys.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    TextField(L.t(AppLocalizationKey.locAPIKeyPlaceholder), text: $keys[index])
                        .textFieldStyle(.plain)
                        .interfaceFont(size: 11, design: .monospaced)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color.mimo.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.mimo.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit(onCommit)
                        // Сохранение при любом изменении текста, а не только
                        // по Enter: иначе потеря фокуса теряла бы ввод.
                        .onChange(of: keys[index]) { _ in
                            onCommit()
                        }

                    Button(role: .destructive) {
                        keys.remove(at: index)
                        onCommit()
                    } label: {
                        Image(systemName: "trash")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.error)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t(AppLocalizationKey.locAPIKeyRemove))
                }
            }

            Button {
                keys.append("")
                onCommit()
            } label: {
                Label(L.t(AppLocalizationKey.locAPIKeyAdd), systemImage: "plus")
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
        }
    }
}
