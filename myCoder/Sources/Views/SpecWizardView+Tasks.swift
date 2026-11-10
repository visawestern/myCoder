import SwiftUI

extension SpecWizardContent {
    // MARK: Tasks

    var decompositionPhase: some View {
        let nextNodeID = session.nextRunnableNode()?.id
        return VStack(alignment: .leading, spacing: 14) {
            specificationCard

            if session.nodes.isEmpty {
                card(title: L.t("Task breakdown"), icon: "square.stack.3d.up") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("Split the approved specification into tasks that can be checked independently. This step does not write code."))
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textSecondary)
                        HStack {
                            Spacer()
                            primaryButton(
                                L.t("Break into tasks"),
                                icon: "square.stack.3d.up",
                                isBusy: session.isLoading
                            ) {
                                Task { await session.generateDecomposition() }
                            }
                            .disabled(session.isLoading)
                        }
                    }
                }
            } else {
                ForEach(session.nodes, id: \.id) { node in
                    decompositionNodeCard(node, isNext: nextNodeID == node.id)
                }

                HStack {
                    Spacer()
                    primaryButton(L.t("Finish and open chat"), icon: "checkmark.circle") {
                        if session.finishWizard(forced: false) {
                            appState.finishSpecWizard(for: session.projectPath)
                        }
                    }
                }
            }
        }
    }

    func decompositionNodeCard(_ node: ProjectSpecNode, isNext: Bool) -> some View {
        let dependencies = session.dependencies(of: node)
        let acceptance = decodeAcceptance(node.acceptanceCriteriaJSON)
        let hasCodingChat = !session.nodeSessions(for: node.id).isEmpty
        return card(title: "\(node.externalKey) · \(node.title)", icon: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: 10) {
                nodeStatusBadge(node.status)

                Text(node.description)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !acceptance.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t("Completion criteria"))
                            .interfaceFont(size: 10, weight: .semibold)
                            .foregroundColor(Color.mimo.textMuted)
                        ForEach(acceptance, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(item)
                            }
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textPrimary)
                        }
                    }
                }

                if !dependencies.isEmpty {
                    Text("\(L.t("Depends on")): \(dependencies.map(\.externalKey).joined(separator: ", "))")
                        .interfaceFont(size: 10, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                }

                nodeActions(node, isNext: isNext, hasCodingChat: hasCodingChat)
            }
        }
    }

    @ViewBuilder
    func nodeActions(_ node: ProjectSpecNode,
                             isNext: Bool,
                             hasCodingChat: Bool) -> some View {
        HStack(spacing: 8) {
            switch node.status {
            case "pending":
                if isNext {
                    primaryButton(L.t("Start coding"), icon: "play.fill") {
                        appState.startSpecNodeCoding(wizard: session, node: node)
                    }
                } else {
                    Text(L.t("Waiting for dependencies"))
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
            case "running":
                if hasCodingChat {
                    secondaryButton(L.t("Open coding chat"), icon: "bubble.left") {
                        appState.openSpecNodeChat(wizard: session, nodeID: node.id)
                    }
                }
                secondaryButton(L.t("Mark done"), icon: "checkmark.circle") {
                    session.finishNode(nodeID: node.id, status: "done")
                }
                secondaryButton(L.t("Mark failed"), icon: "xmark.circle") {
                    session.finishNode(nodeID: node.id, status: "failed")
                }
            case "failed", "blocked":
                secondaryButton(L.t("Retry"), icon: "arrow.clockwise") {
                    session.retryNode(nodeID: node.id)
                }
                if hasCodingChat {
                    secondaryButton(L.t("Open coding chat"), icon: "bubble.left") {
                        appState.openSpecNodeChat(wizard: session, nodeID: node.id)
                    }
                }
            case "done", "skipped":
                if hasCodingChat {
                    secondaryButton(L.t("Open coding chat"), icon: "bubble.left") {
                        appState.openSpecNodeChat(wizard: session, nodeID: node.id)
                    }
                }
            default:
                EmptyView()
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    func nodeStatusBadge(_ status: String) -> some View {
        let color = nodeStatusColor(status)
        return Text(nodeStatusLabel(status))
            .interfaceFont(size: 9, weight: .semibold)
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    func nodeStatusLabel(_ status: String) -> String {
        switch status {
        case "running": return L.t("Running")
        case "done": return L.t("Done")
        case "failed": return L.t("Failed")
        case "blocked": return L.t("Blocked")
        case "skipped": return L.t("Skipped")
        default: return L.t("Pending")
        }
    }

    func nodeStatusColor(_ status: String) -> Color {
        switch status {
        case "running": return Color.mimo.cyan
        case "done": return Color.mimo.success
        case "failed": return Color.mimo.error
        case "blocked": return Color.mimo.warning
        default: return Color.mimo.textMuted
        }
    }

    func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .interfaceFont(size: 10, weight: .semibold)
                Text(title)
                    .interfaceFont(size: 11, weight: .medium)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.mimo.controlBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.mimo.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(HandCursorButtonStyle())
        .foregroundColor(Color.mimo.textPrimary)
    }

    func decodeAcceptance(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }
}
