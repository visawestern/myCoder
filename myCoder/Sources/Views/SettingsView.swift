import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar()
            
            Divider()
            
            SettingsContent()
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.mimo.background)
        .preferredColorScheme(appState.appTheme.preferredColorScheme)
    }
}

struct SettingsSidebar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { appState.showSettings = false }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .interfaceFont(size: 12)
                    Text(AppLocalization.string(.settingsBackToWorkspace, language: appState.appLanguage))
                        .interfaceFont(size: 13)
                }
                .foregroundColor(Color.mimo.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(HandCursorButtonStyle())
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsTab.visibleCases) { tab in
                        SettingsTabRow(tab: tab)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .frame(width: 220)
        .background(Color.mimo.backgroundAlt)
    }
}

struct SettingsTabRow: View {
    let tab: SettingsTab
    @EnvironmentObject var appState: AppState
    
    var isSelected: Bool { appState.settingsTab == tab }
    
    var body: some View {
        Button(action: { appState.settingsTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .interfaceFont(size: 14)
                    .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textMuted)
                    .frame(width: 20)
                
                Text(AppLocalization.settingsTabName(tab, language: appState.appLanguage))
                    .interfaceFont(size: 13)
                    .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.mimo.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .padding(.horizontal, 8)
    }
}

struct SettingsContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch appState.settingsTab {
                    case .general:
                        GeneralSettingsView()
                    case .codePreview:
                        CodePreviewSettingsView()
                    case .modelSettings, .providers:
                        // Unified Providers tab (plan Раздел 1): model/provider
                        // selection columns + provider management + local providers.
                        UnifiedProvidersView(availableWidth: max(0, geometry.size.width - 64))
                    case .skills:
                        SkillsSettingsView()
                    case .mcpServers:
                        MCPServersSettingsView()
                    case .plugins:
                        PluginsSettingsView()
                    case .commands:
                        CommandsSettingsView()
                    case .indexing:
                        IndexingSettingsView()
                    case .storage:
                        StorageSettingsView()
                    case .usage:
                        UsageSettingsView()
                    }
                }
                .padding(32)
            }
        }
    }
}

// MARK: - Shared UI Components

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .background(Color.mimo.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.border, lineWidth: Color.mimo.isLightTheme ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let description: String
    @ViewBuilder let trailing: Trailing
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .interfaceFont(size: 14, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Text(description)
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textMuted)
                }
                
                Spacer()
                
                trailing
            }
        }
        .padding(.vertical, 12)
        
        Divider()
    }
}

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        SettingsRow(title: title, description: description) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

// MARK: - Shared Empty State

@ViewBuilder
func settingsEmptyState(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .interfaceFont(size: 14)
            .foregroundColor(Color.mimo.textMuted)
        Text(subtitle)
            .interfaceFont(size: 12)
            .foregroundColor(Color.mimo.textSecondary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.mimo.surface)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mimo.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 8))
}
