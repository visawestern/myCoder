import SwiftUI

/// Диалог отчёта об откате — как чип «Контекст»: стадии, проблемы и
/// успехи, плюс наглядные диффы файлов «до/после» в стиле VSCode.
struct RollbackReportSheet: View {
    let report: RollbackReport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stagesSection
                    if !report.diffs.isEmpty {
                        diffsSection
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color.mimo.surface)
    }

    private var header: some View {
        HStack {
            Image(systemName: report.plan.full ? "arrow.uturn.backward.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.plan.full ? "Откат выполнен" : "Откат частичный")
                    .interfaceFont(size: 14, weight: .semibold)
                if let reason = report.plan.stopReason {
                    Text(reason)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.mimo.controlBackground, in: Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .help(L.t(AppLocalizationKey.locClose))
        }
        .padding(16)
        .background(Color.mimo.controlBackground.opacity(0.5))
    }

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Stages")).interfaceFont(size: 13, weight: .semibold)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(report.stages.enumerated()), id: \.offset) { _, stage in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: stage.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundColor(stage.success ? .green : .red)
                            .interfaceFont(size: 12)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stage.title)
                                .interfaceFont(size: 12, weight: .medium)
                            Text(stage.detail)
                                .interfaceFont(size: 11)
                                .foregroundColor(Color.mimo.textSecondary)
                        }
                        Spacer()
                    }
                }
                if let error = report.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(10)
            .background(Color.mimo.controlBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var diffsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("File diffs")).interfaceFont(size: 13, weight: .semibold)
            ForEach(Array(report.diffs.enumerated()), id: \.offset) { _, diff in
                RollbackDiffRow(diff: diff)
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

/// Строка диффа «до/после» в стиле VSCode: слева old, справа new.
struct RollbackDiffRow: View {
    let diff: RollbackFileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(diff.path)
                    .interfaceFont(size: 11, weight: .semibold, design: .monospaced)
                Spacer()
            }
            HStack(spacing: 8) {
                side(title: "До", text: diff.before, color: .red)
                side(title: "После", text: diff.after, color: .green)
            }
        }
        .padding(10)
        .background(Color.mimo.controlBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func side(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .interfaceFont(size: 10, weight: .semibold)
                .foregroundColor(color)
            ScrollView {
                Text(text.isEmpty ? "(пусто)" : text)
                    .interfaceFont(size: 11, design: .monospaced)
                    .foregroundColor(Color.mimo.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
        }
        .padding(8)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
