import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    private var language: AppLanguage { appState.appLanguage }

    private var terminalFontBinding: Binding<String> {
        Binding(
            get: { appState.settings.terminalFont },
            set: { newValue in appState.updateSettings { $0.terminalFont = newValue } }
        )
    }

    private var inheritTerminalBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.inheritTerminalProfile },
            set: { newValue in appState.updateSettings { $0.inheritTerminalProfile = newValue } }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(AppLocalization.string(.settingsGeneralTitle, language: language))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            SettingsCard {
                SettingsRow(
                    title: AppLocalization.string(.settingsAppThemeTitle, language: language),
                    description: AppLocalization.string(.settingsAppThemeDescription, language: language)
                ) {
                    SettingsMenuLabel(title: appState.appTheme.rawValue) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Button(theme.rawValue) {
                                appState.appTheme = theme
                            }
                        }
                    }
                }
                
                SettingsRow(
                    title: AppLocalization.string(.settingsLanguageTitle, language: language),
                    description: AppLocalization.string(.settingsLanguageDescription, language: language)
                ) {
                    LanguagePickerDropdown(
                        selected: appState.appLanguage,
                        onSelect: { appState.setLanguage($0) }
                    )
                }
                
                SettingsRow(
                    title: AppLocalization.string(.settingsInterfaceZoomTitle, language: language),
                    description: AppLocalization.string(.settingsInterfaceZoomDescription, language: language)
                ) {
                    HStack(spacing: 0) {
                        ForEach(AppSettings.Zoom.allCases, id: \.self) { zoom in
                            Button(action: {
                                appState.updateSettings { $0.zoom = zoom }
                            }) {
                                Text(zoom.rawValue)
                                    .interfaceFont(size: 13, weight: appState.settings.zoom == zoom ? .semibold : .regular)
                                    .foregroundColor(appState.settings.zoom == zoom ? Color.mimo.textPrimary : Color.mimo.textMuted)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        appState.settings.zoom == zoom
                                            ? RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.mimo.surface)
                                            : nil
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(HandCursorButtonStyle())
                            .help(zoom.rawValue)
                        }
                    }
                    .padding(4)
                    .background(Color.mimo.backgroundAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            SettingsCard {
                SettingsToggleRow(
                    title: AppLocalization.string(.settingsInheritTerminalTitle, language: language),
                    description: AppLocalization.string(.settingsInheritTerminalDescription, language: language),
                    isOn: inheritTerminalBinding
                )
                
                SettingsRow(
                    title: AppLocalization.string(.settingsTerminalFontTitle, language: language),
                    description: AppLocalization.string(.settingsTerminalFontDescription, language: language)
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(
                            AppLocalization.string(.settingsTerminalFontPlaceholder, language: language),
                            text: terminalFontBinding
                        )
                        .zcodeTextFieldStyle()
                        .interfaceFont(size: 13, design: .monospaced)

                        Text(TerminalFontResolver.displayLabel(settings: appState.settings, language: language))
                            .interfaceFont(size: 11, design: .monospaced)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                }
            }
            
            SettingsCard {
                SettingsRow(title: L.t(AppLocalizationKey.locHttpProxy), description: L.t(AppLocalizationKey.locRouteModelMcpCommandtoolAndAppRendererEgressTra)) {
                    TextField(L.t(AppLocalizationKey.locLeaveBlankDirect), text: $appState.settings.httpProxy)
                        .zcodeTextFieldStyle()
                        .interfaceFont(size: 13)
                }
            }
            
            SettingsCard {
                SettingsToggleRow(
                    title: L.t(AppLocalizationKey.settingsInputDropdownTitle),
                    description: L.t(AppLocalizationKey.settingsInputDropdownDescription),
                    isOn: Binding(
                        get: { appState.inputDropdownEnabled },
                        set: { appState.inputDropdownEnabled = $0 }
                    )
                )
            }
        }
    }
}

struct CodePreviewSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.t(AppLocalizationKey.locCodePreview))
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            SettingsCard {
                SettingsRow(title: L.t(AppLocalizationKey.locLightCodeTheme), description: L.t(AppLocalizationKey.locThemeUsedForCodeBlocksWhileTheInterfaceLightMod)) {
                    SettingsMenuLabel(title: appState.settings.lightCodeTheme) {
                        ForEach([L.t(AppLocalizationKey.locGitHubLight), L.t(AppLocalizationKey.locGitHubDark), L.t(AppLocalizationKey.locOneLight), L.t(AppLocalizationKey.locSolarizedLight)], id: \.self) { theme in
                            Button(theme) {
                                appState.updateSettings { $0.lightCodeTheme = theme }
                            }
                        }
                    }
                }

                SettingsRow(title: L.t(AppLocalizationKey.locDarkCodeTheme), description: L.t(AppLocalizationKey.locThemeUsedForCodeBlocksWhileTheInterfaceDarkMode)) {
                    SettingsMenuLabel(title: appState.settings.darkCodeTheme) {
                        ForEach([L.t(AppLocalizationKey.locGitHubDark), L.t(AppLocalizationKey.locGitHubLight), L.t(AppLocalizationKey.locOneDark), L.t(AppLocalizationKey.locSolarizedDark), L.t(AppLocalizationKey.locDracula)], id: \.self) { theme in
                            Button(theme) {
                                appState.updateSettings { $0.darkCodeTheme = theme }
                            }
                        }
                    }
                }
                
                SettingsToggleRow(title: L.t(AppLocalizationKey.locShowLineNumbers), description: L.t(AppLocalizationKey.locDisplayLineNumbersCodePreviews), isOn: $appState.settings.showLineNumbers)
                
                SettingsToggleRow(title: L.t(AppLocalizationKey.locWrapLongLines), description: L.t(AppLocalizationKey.locWrapLongContentInsideThePreviewAreaAutomaticall), isOn: $appState.settings.wrapLongLines)
                
                SettingsRow(title: L.t(AppLocalizationKey.locCodeFontSize), description: L.t(AppLocalizationKey.locAdjustTheDefaultFontSizeUsedCodePreviews)) {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(appState.settings.codeFontSize) },
                            set: { appState.settings.codeFontSize = Int($0) }
                        ), in: 8...24, step: 1)
                        Text("\(appState.settings.codeFontSize)")
                            .interfaceFont(size: 12, design: .monospaced)
                            .foregroundColor(Color.mimo.textMuted)
                            .frame(width: 30)
                    }
                }
            }
        }
    }
}
