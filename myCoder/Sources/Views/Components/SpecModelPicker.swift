import SwiftUI

/// Provider → model tree used by the spec wizard's model roles.
///
/// A flat list mixed every provider's models together, which made picking a
/// planning model error-prone. The tree keeps the provider visible, collapses
/// large catalogs, and shows a metadata card on hover (context window,
/// output limit, reasoning/vision/tools, cost). Only providers the wizard can
/// call directly are in the tree — chat-only transports never appear.
struct SpecModelPicker: View {
    let title: String
    let hint: String
    let groups: [SpecModelGroup]
    @Binding var providerID: String
    @Binding var modelID: String
    let onManageModels: () -> Void

    @State private var isOpen = false
    @State private var collapsedProviders: Set<String> = []
    @State private var hoveredOption: SpecModelOption?

    private var selectedOption: SpecModelOption? {
        SpecWizardModelCatalog.option(
            providerID: providerID,
            modelID: modelID,
            in: groups
        )
    }

    private var defaultDetailsOption: SpecModelOption? {
        hoveredOption ?? selectedOption
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(hint)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 7) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(selectedTitle)
                            .interfaceFont(size: 12, weight: selectedOption == nil ? .regular : .medium)
                            .foregroundColor(selectedOption == nil ? Color.mimo.textMuted : Color.mimo.textPrimary)
                            .lineLimit(1)
                        if let selectedOption {
                            Text(selectedOption.providerName)
                                .interfaceFont(size: 9)
                                .foregroundColor(Color.mimo.textMuted)
                                .lineLimit(1)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .interfaceFont(size: 9, weight: .semibold)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 170, alignment: .trailing)
                .background(Color.mimo.controlBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.mimo.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(HandCursorButtonStyle())
            .fixedSize()
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                pickerContent
            }
        }
    }

    private var selectedTitle: String {
        if let selectedOption { return selectedOption.displayName }
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L.t("Choose model") : trimmed
    }

    // MARK: - Popover

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if groups.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    treePane
                        .frame(width: 310)
                    Divider()
                    detailsPane
                        .frame(width: 300)
                }
                .frame(height: 360)
                Divider()
                Button {
                    isOpen = false
                    onManageModels()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .interfaceFont(size: 10)
                        Text(L.t("Manage models"))
                            .interfaceFont(size: 11)
                        Spacer()
                    }
                    .foregroundColor(Color.mimo.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HandCursorButtonStyle())
            }
        }
        .frame(width: 610)
        .background(Color.mimo.background)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("No models are available"))
                .interfaceFont(size: 12, weight: .medium)
                .foregroundColor(Color.mimo.textPrimary)
            Text(L.t("Enable a provider or connect a local model before choosing the planning and coding models."))
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                isOpen = false
                onManageModels()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .interfaceFont(size: 10)
                    Text(L.t("Configure models…"))
                        .interfaceFont(size: 11)
                }
                .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tree

    private var treePane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(groups) { group in
                    providerSection(group)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func providerSection(_ group: SpecModelGroup) -> some View {
        let isCollapsed = collapsedProviders.contains(group.id)
        return VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed {
                        collapsedProviders.remove(group.id)
                    } else {
                        collapsedProviders.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .interfaceFont(size: 8, weight: .bold)
                        .foregroundColor(Color.mimo.textMuted)
                        .frame(width: 9)
                    Image(systemName: group.source.icon)
                        .interfaceFont(size: 10, weight: .medium)
                        .foregroundColor(Color.mimo.brand)
                    Text(group.providerName)
                        .interfaceFont(size: 11, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                        .lineLimit(1)
                    Text(L.t(group.source.label))
                        .interfaceFont(size: 8, weight: .semibold)
                        .foregroundColor(Color.mimo.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.mimo.textMuted.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Spacer(minLength: 4)
                    Text("\(group.models.count)")
                        .interfaceFont(size: 9, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())

            if !isCollapsed {
                ForEach(group.models) { option in
                    modelRow(option)
                }
            }
        }
    }

    private func modelRow(_ option: SpecModelOption) -> some View {
        let isSelected = option.providerID == providerID && option.modelID == modelID
        let isHovered = hoveredOption?.id == option.id
        return Button {
            providerID = option.providerID
            modelID = option.modelID
            isOpen = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .interfaceFont(size: 9)
                    .foregroundColor(isSelected ? Color.mimo.brand : Color.mimo.textMuted.opacity(0.6))
                    .frame(width: 11)
                Text(option.displayName)
                    .interfaceFont(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced)
                    .foregroundColor(isSelected ? Color.mimo.brand : Color.mimo.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let context = option.metadata.contextWindow {
                    Text(ModelCapabilityLogic.contextLabel(for: context))
                        .interfaceFont(size: 8, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                }
                if option.metadata.reasoning == true {
                    Image(systemName: "brain.head.profile")
                        .interfaceFont(size: 8)
                        .foregroundColor(Color.mimo.violet)
                        .help(L.t("Reasoning"))
                }
                if option.metadata.vision == true {
                    Image(systemName: "eye")
                        .interfaceFont(size: 8)
                        .foregroundColor(Color.mimo.cyan)
                        .help(L.t("Vision"))
                }
            }
            .padding(.leading, 25)
            .padding(.trailing, 9)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color.mimo.brand.opacity(0.10)
                    : (isHovered ? Color.mimo.textMuted.opacity(0.08) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { hovering in
            if hovering {
                hoveredOption = option
            } else if hoveredOption?.id == option.id {
                hoveredOption = nil
            }
        }
    }

    // MARK: - Details card

    private var detailsPane: some View {
        ScrollView {
            if let option = defaultDetailsOption {
                metadataCard(option)
                    .padding(12)
            } else {
                Text(L.t("Hover over a model to see its details."))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(16)
            }
        }
        .background(Color.mimo.backgroundAlt.opacity(0.25))
    }

    private func metadataCard(_ option: SpecModelOption) -> some View {
        let metadata = option.metadata
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: metadata.source.icon)
                    .interfaceFont(size: 13, weight: .medium)
                    .foregroundColor(Color.mimo.brand)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.displayName)
                        .interfaceFont(size: 13, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(option.providerName)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }

            if let description = metadata.description,
               !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(description)
                    .interfaceFont(size: 10.5)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            infoRow(
                L.t("Context window"),
                value: contextValue(metadata)
            )
            infoRow(
                L.t("Max output"),
                value: outputValue(metadata)
            )
            infoRow(
                L.t("Cost"),
                value: costValue(metadata)
            )

            Divider()

            Text(L.t("Capabilities").uppercased())
                .interfaceFont(size: 8, weight: .bold)
                .foregroundColor(Color.mimo.textMuted)

            capabilityRow(L.t("Reasoning"), systemImage: "brain.head.profile", value: metadata.reasoning)
            capabilityRow(L.t("Vision"), systemImage: "eye", value: metadata.vision)
            capabilityRow(L.t("Tools"), systemImage: "wrench.and.screwdriver", value: metadata.toolCall)
            capabilityRow(L.t("Planning"), systemImage: "map", value: metadata.plan)
            capabilityRow(L.t("Image generation"), systemImage: "photo", value: metadata.imageGeneration)

            Text(option.modelID)
                .interfaceFont(size: 8.5, design: .monospaced)
                .foregroundColor(Color.mimo.textMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
            Spacer(minLength: 6)
            Text(value)
                .interfaceFont(size: 10, weight: .medium, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func capabilityRow(_ label: String, systemImage: String, value: Bool?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .interfaceFont(size: 9)
                .foregroundColor(value == true ? Color.mimo.brand : Color.mimo.textMuted.opacity(0.7))
                .frame(width: 12)
            Text(label)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textSecondary)
            Spacer(minLength: 6)
            Text(capabilityValue(value))
                .interfaceFont(size: 10, weight: value == true ? .medium : .regular)
                .foregroundColor(capabilityColor(value))
        }
    }

    private func capabilityValue(_ value: Bool?) -> String {
        switch value {
        case .some(true): return L.t("Yes")
        case .some(false): return L.t("No")
        case .none: return L.t("Not reported")
        }
    }

    private func capabilityColor(_ value: Bool?) -> Color {
        switch value {
        case .some(true): return Color.mimo.success
        case .some(false): return Color.mimo.textMuted
        case .none: return Color.mimo.textMuted
        }
    }

    private func contextValue(_ metadata: SpecModelMetadata) -> String {
        guard metadata.effectiveContextWindow > 0 else { return L.t("Not reported") }
        let label = ModelCapabilityLogic.contextLabel(for: metadata.effectiveContextWindow)
        return metadata.isContextReported
            ? "\(label) \(L.t("tokens"))"
            : "\(label) \(L.t("tokens")) · \(L.t("estimated"))"
    }

    private func outputValue(_ metadata: SpecModelMetadata) -> String {
        guard metadata.effectiveOutputLimit > 0 else { return L.t("Not reported") }
        let label = ModelCapabilityLogic.contextLabel(for: metadata.effectiveOutputLimit)
        return metadata.outputLimit == nil
            ? "\(label) \(L.t("tokens")) · \(L.t("estimated"))"
            : "\(label) \(L.t("tokens"))"
    }

    private func costValue(_ metadata: SpecModelMetadata) -> String {
        if metadata.isFree { return L.t("Free") }
        let input = metadata.costInput
        let output = metadata.costOutput
        switch (input, output) {
        case let (.some(input), .some(output)):
            return "$\(formatCost(input)) / $\(formatCost(output)) \(L.t("per 1M tokens"))"
        case let (.some(input), .none):
            return "$\(formatCost(input)) \(L.t("input per 1M tokens"))"
        case let (.none, .some(output)):
            return "$\(formatCost(output)) \(L.t("output per 1M tokens"))"
        case (.none, .none):
            return L.t("Not reported")
        }
    }

    private func formatCost(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
