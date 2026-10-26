import SwiftUI

/// Dropdown shown by the sidebar's New Project action. Two explicit paths:
/// a plain project (chat immediately) or the spec-wizard project (chat gated
/// until the specification setup is finished or force-finished).
struct NewProjectTypeMenu: View {
    @EnvironmentObject var appState: AppState
    let onSelect: (ProjectCreationMode) -> Void

    @State private var hovered: ProjectCreationMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("Create a project"))
                .interfaceFont(size: 10, weight: .bold, design: .monospaced)
                .tracking(0.8)
                .foregroundColor(Color.mimo.textMuted)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

            row(
                mode: .empty,
                icon: "folder.badge.plus",
                iconTint: Color.mimo.textSecondary,
                title: L.t("Empty project"),
                subtitle: L.t("Register a folder and start chatting right away — no specification required."),
                tooltip: L.t("Best for existing codebases or quick work: opens an empty chat in the selected folder.")
            )

            row(
                mode: .wizard,
                icon: "wand.and.stars",
                iconTint: Color.mimo.cyan,
                title: L.t("Project setup"),
                subtitle: L.t("Answer a few questions and get a clear plan before coding."),
                tooltip: L.t("Choose a planning model and a coding model, answer questions, and get a versioned specification. Chat opens when the plan is ready.")
            )

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .interfaceFont(size: 9)
                Text(L.t("Finish project setup before chat opens."))
                    .interfaceFont(size: 10)
            }
            .foregroundColor(Color.mimo.textMuted)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .padding(8)
        .frame(width: 360)
        .background(Color.mimo.backgroundAlt)
    }

    private func row(mode: ProjectCreationMode,
                     icon: String,
                     iconTint: Color,
                     title: String,
                     subtitle: String,
                     tooltip: String) -> some View {
        Button {
            onSelect(mode)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .interfaceFont(size: 14, weight: .medium)
                    .foregroundColor(iconTint)
                    .frame(width: 30, height: 30)
                    .background(iconTint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .interfaceFont(size: 13, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(subtitle)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovered == mode ? Color.mimo.surfaceHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { hovering in
            hovered = hovering ? mode : (hovered == mode ? nil : hovered)
        }
        .help(tooltip)
    }
}
