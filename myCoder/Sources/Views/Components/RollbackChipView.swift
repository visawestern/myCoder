import SwiftUI

/// Оранжевый чип отката в чате. Показывает, что был произведён откат,
/// с полными данными (полный/частичный, сводка, время). По клику открывает
/// диалог отчёта (RollbackReportSheet) со стадиями и диффами файлов.
/// Наведение показывает тултип.
struct RollbackChipView: View {
    let data: RollbackChipData
    @State private var showReport = false

    private var color: Color {
        data.full ? Color.orange : Color.orange.opacity(0.75)
    }

    var body: some View {
        Button {
            showReport = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: data.full ? "arrow.uturn.backward.circle.fill" : "exclamationmark.triangle.fill")
                    .interfaceFont(size: 13)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.full ? L.t("Rollback complete") : L.t("Rollback partial"))
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(.white)
                    Text(data.summary)
                        .interfaceFont(size: 11)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                Image(systemName: "chevron.right")
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(color)
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(L.t("Open rollback report: stages, problems and file diffs"))
        .sheet(isPresented: $showReport) {
            RollbackReportSheet(report: data.report)
        }
    }
}

/// Кнопка-чип отката, встраиваемая в путь сообщений (системное сообщение
/// с маркером [ROLLBACK_CHIP]).
struct RollbackChipMessageView: View {
    let content: String
    var body: some View {
        if let chip = RollbackChipCodec.decode(from: content) {
            RollbackChipView(data: chip)
        }
    }
}
