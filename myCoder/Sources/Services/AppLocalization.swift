import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "English"
    case russian = "Russian"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case chineseSimplified = "Chinese"
    case japanese = "Japanese"
    case korean = "Korean"
    case portuguese = "Portuguese"
    case arabic = "Arabic"

    var id: String { rawValue }

    static func from(stored: String) -> AppLanguage {
        AppLanguage(rawValue: stored) ?? .english
    }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .chineseSimplified: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .portuguese: return "Português"
        case .arabic: return "العربية"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .russian: return "🇷🇺"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .chineseSimplified: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .portuguese: return "🇵🇹"
        case .arabic: return "🇸🇦"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .russian: return "ru_RU"
        case .spanish: return "es_ES"
        case .french: return "fr_FR"
        case .german: return "de_DE"
        case .chineseSimplified: return "zh_Hans"
        case .japanese: return "ja_JP"
        case .korean: return "ko_KR"
        case .portuguese: return "pt_PT"
        case .arabic: return "ar_SA"
        }
    }

    var isRTL: Bool { self == .arabic }
}

enum AppLocalizationKey: String, CaseIterable {
    case settingsBackToWorkspace
    case settingsGeneralTitle
    case settingsAppThemeTitle
    case settingsAppThemeDescription
    case settingsLanguageTitle
    case settingsLanguageDescription
    case settingsInterfaceZoomTitle
    case settingsInterfaceZoomDescription
    case settingsInheritTerminalTitle
    case settingsInheritTerminalDescription
    case settingsInputDropdownTitle
    case settingsInputDropdownDescription
    case settingsTerminalFontTitle
    case settingsTerminalFontDescription
    case settingsTerminalFontPlaceholder
    case settingsTerminalFontCurrentInherited
    case settingsTerminalFontCurrentOverride
    case settingsTabGeneral
    case settingsTabCodePreview
    case settingsTabModelSettings
    case settingsTabProviders
    case settingsTabSkills
    case settingsTabMCPServers
    case settingsTabPlugins
    case settingsTabCommands
    case settingsTabIndexing
    case settingsTabUsage
    case settingsCodePreviewTitle
    case settingsLightCodeThemeTitle
    case settingsLightCodeThemeDescription
    case settingsDarkCodeThemeTitle
    case settingsDarkCodeThemeDescription
    case settingsShowLineNumbersTitle
    case settingsShowLineNumbersDescription
    case settingsWrapLongLinesTitle
    case settingsWrapLongLinesDescription
    case settingsCodeFontSizeTitle
    case settingsCodeFontSizeDescription
    case settingsModelSettingsTitle
    case settingsModelSettingsDescription
    case settingsSkillsTitle
    case settingsSkillsDescription
    case settingsSearchSkillsPlaceholder
    case settingsNoSkillsInstalled
    case settingsNoSkillsInstalledSubtitle
    case settingsMCPServersTitle
    case settingsMCPServersDescription
    case settingsSearchMCPServersPlaceholder
    case settingsNoMCPServersConfigured
    case settingsNoMCPServersConfiguredSubtitle
    case settingsPluginsTitle
    case settingsPluginsDescription
    case settingsSearchPluginsPlaceholder
    case settingsNoPluginsInstalled
    case settingsNoPluginsInstalledSubtitle
    case settingsEnabled
    case settingsDisabled
    case settingsCommandsTitle
    case settingsCommandsDescription
    case settingsSearchCommandsPlaceholder
    case settingsNoUserCommands
    case settingsNoUserCommandsSubtitle
    case settingsIndexingTitle
    case settingsIndexingCodebaseTitle
    case settingsIndexNewFoldersTitle
    case settingsIndexNewFoldersDescription
    case settingsIndexRepositoriesTitle
    case settingsIndexRepositoriesDescription
    case settingsStorageTitle
    case settingsUsageTitle
    case settingsUsageSubtitle
    case settingsUsageTimeRange
    case settingsUsageTotalTokens
    case settingsUsageTotalCost
    case settingsUsageMessages
    case settingsUsageActiveDays
    case settingsUsageDatabaseSize
    case settingsUsageFavoriteModel
    case settingsUsageFavoriteModelSubtitle
    case settingsUsageByModel
    case settingsUsageNoData
    case settingsLocalProvidersTitle
    case settingsLocalProvidersDescription
    case settingsLocalProvidersAddressPlaceholder
    case settingsLocalProvidersAutoDetect
    case settingsLocalProvidersDetecting
    case settingsLocalProvidersAdded
    case settingsLocalProvidersAdd
    case settingsLocalProvidersEnabled
    case settingsLocalProvidersDisabled
    case settingsProvidersTitle
    case settingsProvidersDescription
    case settingsProvidersStatsProviders
    case settingsProvidersStatsModels
    case settingsProvidersSearchPlaceholder
    case settingsProvidersAdd
    case settingsProvidersNoProviders
    case settingsProvidersModelsCount
    case settingsProvidersToolsEnabled
    case settingsProvidersACPEnabled
    case settingsProvidersRemove
    case settingsConfirm
    case settingsCancel
    case settingsRemove
    case settingsDelete
    case settingsArchive
    case settingsRestore
    case settingsFindNewPath
    case settingsExportBackup
    case settingsImportBackup
    case settingsCompress
    case settingsArchiveNow
    case settingsDeleteOlderThan
    case settingsTypeNameToConfirm
    case settingsDeleteProjectDescription
    case settingsStorageQuotaExceeded
    case settingsStorageQuotaDescription
    case settingsStorageQuotaArchiveInactive
    case settingsNoProjectsRegistered
    case settingsActive
    case settingsArchived
    case settingsOrphaned
    case settingsAutoArchiveDescription
    case settingsArchiveAfter
    case settingsCleanupTitle
    case settingsCleanupDeleteChatsOlderThan
    case settingsDeleteButton
    case settingsDeleteAllArchivedChats
    case settingsCompressDatabase
    case settingsResetStorageTitle
    case settingsResetAppCache
    case settingsClearAppCache
    case settingsArchiveInactive
    case terminalTab
    case gitTab
    case terminalWelcome
    case terminalHelpHint
    case terminalHelpOutput
    case terminalCommandNotFound
    case gitToolsTitle
    case subagentsTitle
    case gitChanges
    case gitNoChanges
    case gitBranch
    case gitCommit
    case gitCommitAuto
    case gitCommitCustom
    case gitReviewPush
    case gitPublish
    case gitPublishTitle
    case gitRepoName
    case gitInitTitle
    case gitVisibility
    case gitPublic
    case gitPrivate
    case gitInitialize
    case gitPublishToGithub
    case gitBusyRetrying
    case gitInstallGHTitle
    case gitInstallGHSubtitle
    case gitInstallGHButton
    case gitSignInTitle
    case gitSignInSubtitle
    case gitSignInButton
    case gitCreateAndPush
    case gitCancel
    case gitInitSubtitle
    case gitReviewComment
    case gitReviewCommentPlaceholder
    case gitReviewSummary
    case gitCommitAndPush
    case gitOpenGitHubDocs
    case planTitle
    case noStepsYet
    case completedSteps
    case waitingSteps
    case appDisplayName
    case statusBarIdle
    case statusBarGenerating
    case statusBarProcessing
    case newProjectTitle
    case newProjectName
    case newProjectFolder
    case newProjectChooseFolder
    case newProjectCreate
    case newProjectCancel
    case notificationsTitle
    case notificationsEmpty
    case notificationsEmptySubtitle
    case workspacesTitle
    case noTasksYet
    case justNow
    case storageTabTitle
    case storageStatsTitle
    case storageDatabaseSize
    case storageSnapshotSize
    case storageMessageCount
    case storageActiveSessions
    case storageArchivedSessions
    case cleanupTitle
    case deleteChatsOlderThan
    case deleteChats7Days
    case deleteChats30Days
    case deleteChats90Days
    case deleteChats180Days
    case deleteChats1Year
    case deleteChatsConfirmTitle
    case deleteChatsConfirmMessage
    case deleteButton
    case cancelButton
    case deleteAllArchivedChats
    case compressDatabase
    case resetStorageTitle
    case resetAppCache
    case resetAppCacheConfirmTitle
    case resetButton
    case resetFullDatabase
    case resetFullDatabaseConfirmTitle
    case resetAppCacheWarning
    case resetFullDatabaseWarning
    case resetPlanPathsTitle
    case archiveNow
    case loc180Days
    case locActiveChats
    case locActiveDays
    case locAdd
    case locAddAnotherAccount
    case locAddFilesMycodercommands
    case locAddProvider
    case locAddProvider1
    case locAdjustTheDefaultFontSizeUsedCodePreviews
    case locApiKey
    case locAppUsage
    case locArchiveAfter
    case locArchived
    case locArchivedProjects
    case locArchivedProjects1
    case locAutoarchive
    case locAutomaticallyIndexAnyNewFoldersWithFewerThan500
    case locAutomaticallyIndexRepositoriesSpeedGrepSearches
    case locBack
    case locBaseUrl
    case locBrowseTheLibraryAndInstallMcpServersOneClickCon
    case locBrowseTheLibraryAndInstallSkillsOneClickManageL
    case locCannotPreviewImage
    case locChanges
    case locChanges1
    case locCleanup
    case locClearAll
    case locClose
    case locCodeFontSize
    case locCodePreview
    case locCodebase
    case locCommands
    case locCommandsSubtitle
    case locBuiltInCommands
    case locCustomCommands
    case locNewCommand
    case locAddCommand
    case locEditCommand
    case locCommandName
    case locCommandTemplate
    case locCommandPlaceholdersHint
    case locCommandBodyEmptyWarning
    case locDeleteCommandConfirmation
    case locConfiguration
    case locConfigureModelProvidersAndManageAvailableModels
    case locConfirmAndAdd
    case locConnectLocalAgentInstanceAnotherHost
    case locConnectTheLocalAgentAddCustomProvider
    case locConnectTheLocalAgentAddCustomProviderGetStarted
    case locCopyAll
    case locRawText
    case locFormatted
    case locCreate
    case locCreateProject
    case locCreatePullRequest
    case locCustom
    case locCustomModels
    case locDarkCodeTheme
    case locDatabase
    case locDatabaseSize
    case locDays
    case locDays1
    case locDays2
    case locDays3
    case locDays4
    case locDefault
    case locDeleteChatsOlderThan
    case locDescriptionOptional
    case locDetails
    case locDisableForLocalModelsProvidersThatDontNeedAuthe
    case locDisplayLineNumbersCodePreviews
    case locEdit
    case locEnableAgentCoderProtocol
    case locEnableAgentCoderProtocolForAutonomousCodingTask
    case locEnableDisableInstalledPluginsPluginsBundleSkill
    case locEnableFunctiontoolCallingSupport
    case locEnableFunctiontoolCallingSupportForThisProvider
    case locEscClose
    case locExistingChromeCookies
    case locFavoriteModel
    case locFolder
    case locHttpProxy
    case locImagePreview
    case locInactiveChatsAreAutomaticallyArchivedAfterTheSe
    case locIndexNewFolders
    case locIndexRepositoriesForInstantGrepBeta
    case locIndexing
    case locKeep
    case locLibrary
    case locLightCodeTheme
    case locLoadingChat
    case locLoadingOlderMessages
    case locLocalProviders
    case locManageCustomModelProvidersAndViewServerconnecte
    case locManageMycoderAgentCommandFilesCommandsCanInvoke
    case locManagedBrowser
    case locMcpServers
    case locMessages
    case locMycoder
    case locModel
    case locModelDetails
    case locModelEffortAreChosenTheChatInputAfterConnecting
    case locModelSettings
    case locInternalModels
    case locInternalModelsDescription
    case locAddInternalModel
    case locNoInternalModels
    case locInternalModelsHint
    case locInternalModelBadge
    case locInternalModelBadgeHelp
    case locMarkAsInternalModel
    case locUnmarkAsInternalModel
    case locInternalModelUnavailable
    case locMoveUp
    case locMoveDown
    case locFree
    case locModels
    case locModels1
    case locModelsForThisProvider
    case locModelsLoaded
    case locName
    case locNewProject
    case locNext
    case locNotifications
    case locNotifications1
    case locNow
    case locOpenFolder
    case locOpenFullStoragePanel
    case locOrphanedPathMissing
    case locRemoveOrphanedRecords
    case locRemoveOrphanedRecordsHelp
    case locAlertRemoveOrphanedRecords
    case locRemoveOrphanedRecordsMessage
    case locOverview
    case locParametersAvailable
    case locPerProject
    case locPickProviderTheLeftViewItsConnectionAndSettings
    case locPickServerFromTheLibraryAboveAndTapInstall
    case locPickSkillFromTheLibraryAboveAndTapInstall
    case locPlugins
    case locPluginsLiveUnderMycoderplugins
    case locProjectName
    case locProjects
    case locProjectsRegisteredYet
    case locProviderSelected
    case locProviderType
    case locProviders
    case locProvidersConfigured
    case locProvidersModels
    case locProvidersYet
    case locRemoteConnection
    case locRemove
    case locRetry
    case locRouteModelMcpCommandtoolAndAppRendererEgressTra
    case locRunModelsLocallyViaOllamaOpencodeMycoderCliserv
    case locSearch
    case locSelectProviderFirst
    case locShowLineNumbers
    case locSkills
    case locSnapshots
    case locStorageDatabase
    case locStorageQuotaExceeded
    case locSwitchPlanAgent
    case locSystemPrompt
    case locTaskCompletionsAndSystemAlertsWillAppearHere
    case locTasksYet
    case locTestConnection
    case locThemeUsedForCodeBlocksWhileTheInterfaceDarkMode
    case locThemeUsedForCodeBlocksWhileTheInterfaceLightMod
    case locThinking
    case locThisWillPermanentlyDeleteAllArchivedChatsAndThe
    case locTimeRange
    case locTitle
    case locToolsUnavailableForCurrentModel
    case locToolsUnavailableForTheCurrentModelProvider
    case locToolsUnavailableForThisModel
    case locTotal
    case locTotalCost
    case locTotalTokens
    case locTransmit
    case locUrl
    case locUsage
    case locUsage1
    case locUsageDataForTheSelectedPeriod
    case locUseFreeWebModelsKimiQwenChatgptThroughControlle
    case locWebProvidersBrowser
    case locWrapLongContentInsideThePreviewAreaAutomaticall
    case locWrapLongLines
    case locYear
    case locRemoveProvider
    case locSelect
    case locParameters
    case locCopyInfo
    case locNewTask
    case locOpenProject
    case locFilterWorkspaces
    case locNoWorkspaces
    case locCollapse
    // MARK: - Settings new localization keys
    case locSearchCommands
    case locSearchPlugins
    case locSearchSkills
    case locSearchMCPServers
    case locSearchProviders
    case locEnable
    case locDisable
    case locEnabled
    case locDisabled
    case locAdded
    case locSaveConfiguration
    case locRefreshModels
    case locRefreshWebModels
    case locWebSession
    case locCustomProvider
    case locLocalAgent
    case locConfigure
    case locConnect
    case locDisconnect
    case locAutoDetect
    case locDetecting
    case locSave
    case locLeaveBlankDirect
    case locAll
    case locSelectProviderToBrowse
    case locStartLocalAgent
    case locYes
    case locNo
    case locSupported
    case locNotSupported
    case locPer1KTokens
    case locToolResultFixOn
    case locToolResultFixOff
    case locConnectionSuccess
    case locWebLoginTitle
    case locWebDetectModels
    case locWebDetectModelsHelp
    case locWebCaptureSession
    case locWebDetecting
    case locWebModelsFound
    case locWebNoSelector
    case locShowInFinder
    case locStop
    case locModelPlaceholder
    case locVariantPlaceholder
    case locManageModels
    case locManageProviders
    case locHost
    case locPort
    case locNoVariants
    case locSearchWorkspaces
    case locSelectWorkspace
    case locPlanModeUnavailable
    case locProvider
    case locModelParameters
    case locParametersFor
    case locStopGeneration
    case locSendMessage
    case locSendNow
    case locQueueMessage
    case locEditQueuedMessage
    case locDeleteQueuedMessage
    case locPointContext
    case locPointContextDescription
    case locCompilingPointContext
    case locShowCompiledContext
    case locCompiledContextTitle
    case locContextCompilationFailed
    case locMemorySaved
    case locMemoryFailed
    case locMemoryUsage
    case locMemoryLoadFailed
    case locLedgerFailed
    case locAccessAskBefore
    case locAccessEditAuto
    case locAccessFull
    case locAccessAskBeforeDesc
    case locAccessEditAutoDesc
    case locAccessFullDesc
    case locModeBuild
    case locModePlan
    case locModeCompose
    case locToolCallDelay
    case locKeepalive
    case locTransport
    case locGitHubCliNotInstalled
    case locAddModel

    case locWebNoSelectorYet
    case locWebLoginFirst
    case locWebInputNotFound
    case locWebModelListFailed
    case locWebLoadedModels
    case locWebRefreshFailed
    case locWebEffortNoSelector
    case locWebEffortLoginFirst
    case locWebEffortInputNotFound
    case locWebEffortReadFailed
    case locWebLoadedEffort
    case locWebEffortRefreshFailed
    case locWebRequiresWebKit
    case locCaptchaSolveNote
    case locWebSessionExpired
    case locWebSessionTooLong
    case locWebNewSessionStarted
    case locWebModelNote
    case locWebEffortNote
    case locWebPromptSplit
    case locWebToolCall
    case locWebToolResult
    case locWebIterationLimit
    case locWebEmptyResponse
    case locWebProviderError
    case locWebModelInjectionFailed
    case locWebEffortNotFound
    case locWebModelNotFound
    case locWebModeNotFound
    case locWebCannotOpen
    case locWebRestoreSessionFailed
    case locWebCannotReadImage
    case locEmptyInput
    case locModeSwitched
    case locPlanNotSupported
    case locEffortLow
    case locEffortMedium
    case locEffortHigh
    case locThinkingMode
    case locFeatureModes
    case locAuto
    case locThink
    case locFast
    case locDeepResearch
    case locCreateImage
    case locCreateVideo
    case locWebDev
    case locTools
    case locMore
    case locUpload
    case locSlides
    case locSwarm
    case locInstant
    case locK3
    case locK3Swarm
    case locThinkingEffort
    case locPickerTitle
    case locPickerSelector
    case locPickerTag
    case locPickerClass
    case locPickerText
    case locUseAsModelSelector
    case locTosViolation
    case locModelsCount
    case locActiveCount
    case locArchivedCount
    case locMessageCount
    case locWebNoModels
    case locGenerationStopped
    case locTaskCompletedMessage
    case locResult
    case locArguments
    case locCompleted
    case locRunning
    case locResend
    case locCopied
    case locNewTaskSidebar
    case locMarkAllRead
    case locSelectFolder
    case locConfigured
    case locLogin
    case locConnecting
    case locChooseFolder
    case locMyProject
    case locShortSummary
    case locWhatChanged
    case locBranchName
    case locCreateNewBranch
    case locViewImage
    case locIgnore
    case locRestoreFromBackup
    case locConnected
    case locDisconnected
    case locUndoLastFileChange
    case locGoal
    case locTerminal
    case locCopyChat
    case locPickElement
    case locNotConfigured
    case locConnectionFailed
    case locRequiresAPIKey
    case locEnableToolCalling
    case locEnableACP
    case locAlertRemoveSkill
    case locAlertRemoveMCPServer
    case locUpdate
    case locUpdateAvailable
    case locInstall
    case locUninstall
    case locRequires
    case locDependenciesSatisfied
    case locDependenciesMissing
    case locNote
    case locAlertDeleteOldChats
    case locAlertDeleteArchivedChats
    case locAlertDeleteProject
    case locFindNewPath
    case locDeleteRecord
    case locDeleteProjectHelp
    case locLast7Days
    case locLast30Days
    case locGitHubLight
    case locGitHubDark
    case locOneLight
    case locOneDark
    case locSolarizedLight
    case locSolarizedDark
    case locDracula
    case locTypeToConfirm
    case locConfirmAndAdd1
    case locCancel
    case locDelete
    case locResetButton
    case locAlertDeleteMCPMessage
    case locAlertDeleteSkillMessage
    case locDeleteChatsConfirmMessage
    case locInstalledCount
    case locArchiveNow
    case locArchiveInactiveDays
    case locArchiveInactive
    case locBulkArchiveHelp
    case locClearAppCache
    case locQuotaWarning
    case locFindNewPath2
    case locRelink
    case locFindProjectFolder
    case locExportBackup
    case locRestoreBackup
    case locExportBackupPrompt
    case locRestoreBackupPrompt
    case locDeleteProjectHelp2
    case locCompressProjectHelp
    case locExportBackupHelp
    case locRestoreBackupHelp
    case locNone
    case locParamContext
    case locParamOutput
    case locParamReasoning
    case locParamTools
    case locParamPlan
    case locParamCost
    case locParamVariants
    case locParamProvider
    case locParamContextLength
    case locParamPlanMode
    case locSelectProviderToBrowseModels
    case locStartLocalAgentOrCheck
    case locArchive
    case locRestore
    case locNoUserCommands
    case locNoPluginsInstalled
    case locNoSkillsInstalledYet
    case locNoMCPServersConfigured

    // MARK: - Round 106 complete UI localization
    case locSearchLanguage
    case locOtherAnswer
    case locCaptchaVerification
    case locCaptchaInstruction
    case locChooseSavedWebLogin
    case locChangeLoginSession
    case locDetectedCount
    case locDetectionFailed
    case locDetectModels
    case locDetectModelsHelp
    case locRefreshEffortHelp
    case locRemoveWebProvider
    case locRemoveWebProviderConfirm
    case locSavedSessionDeleted
    case locDetectedModelsCount
    case locDetectedModels
    case locHideDetectedModels
    case locShowDetectedModels
    case locRemoveUnavailableDetection
    case locEffort
    case locNoEffort
    case locParams
    case locEffortNotDetected
    case locSelectorAvailable
    case locInAppBrowser
    case locBuiltInBrowserDetection
    case locBrowserDetectionHelp
    case locFastDOMDetectionHelp
    case locAskMyCoderAutoFree
    case locAskMyCoderAutoFreeHelp
    case locSaveSessionModels
    case locDetectModelsFirst
    case locNoSelectorFound
    case locNoModelsFound
    case locNoReadablePageText
    case locAIDetectionFailed
    case locNoModelNamesReturned
    case locAICandidateVerification
    case locProviderMetadata
    case locNoModelMetadata
    case locVisionInput
    case locImageGeneration
    case locEffortLevels
    case locManualMetadata
    case locResetMetadata
    case locLiveWebProfile
    case locNoParameterControls
    case locDetectedDefaults
    case locDetectedLabels
    case locTemperature
    case locMaxTokens
    case locTopP
    case locSystemPromptOverride
    case locBlankValuesProviderDefaults
    case locResetParameters
    case locSaveParameters
    case locUseNumericParameters
    case locTemperatureRange
    case locMaxTokensRange
    case locTopPRange
    case locSortModels
    case locFilterModels
    case locNoModelsMatchFilter
    case locModelsCountOf
    case locAllModels
    case locModelCount
    case locAvailableCount
    case locProviderParameters
    case locChooseFromList
    case locFreeModelsPrivacy
    case locLiveFreeModels
    case locNoEligibleFreeModels
    case locSwitchFreeModel
    case locUnlockSelectedModel
    case locLockSelectedModel
    case locModelLocked
    case locAutomaticFallbackEnabled
    case locModelLockedDescription
    case locAutomaticFallbackDescription
    case locSystemPromptSentBeforeRequest
    case locSavePrompt
    case locRefreshCatalog
    case locRefreshing
    case locUpdated
    case locEndpoint
    case locProtocol
    case locAccess
    case locFallback
    case locAnonymousNoKey
    case locRateLimitOrFailures
    case locOpenCodeZenDescription
    case locOnlineFreeModels
    case locOfflineCatalogUnavailable
    case locLoadingLiveCatalog
    case locFreeBadge
    case locStorageImportReplace
    case locStorageImportWarning
    case locStorageExportConfiguration
    case locStorageImportConfiguration
    case locCancelDeletion
    case locProjectRegistryDeletionWarning
    case locOK
    case locAllWorkspaces
    case locProjectFiles
    case locSearchTasks
    case locCollapseWorkspaces
    case locExpandWorkspaces
    case locWorkspaceActions
    case locSortWorkspaces
    case locHideWorkspaceSearch
    case locShowWorkspaceSearch
    case locShowGrid
    case locShowList
    case locCopy
    case locCut
    case locPaste
    case locSelectAll
    case locTemplates
    case locEffortValue
    case locCloseModelParameters
    case locSortName
    case locSortContext
    case locSortReasoning
    case locSortTools
    case locProviderNameExample
    case locProviderNameOptional
    case locEndpointExample
    case locContextValue
    case locLock
    case locUnlock
    case locReplaceAppConfiguration
    case locDeletingProjectData
    case locProjectDatabaseCorrupted
    case locNoBackupFound
    case locDatabaseRestored
    case locRestoreFailed
    case locIntegrityCheckFailed
    case locProjectPathPlaceholder
    case locChooseProjectFolder
    case locActions
    case locFreeModelRateLimitMessage
    case locFreeModelSwitchedMessage
    case locTaskCompleteMessage
    case locGitOperation
    case locPreviousModel
    case locAnotherFreeModel
    case locProviderError
    case locFreeModelRateLimited
    case locServerDisconnected
    case locServerConnected
    case locSessionBusy
    case locNewBranchName
    case locFileAttached
    case locFilesAttached
    case locPhotoAttached
    case locPhotosAttached
    case locCookiesCount
    case locWebModelsFoundCount
    case locApiEndpointURL
    case locInvalidEndpoint
    case locNoZenKeyDescription
    case locOpenCodeZen
    case locMessagesCount
    case locCustomProviders
    case locBuiltInProviders
    case locAddOrSelectOpenCodeZen
    case locOpenCodeZenApiKeyOptional
    case locSecretKeyPlaceholder
    case locFreeModelSwitched
    case locTaskComplete
    case locResponseStopped
    case locLocalAgentConnectionLost
    case locConnectedLocalAgent
    case locSessionBusyMessage
    case locFind
    case locActive
    case locClear
    case locHide
    case locShow
}

enum AppLocalization {
    static func string(forEnglish english: String, language: AppLanguage) -> String {
        if let key = translations.first(where: { $0.value["en"] == english }).flatMap({ AppLocalizationKey(rawValue: $0.key) }) {
            return string(key, language: language)
        }
        return english
    }

    static func string(_ key: AppLocalizationKey, language: AppLanguage) -> String {
        guard let entry = translations[key.rawValue] else { return key.rawValue }
        switch language {
        case .english: return entry["en"] ?? key.rawValue
        case .russian: return entry["ru"] ?? entry["en"] ?? key.rawValue
        case .spanish: return entry["es"] ?? entry["en"] ?? key.rawValue
        case .french: return entry["fr"] ?? entry["en"] ?? key.rawValue
        case .german: return entry["de"] ?? entry["en"] ?? key.rawValue
        case .chineseSimplified: return entry["zh"] ?? entry["en"] ?? key.rawValue
        case .japanese: return entry["ja"] ?? entry["en"] ?? key.rawValue
        case .korean: return entry["ko"] ?? entry["en"] ?? key.rawValue
        case .portuguese: return entry["pt"] ?? entry["en"] ?? key.rawValue
        case .arabic: return entry["ar"] ?? entry["en"] ?? key.rawValue
        }
    }

    static func settingsTabName(_ tab: SettingsTab, language: AppLanguage) -> String {
        switch tab {
        case .general: return string(.settingsTabGeneral, language: language)
        case .codePreview: return string(.settingsTabCodePreview, language: language)
        case .modelSettings: return string(.settingsTabModelSettings, language: language)
        case .providers: return string(.settingsTabProviders, language: language)
        case .skills: return string(.settingsTabSkills, language: language)
        case .mcpServers: return string(.settingsTabMCPServers, language: language)
        case .plugins: return string(.settingsTabPlugins, language: language)
        case .commands: return string(.settingsTabCommands, language: language)
        case .indexing: return string(.settingsTabIndexing, language: language)
        case .storage:
            switch language {
            case .russian: return "Хранилище"
            case .spanish: return "Almacenamiento"
            case .french: return "Stockage"
            case .german: return "Speicher"
            case .chineseSimplified: return "存储"
            case .japanese: return "ストレージ"
            case .korean: return "저장소"
            case .portuguese: return "Armazenamento"
            case .arabic: return "التخزين"
            case .english: return "Storage"
            }
        case .usage: return string(.settingsTabUsage, language: language)
        }
    }

    static let translations: [String: [String: String]] = [
        "locSelect": ["en": "Select", "ru": "Выбрать", "es": "Seleccionar", "fr": "Sélectionner", "de": "Auswählen", "zh": "选择", "ja": "選択", "ko": "선택", "pt": "Selecionar", "ar": "تحديد"],
        "locRemoveProvider": ["en": "Remove provider", "ru": "Удалить провайдер", "es": "Eliminar proveedor", "fr": "Supprimer le fournisseur", "de": "Anbieter entfernen", "zh": "移除提供商", "ja": "プロバイダーを削除", "ko": "공급자 제거", "pt": "Remover provedor", "ar": "إزالة الموفر"],
        "locParameters": ["en": "Parameters", "ru": "Параметры", "es": "Parámetros", "fr": "Paramètres", "de": "Parameter", "zh": "参数", "ja": "パラメーター", "ko": "매개변수", "pt": "Parâmetros", "ar": "المعلمات"],
        "locOpenProject": ["en": "Open Project…", "ru": "Открыть проект…", "es": "Abrir proyecto…", "fr": "Ouvrir le projet…", "de": "Projekt öffnen…", "zh": "打开项目…", "ja": "プロジェクトを開く…", "ko": "프로젝트 열기…", "pt": "Abrir projeto…", "ar": "فتح المشروع…"],
        "locNoWorkspaces": ["en": "No workspaces", "ru": "Нет рабочих областей", "es": "Sin áreas de trabajo", "fr": "Aucun espace de travail", "de": "Keine Arbeitsbereiche", "zh": "暂无工作区", "ja": "ワークスペースなし", "ko": "작업 공간 없음", "pt": "Sem áreas de trabalho", "ar": "لا توجد مساحات عمل"],
        "locNewTask": ["en": "New task", "ru": "Новая задача", "es": "Nueva tarea", "fr": "Nouvelle tâche", "de": "Neue Aufgabe", "zh": "新任务", "ja": "新しいタスク", "ko": "새 작업", "pt": "Nova tarefa", "ar": "مهمة جديدة"],
        "locFilterWorkspaces": ["en": "Filter workspaces", "ru": "Фильтр рабочих областей", "es": "Filtrar áreas de trabajo", "fr": "Filtrer les espaces de travail", "de": "Arbeitsbereiche filtern", "zh": "筛选工作区", "ja": "ワークスペースをフィルター", "ko": "작업 공간 필터", "pt": "Filtrar áreas de trabalho", "ar": "تصفية مساحات العمل"],
        "locCopyInfo": ["en": "Copy info", "ru": "Копировать инфо", "es": "Copiar información", "fr": "Copier les infos", "de": "Info kopieren", "zh": "复制信息", "ja": "情報をコピー", "ko": "정보 복사", "pt": "Copiar informações", "ar": "نسخ المعلومات"],
        "locCollapse": ["en": "Collapse", "ru": "Свернуть", "es": "Colapsar", "fr": "Réduire", "de": "Einklappen", "zh": "折叠", "ja": "折りたたむ", "ko": "접기", "pt": "Recolher", "ar": "طي"],
        "locYear": ["en": "1 year", "ru": "1 год", "es": "1 año", "fr": "1 an", "de": "1 Jahr", "zh": "1 年", "ja": "1年", "ko": "1년", "pt": "1 ano", "ar": "1 سنة"],
        "locDays": ["en": "14 days", "ru": "14 дней", "es": "14 días", "fr": "14 jours", "de": "14 Tage", "zh": "14 天", "ja": "14日", "ko": "14일", "pt": "14 dias", "ar": "14 يومًا"],
        "loc180Days": ["en": "180 days", "ru": "180 дней", "es": "180 días", "fr": "180 jours", "de": "180 Tage", "zh": "180 天", "ja": "180日", "ko": "180일", "pt": "180 dias", "ar": "180 يومًا"],
        "locDays1": ["en": "3 days", "ru": "3 дня", "es": "3 días", "fr": "3 jours", "de": "3 Tage", "zh": "3 天", "ja": "3日", "ko": "3일", "pt": "3 dias", "ar": "3 أيام"],
        "locDays2": ["en": "30 days", "ru": "30 дней", "es": "30 días", "fr": "30 jours", "de": "30 Tage", "zh": "30 天", "ja": "30日", "ko": "30일", "pt": "30 dias", "ar": "30 يومًا"],
        "locDays3": ["en": "7 days", "ru": "7 дней", "es": "7 días", "fr": "7 jours", "de": "7 Tage", "zh": "7 天", "ja": "7日", "ko": "7일", "pt": "7 dias", "ar": "7 أيام"],
        "locDays4": ["en": "90 days", "ru": "90 дней", "es": "90 días", "fr": "90 jours", "de": "90 Tage", "zh": "90 天", "ja": "90日", "ko": "90일", "pt": "90 dias", "ar": "90 يومًا"],
        "locApiKey": ["en": "API Key", "ru": "API-ключ", "es": "Clave API", "fr": "Clé API", "de": "API-Schlüssel", "zh": "API 密钥", "ja": "APIキー", "ko": "API 키", "pt": "Chave API", "ar": "مفتاح API"],
        "locActiveChats": ["en": "Active chats", "ru": "Активные чаты", "es": "Chats activos", "fr": "Conversations actives", "de": "Aktive Chats", "zh": "活跃聊天", "ja": "アクティブチャット", "ko": "활성 채팅", "pt": "Conversas ativas", "ar": "المحادثات النشطة"],
        "locActiveDays": ["en": "Active days", "ru": "Активные дни", "es": "Días activos", "fr": "Jours actifs", "de": "Aktive Tage", "zh": "活跃天数", "ja": "アクティブ日数", "ko": "활성 일수", "pt": "Dias ativos", "ar": "الأيام النشطة"],
        "locAdd": ["en": "Add", "ru": "Добавить", "es": "Agregar", "fr": "Ajouter", "de": "Hinzufügen", "zh": "添加", "ja": "追加", "ko": "추가", "pt": "Adicionar", "ar": "إضافة"],
        "locAddAnotherAccount": ["en": "+ Account", "ru": "+ Аккаунт", "es": "+ Cuenta", "fr": "+ Compte", "de": "+ Konto", "zh": "+ 账号", "ja": "+ アカウント", "ko": "+ 계정", "pt": "+ Conta", "ar": "+ حساب"],
        "locAddFilesMycodercommands": ["en": "Add .md files to ~/.mycoder/commands", "ru": "Добавьте .md файлы в ~/.mycoder/commands", "es": "Agregar archivos .md a ~/.mycoder/commands", "fr": "Ajouter des fichiers .md dans ~/.mycoder/commands", "de": ".md-Dateien zu ~/.mycoder/commands hinzufügen", "zh": "将 .md 文件添加到 ~/.mycoder/commands", "ja": "~/.mycoder/commands に .md ファイルを追加", "ko": "~/.mycoder/commands에 .md 파일 추가", "pt": "Adicionar arquivos .md em ~/.mycoder/commands", "ar": "إضافة ملفات .md إلى ~/.mycoder/commands"],
        "locAddProvider": ["en": "Add Provider", "ru": "Добавить провайдер", "es": "Agregar proveedor", "fr": "Ajouter un fournisseur", "de": "Anbieter hinzufügen", "zh": "添加提供商", "ja": "プロバイダーを追加", "ko": "공급자 추가", "pt": "Adicionar provedor", "ar": "إضافة مزود"],
        "locAddProvider1": ["en": "Add provider", "ru": "Добавить провайдер", "es": "Agregar proveedor", "fr": "Ajouter un fournisseur", "de": "Anbieter hinzufügen", "zh": "添加提供商", "ja": "プロバイダーを追加", "ko": "공급자 추가", "pt": "Adicionar provedor", "ar": "إضافة مزود"],
        "locAdjustTheDefaultFontSizeUsedCodePreviews": ["en": "Adjust the default font size used by code previews.", "ru": "Настройте размер шрифта по умолчанию для предварительного просмотра кода.", "es": "Ajustar el tamaño de fuente predeterminado para vistas previas de código.", "fr": "Ajuster la taille de police par défaut pour les aperçus de code.", "de": "Standard-Schriftgröße für Code-Vorschauen anpassen.", "zh": "调整代码预览使用的默认字体大小。", "ja": "コードプレビューのデフォルトフォントサイズを調整します。", "ko": "코드 미리보기에 사용되는 기본 글꼴 크기를 조정합니다.", "pt": "Ajustar o tamanho de fonte padrão usado nas pré-visualizações de código.", "ar": "ضبط حجم الخط الافتراضي المستخدم في معاينات الكود."],
        "locAppUsage": ["en": "App usage", "ru": "Использование приложения", "es": "Uso de la aplicación", "fr": "Utilisation de l'application", "de": "App-Nutzung", "zh": "应用使用情况", "ja": "アプリの使用状況", "ko": "앱 사용량", "pt": "Uso do aplicativo", "ar": "استخدام التطبيق"],
        "locArchiveAfter": ["en": "Archive after:", "ru": "Архивировать через:", "es": "Archivar después de:", "fr": "Archiver après :", "de": "Archivieren nach:", "zh": "归档时间：", "ja": "アーカイブ期限：", "ko": "보관 기간:", "pt": "Arquivar após:", "ar": "أرشفة بعد:"],
        "locArchived": ["en": "Archived", "ru": "Архивировано", "es": "Archivado", "fr": "Archivé", "de": "Archiviert", "zh": "已归档", "ja": "アーカイブ済み", "ko": "보관됨", "pt": "Arquivado", "ar": "مؤرشف"],
        "locArchivedProjects": ["en": "Archived projects", "ru": "Архивированные проекты", "es": "Proyectos archivados", "fr": "Projets archivés", "de": "Archivierte Projekte", "zh": "已归档项目", "ja": "アーカイブ済みプロジェクト", "ko": "보관된 프로젝트", "pt": "Projetos arquivados", "ar": "المشاريع المؤرشفة"],
        "locAutoarchive": ["en": "Auto-archive", "ru": "Автоархивация", "es": "Autoarchivar", "fr": "Archivage automatique", "de": "Automatisch archivieren", "zh": "自动归档", "ja": "自動アーカイブ", "ko": "자동 보관", "pt": "Arquivamento automático", "ar": "أرشفة تلقائية"],
        "locAutomaticallyIndexAnyNewFoldersWithFewerThan500": ["en": "Automatically index any new folders with fewer than 50,000 files.", "ru": "Автоматически индексировать новые папки с менее чем 50 000 файлов.", "es": "Indexar automáticamente carpetas nuevas con menos de 50,000 archivos.", "fr": "Indexer automatiquement les nouveaux dossiers contenant moins de 50 000 fichiers.", "de": "Automatisch neue Ordner mit weniger als 50.000 Dateien indexieren.", "zh": "自动索引少于 50,000 个文件的新文件夹。", "ja": "50,000 ファイル未満の新しいフォルダを自動的にインデックスします。", "ko": "50,000개 미만 파일이 있는 새 폴더를 자동으로 인덱싱합니다.", "pt": "Indexar automaticamente pastas novas com menos de 50.000 arquivos.", "ar": "فهرسة تلقائية لأي مجلدات جديدة تحتوي على أقل من 50,000 ملف."],
        "locAutomaticallyIndexRepositoriesSpeedGrepSearches": ["en": "Automatically index repositories to speed up Grep searches. All data is stored locally.", "ru": "Автоматически индексировать репозитории для ускорения поиска Grep. Все данные хранятся локально.", "es": "Indexar automáticamente repositorios para acelerar las búsquedas de Grep. Todos los datos se almacenan localmente.", "fr": "Indexer automatiquement les dépôts pour accélérer les recherches Grep. Toutes les données sont stockées localement.", "de": "Repositorys automatisch indexieren, um Grep-Suchen zu beschleunigen. Alle Daten werden lokal gespeichert.", "zh": "自动索引仓库以加速 Grep 搜索。所有数据都存储在本地。", "ja": "リポジトリを自動的にインデックスして Grep 検索を高速化します。すべてのデータはローカルに保存されます。", "ko": "저장소를 자동으로 인덱싱하여 Grep 검색 속도를 높입니다. 모든 데이터는 로컬에 저장됩니다.", "pt": "Indexar automaticamente repositórios para acelerar pesquisas Grep. Todos os dados são armazenados localmente.", "ar": "فهرسة المستودعات تلقائيًا لتسريع عمليات بحث Grep. يتم تخزين جميع البيانات محليًا."],
        "locBack": ["en": "Back", "ru": "Назад", "es": "Atrás", "fr": "Retour", "de": "Zurück", "zh": "返回", "ja": "戻る", "ko": "뒤로", "pt": "Voltar", "ar": "رجوع"],
        "locBaseUrl": ["en": "Base URL", "ru": "Базовый URL", "es": "URL base", "fr": "URL de base", "de": "Basis-URL", "zh": "基础 URL", "ja": "ベースURL", "ko": "기본 URL", "pt": "URL base", "ar": "عنوان URL الأساسي"],
        "locBrowseTheLibraryAndInstallMcpServersOneClickCon": ["en": "Browse the library and install MCP servers in one click. Configurations are saved to ~/.mycoder/mcp.json.", "ru": "Просматривайте библиотеку и устанавливайте MCP-серверы в один клик. Конфигурации сохраняются в ~/.mycoder/mcp.json.", "es": "Explore la biblioteca e instale servidores MCP con un clic. Las configuraciones se guardan en ~/.mycoder/mcp.json.", "fr": "Parcourez la bibliothèque et installez des serveurs MCP en un clic. Les configurations sont enregistrées dans ~/.mycoder/mcp.json.", "de": "Durchsuchen Sie die Bibliothek und installieren Sie MCP-Server mit einem Klick. Konfigurationen werden in ~/.mycoder/mcp.json gespeichert.", "zh": "浏览库并一键安装 MCP 服务器。配置保存到 ~/.mycoder/mcp.json。", "ja": "ライブラリを閲覧してMCPサーバーをワンクリックでインストール。設定は ~/.mycoder/mcp.json に保存されます。", "ko": "라이브러리를 탐색하고 MCP 서버를 원클릭으로 설치합니다. 구성은 ~/.mycoder/mcp.json에 저장됩니다.", "pt": "Navegue pela biblioteca e instale servidores MCP com um clique. As configurações são salvas em ~/.mycoder/mcp.json.", "ar": "تصفح المكتبة وتثبيت خوادم MCP بنقرة واحدة. يتم حفظ الإعدادات في ~/.mycoder/mcp.json."],
        "locBrowseTheLibraryAndInstallSkillsOneClickManageL": ["en": "Browse the library and install skills in one click, or manage local skills under ~/.mycoder/skills.", "ru": "Просматривайте библиотеку и устанавливайте навыки в один клик, или управляйте локальными навыками в ~/.mycoder/skills.", "es": "Explore la biblioteca e instale habilidades con un clic, o administre habilidades locales en ~/.mycoder/skills.", "fr": "Parcourez la bibliothèque et installez des compétences en un clic, ou gérez les compétences locales dans ~/.mycoder/skills.", "de": "Durchsuchen Sie die Bibliothek und installieren Sie Skills mit einem Klick oder verwalten Sie lokale Skills unter ~/.mycoder/skills.", "zh": "浏览库并一键安装技能，或在 ~/.mycoder/skills 下管理本地技能。", "ja": "ライブラリを閲覧してスキルをワンクリックでインストール、または ~/.mycoder/skills でローカルスキルを管理。", "ko": "라이브러리를 탐색하고 스킬을 원클릭으로 설치하거나 ~/.mycoder/skills에서 로컬 스킬을 관리합니다.", "pt": "Navegue pela biblioteca e instale habilidades com um clique, ou gerencie habilidades locais em ~/.mycoder/skills.", "ar": "تصفح المكتبة وتثبيت المهارات بنقرة واحدة، أو إدارة المهارات المحلية ضمن ~/.mycoder/skills."],
        "locModel": ["en": "By model", "ru": "По модели", "es": "Por modelo", "fr": "Par modèle", "de": "Nach Modell", "zh": "按模型", "ja": "モデル別", "ko": "모델별", "pt": "Por modelo", "ar": "حسب النموذج"],
        "locCannotPreviewImage": ["en": "Cannot preview image", "ru": "Не удалось загрузить изображение", "es": "No se puede previsualizar la imagen", "fr": "Impossible de prévisualiser l'image", "de": "Bildvorschau nicht möglich", "zh": "无法预览图片", "ja": "画像をプレビューできません", "ko": "이미지를 미리볼 수 없습니다", "pt": "Não é possível visualizar a imagem", "ar": "لا يمكن معاينة الصورة"],
        "locChanges": ["en": "Changes", "ru": "Изменения", "es": "Cambios", "fr": "Modifications", "de": "Änderungen", "zh": "更改", "ja": "変更", "ko": "변경 사항", "pt": "Alterações", "ar": "التغييرات"],
        "locCleanup": ["en": "Cleanup", "ru": "Очистка", "es": "Limpieza", "fr": "Nettoyage", "de": "Bereinigung", "zh": "清理", "ja": "クリーンアップ", "ko": "정리", "pt": "Limpeza", "ar": "التنظيف"],
        "locClearAll": ["en": "Clear all", "ru": "Очистить все", "es": "Borrar todo", "fr": "Tout effacer", "de": "Alle löschen", "zh": "清除全部", "ja": "すべてクリア", "ko": "모두 지우기", "pt": "Limpar tudo", "ar": "مسح الكل"],
        "locClose": ["en": "Close", "ru": "Закрыть", "es": "Cerrar", "fr": "Fermer", "de": "Schließen", "zh": "关闭", "ja": "閉じる", "ko": "닫기", "pt": "Fechar", "ar": "إغلاق"],
        "locCodeFontSize": ["en": "Code font size", "ru": "Размер шрифта кода", "es": "Tamaño de fuente del código", "fr": "Taille de police du code", "de": "Code-Schriftgröße", "zh": "代码字体大小", "ja": "コードフォントサイズ", "ko": "코드 글꼴 크기", "pt": "Tamanho da fonte do código", "ar": "حجم خط الكود"],
        "locCodePreview": ["en": "Code preview", "ru": "Предпросмотр кода", "es": "Vista previa de código", "fr": "Aperçu du code", "de": "Code-Vorschau", "zh": "代码预览", "ja": "コードプレビュー", "ko": "코드 미리보기", "pt": "Pré-visualização de código", "ar": "معاينة الكود"],
        "locCodebase": ["en": "Codebase", "ru": "Кодовая база", "es": "Código fuente", "fr": "Base de code", "de": "Codebasis", "zh": "代码库", "ja": "コードベース", "ko": "코드베이스", "pt": "Base de código", "ar": "قاعدة الكود"],
        "locCommands": ["en": "Commands", "ru": "Команды", "es": "Comandos", "fr": "Commandes", "de": "Befehle", "zh": "命令", "ja": "コマンド", "ko": "명령", "pt": "Comandos", "ar": "الأوامر"],
        "locCommandsSubtitle": ["en": "Built-in commands are always available. Create custom commands that inject a reusable template into your message.", "ru": "Встроенные команды доступны всегда. Создавайте собственные команды, которые вставляют переиспользуемый шаблон в ваше сообщение.", "es": "Los comandos integrados siempre están disponibles. Cree comandos personalizados que insertan una plantilla reutilizable en su mensaje.", "fr": "Les commandes intégrées sont toujours disponibles. Créez des commandes personnalisées qui insèrent un modèle réutilisable dans votre message.", "de": "Integrierte Befehle sind immer verfügbar. Erstellen Sie benutzerdefinierte Befehle, die eine wiederverwendbare Vorlage in Ihre Nachricht einfügen.", "zh": "内置命令始终可用。创建自定义命令，将可复用模板插入到您的消息中。", "ja": "組み込みコマンドは常に利用できます。再利用可能なテンプレートをメッセージに挿入するカスタムコマンドを作成します。", "ko": "내장 명령은 항상 사용할 수 있습니다. 재사용 가능한 템플릿을 메시지에 삽입하는 사용자 지정 명령을 만듭니다.", "pt": "Os comandos integrados estão sempre disponíveis. Crie comandos personalizados que inserem um modelo reutilizável na sua mensagem.", "ar": "الأوامر المدمجة متاحة دائمًا. أنشئ أوامر مخصصة تُدرج قالبًا قابلًا لإعادة الاستخدام في رسالتك."],
        "locBuiltInCommands": ["en": "Built-in", "ru": "Встроенные", "es": "Integrados", "fr": "Intégrées", "de": "Integriert", "zh": "内置", "ja": "組み込み", "ko": "내장", "pt": "Integrados", "ar": "مدمجة"],
        "locCustomCommands": ["en": "Custom commands", "ru": "Пользовательские команды", "es": "Comandos personalizados", "fr": "Commandes personnalisées", "de": "Benutzerdefinierte Befehle", "zh": "自定义命令", "ja": "カスタムコマンド", "ko": "사용자 지정 명령", "pt": "Comandos personalizados", "ar": "أوامر مخصصة"],
        "locNewCommand": ["en": "New command", "ru": "Новая команда", "es": "Nuevo comando", "fr": "Nouvelle commande", "de": "Neuer Befehl", "zh": "新命令", "ja": "新しいコマンド", "ko": "새 명령", "pt": "Novo comando", "ar": "أمر جديد"],
        "locAddCommand": ["en": "Add command", "ru": "Добавить команду", "es": "Agregar comando", "fr": "Ajouter une commande", "de": "Befehl hinzufügen", "zh": "添加命令", "ja": "コマンドを追加", "ko": "명령 추가", "pt": "Adicionar comando", "ar": "إضافة أمر"],
        "locEditCommand": ["en": "Edit command", "ru": "Редактировать команду", "es": "Editar comando", "fr": "Modifier la commande", "de": "Befehl bearbeiten", "zh": "编辑命令", "ja": "コマンドを編集", "ko": "명령 편집", "pt": "Editar comando", "ar": "تعديل الأمر"],
        "locCommandName": ["en": "Command name", "ru": "Имя команды", "es": "Nombre del comando", "fr": "Nom de la commande", "de": "Befehlsname", "zh": "命令名称", "ja": "コマンド名", "ko": "명령 이름", "pt": "Nome do comando", "ar": "اسم الأمر"],
        "locCommandTemplate": ["en": "Template", "ru": "Шаблон", "es": "Plantilla", "fr": "Modèle", "de": "Vorlage", "zh": "模板", "ja": "テンプレート", "ko": "템플릿", "pt": "Modelo", "ar": "قالب"],
        "locCommandPlaceholdersHint": ["en": "Use {{input}} in the template to insert the text typed after the command.", "ru": "Используйте {{input}} в шаблоне, чтобы вставить текст, введённый после команды.", "es": "Use {{input}} en la plantilla para insertar el texto escrito después del comando.", "fr": "Utilisez {{input}} dans le modèle pour insérer le texte saisi après la commande.", "de": "Verwenden Sie {{input}} in der Vorlage, um den nach dem Befehl eingegebenen Text einzufügen.", "zh": "在模板中使用 {{input}} 来插入命令后输入的文本。", "ja": "テンプレートで {{input}} を使用すると、コマンドの後に入力したテキストが挿入されます。", "ko": "템플릿에서 {{input}}을 사용하여 명령 뒤에 입력한 텍스트를 삽입하세요.", "pt": "Use {{input}} no modelo para inserir o texto digitado após o comando.", "ar": "استخدم {{input}} في القالب لإدراج النص المكتوب بعد الأمر."],
        "locCommandBodyEmptyWarning": ["en": "Template body is empty.", "ru": "Шаблон пуст.", "es": "La plantilla está vacía.", "fr": "Le modèle est vide.", "de": "Die Vorlage ist leer.", "zh": "模板为空。", "ja": "テンプレートが空です。", "ko": "템플릿이 비어 있습니다.", "pt": "O modelo está vazio.", "ar": "القالب فارغ."],
        "locDeleteCommandConfirmation": ["en": "Delete command /{0}?", "ru": "Удалить команду /{0}?", "es": "¿Eliminar el comando /{0}?", "fr": "Supprimer la commande /{0} ?", "de": "Befehl /{0} löschen?", "zh": "删除命令 /{0}？", "ja": "コマンド /{0} を削除しますか？", "ko": "/{0} 명령을 삭제하시겠습니까?", "pt": "Excluir comando /{0}?", "ar": "حذف الأمر /{0}؟"],
        "locConfiguration": ["en": "Configuration", "ru": "Конфигурация", "es": "Configuración", "fr": "Configuration", "de": "Konfiguration", "zh": "配置", "ja": "設定", "ko": "구성", "pt": "Configuração", "ar": "الإعدادات"],
        "locConfigureModelProvidersAndManageAvailableModels": ["en": "Configure model providers and manage available models.", "ru": "Настройте провайдеров моделей и управ доступными моделями.", "es": "Configure proveedores de modelos y gestione los modelos disponibles.", "fr": "Configurez les fournisseurs de modèles et gérez les modèles disponibles.", "de": "Modellanbieter konfigurieren und verfügbare Modelle verwalten.", "zh": "配置模型提供商并管理可用模型。", "ja": "モデルプロバイダーを設定し、利用可能なモデルを管理します。", "ko": "모델 공급자를 구성하고 사용 가능한 모델을 관리합니다.", "pt": "Configure provedores de modelos e gerencie os modelos disponíveis.", "ar": "تكوين مزودي النماذج وإدارة النماذج المتاحة."],
        "locConfirmAndAdd": ["en": "Confirm and add", "ru": "Подтвердить и добавить", "es": "Confirmar y agregar", "fr": "Confirmer et ajouter", "de": "Bestätigen und hinzufügen", "zh": "确认并添加", "ja": "確認して追加", "ko": "확인 및 추가", "pt": "Confirmar e adicionar", "ar": "تأكيد والإضافة"],
        "locConnectTheLocalAgentAddCustomProvider": ["en": "Connect the local agent or add a custom provider", "ru": "Подключите локальный агент или добавьте пользовательский провайдер", "es": "Conecte el agente local o agregue un proveedor personalizado", "fr": "Connectez l'agent local ou ajoutez un fournisseur personnalisé", "de": "Verbinden Sie den lokalen Agenten oder fügen Sie einen benutzerdefinierten Anbieter hinzu", "zh": "连接本地代理或添加自定义提供商", "ja": "ローカルエージェントを接続するか、カスタムプロバイダーを追加", "ko": "로컬 에이전트를 연결하거나 사용자 정의 공급자를 추가하세요", "pt": "Conecte o agente local ou adicione um provedor personalizado", "ar": "اتصل بالوكيل المحلي أو أضف مزودًا مخصصًا"],
        "locConnectTheLocalAgentAddCustomProviderGetStarted": ["en": "Connect the local agent or add a custom provider to get started.", "ru": "Подключите локальный агент или добавьте пользовательский провайдер для начала.", "es": "Conecte el agente local o agregue un proveedor personalizado para comenzar.", "fr": "Connectez l'agent local ou ajoutez un fournisseur personnalisé pour commencer.", "de": "Verbinden Sie den lokalen Agenten oder fügen Sie einen benutzerdefinierten Anbieter hinzu, um zu beginnen.", "zh": "连接本地代理或添加自定义提供商以开始使用。", "ja": "ローカルエージェントを接続するか、カスタムプロバイダーを追加して開始します。", "ko": "로컬 에이전트를 연결하거나 사용자 정의 공급자를 추가하여 시작하세요.", "pt": "Conecte o agente local ou adicione um provedor personalizado para começar.", "ar": "اتصل بالوكيل المحلي أو أضف مزودًا مخصصًا للبدء."],
        "locConnectLocalAgentInstanceAnotherHost": ["en": "Connect to a local agent instance on another host.", "ru": "Подключиться к локальному агенту на другом хосте.", "es": "Conectarse a una instancia de agente local en otro host.", "fr": "Se connecter à une instance d'agent local sur un autre hôte.", "de": "Mit einer lokalen Agenten-Instanz auf einem anderen Host verbinden.", "zh": "连接到另一台主机上的本地代理实例。", "ja": "別のホスト上のローカルエージェントインスタンスに接続。", "ko": "다른 호스트의 로컬 에이전트 인스턴스에 연결합니다.", "pt": "Conectar a uma instância de agente local em outro host.", "ar": "الاتصال بinstance وكيل מקומי على مضيف آخر."],
        "locCopyAll": ["en": "Copy All", "ru": "Копировать все", "es": "Copiar todo", "fr": "Tout copier", "de": "Alles kopieren", "zh": "全部复制", "ja": "すべてコピー", "ko": "모두 복사", "pt": "Copiar tudo", "ar": "نسخ الكل"],
        "locRawText": ["en": "Raw text", "ru": "Исходный текст", "es": "Texto sin formato", "fr": "Texte brut", "de": "Rohtext", "zh": "纯文本", "ja": "プレーンテキスト", "ko": "원시 텍스트", "pt": "Texto sem formatação", "ar": "نص خام"],
        "locFormatted": ["en": "Formatted", "ru": "Форматированный", "es": "Con formato", "fr": "Formaté", "de": "Formatiert", "zh": "格式化", "ja": "書式付き", "ko": "서식 있음", "pt": "Formatado", "ar": "منسق"],
        "locCreate": ["en": "Create PR", "ru": "Создать PR", "es": "Crear PR", "fr": "Créer PR", "de": "PR erstellen", "zh": "创建 PR", "ja": "PRを作成", "ko": "PR 생성", "pt": "Criar PR", "ar": "إنشاء PR"],
        "locCreateProject": ["en": "Create Project", "ru": "Создать проект", "es": "Crear proyecto", "fr": "Créer un projet", "de": "Projekt erstellen", "zh": "新建项目", "ja": "プロジェクトを作成", "ko": "프로젝트 생성", "pt": "Criar projeto", "ar": "إنشاء مشروع"],
        "locCreatePullRequest": ["en": "Create Pull Request", "ru": "Создать Pull Request", "es": "Crear Pull Request", "fr": "Créer une Pull Request", "de": "Pull Request erstellen", "zh": "创建 Pull Request", "ja": "Pull Requestを作成", "ko": "Pull Request 생성", "pt": "Criar Pull Request", "ar": "إنشاء طلب سحب"],
        "locCustom": ["en": "Custom", "ru": "Пользовательский", "es": "Personalizado", "fr": "Personnalisé", "de": "Benutzerdefiniert", "zh": "自定义", "ja": "カスタム", "ko": "사용자 정의", "pt": "Personalizado", "ar": "مخصص"],
        "locCustomModels": ["en": "Custom models", "ru": "Пользовательские модели", "es": "Modelos personalizados", "fr": "Modèles personnalisés", "de": "Benutzerdefinierte Modelle", "zh": "自定义模型", "ja": "カスタムモデル", "ko": "사용자 정의 모델", "pt": "Modelos personalizados", "ar": "نماذج مخصصة"],
        "locDarkCodeTheme": ["en": "Dark code theme", "ru": "Тёмная тема кода", "es": "Tema de código oscuro", "fr": "Thème de code sombre", "de": "Dunkles Code-Theme", "zh": "深色代码主题", "ja": "ダークコードテーマ", "ko": "다크 코드 테마", "pt": "Tema de código escuro", "ar": "سمة الكود الداكنة"],
        "locDatabase": ["en": "Database", "ru": "База данных", "es": "Base de datos", "fr": "Base de données", "de": "Datenbank", "zh": "数据库", "ja": "データベース", "ko": "데이터베이스", "pt": "Base de dados", "ar": "قاعدة البيانات"],
        "locDatabaseSize": ["en": "Database size", "ru": "Размер базы данных", "es": "Tamaño de la base de datos", "fr": "Taille de la base de données", "de": "Datenbankgröße", "zh": "数据库大小", "ja": "データベースサイズ", "ko": "데이터베이스 크기", "pt": "Tamanho do banco de dados", "ar": "حجم قاعدة البيانات"],
        "locDeleteChatsOlderThan": ["en": "Delete chats older than:", "ru": "Удалить чаты старше:", "es": "Eliminar chats más antiguos de:", "fr": "Supprimer les conversations antérieures à :", "de": "Chats löschen, die älter sind als:", "zh": "删除早于以下时间的聊天：", "ja": "より古いチャットを削除：", "ko": "이전 채팅 삭제:", "pt": "Excluir conversas mais antigas que:", "ar": "حذف المحادثات الأقدم من:"],
        "locDescriptionOptional": ["en": "Description (optional)", "ru": "Описание (необязательно)", "es": "Descripción (opcional)", "fr": "Description (facultatif)", "de": "Beschreibung (optional)", "zh": "描述（可选）", "ja": "説明（任意）", "ko": "설명 (선택사항)", "pt": "Descrição (opcional)", "ar": "الوصف (اختياري)"],
        "locDetails": ["en": "Details", "ru": "Подробности", "es": "Detalles", "fr": "Détails", "de": "Details", "zh": "详情", "ja": "詳細", "ko": "세부 정보", "pt": "Detalhes", "ar": "التفاصيل"],
        "locDisableForLocalModelsProvidersThatDontNeedAuthe": ["en": "Disable for local models or providers that don't need authentication", "ru": "Отключить для локальных моделей или провайдеров, не требующих аутентификации", "es": "Desactivar para modelos locales o proveedores que no necesitan autenticación", "fr": "Désactiver pour les modèles locaux ou fournisseurs qui n'ont pas besoin d'authentification", "de": "Deaktivieren für lokale Modelle oder Anbieter, die keine Authentifizierung benötigen", "zh": "对不需要认证的本地模型或提供商禁用", "ja": "認証不要のローカルモデルやプロバイダーに対して無効化", "ko": "인증이 필요 없는 로컬 모델 또는 공급자에 대해 비활성화", "pt": "Desativar para modelos locais ou provedores que não precisam de autenticação", "ar": "تعطيل للنماذج المحلية أو المزودين الذين لا يحتاجون إلى مصادقة"],
        "locDisplayLineNumbersCodePreviews": ["en": "Display line numbers in code previews.", "ru": "Показывать номера строк в предпросмотре кода.", "es": "Mostrar números de línea en vistas previas de código.", "fr": "Afficher les numéros de ligne dans les aperçus de code.", "de": "Zeilennummern in Code-Vorschauen anzeigen.", "zh": "在代码预览中显示行号。", "ja": "コードプレビューに行番号を表示します。", "ko": "코드 미리보기에 줄 번호를 표시합니다.", "pt": "Exibir números de linha nas pré-visualizações de código.", "ar": "عرض أرقام الأسطر في معاينات الكود."],
        "locEdit": ["en": "Edit", "ru": "Редактировать", "es": "Editar", "fr": "Modifier", "de": "Bearbeiten", "zh": "编辑", "ja": "編集", "ko": "편집", "pt": "Editar", "ar": "تعديل"],
        "locEnableAgentCoderProtocol": ["en": "Enable Agent Coder Protocol", "ru": "Включить протокол Agent Coder", "es": "Habilitar Agent Coder Protocol", "fr": "Activer le protocole Agent Coder", "de": "Agent Coder Protocol aktivieren", "zh": "启用 Agent Coder Protocol", "ja": "Agent Coder Protocolを有効化", "ko": "Agent Coder Protocol 활성화", "pt": "Habilitar Agent Coder Protocol", "ar": "تفعيل بروتوكول وكيل المبرمج"],
        "locEnableAgentCoderProtocolForAutonomousCodingTask": ["en": "Enable Agent Coder Protocol for autonomous coding tasks", "ru": "Включить протокол Agent Coder для автономных задач кодирования", "es": "Habilitar Agent Coder Protocol para tareas de codificación autónomas", "fr": "Activer le protocole Agent Coder pour les tâches de codage autonomes", "de": "Agent Coder Protocol für autonome Codierungsaufgaben aktivieren", "zh": "为自主编码任务启用 Agent Coder Protocol", "ja": "自律コーディングタスクにAgent Coder Protocolを有効化", "ko": "자율 코딩 작업에 Agent Coder Protocol 활성화", "pt": "Habilitar Agent Coder Protocol para tarefas de codificação autônomas", "ar": "تفعيل بروتوكول وكيل المبرمج لمهام البرمجة المستقلة"],
        "locEnableFunctiontoolCallingSupport": ["en": "Enable function/tool calling support", "ru": "Включить поддержку вызова функций/инструментов", "es": "Habilitar soporte de llamadas de función/herramienta", "fr": "Activer le support des appels de fonctions/outils", "de": "Funktion/Tool-Aufruf-Unterstützung aktivieren", "zh": "启用函数/工具调用支持", "ja": "関数/ツール呼び出しサポートを有効化", "ko": "함수/도구 호출 지원 활성화", "pt": "Habilitar suporte a chamadas de função/ferramenta", "ar": "تفعيل دعم استدعاء الدوال/الأدوات"],
        "locEnableFunctiontoolCallingSupportForThisProvider": ["en": "Enable function/tool calling support for this provider", "ru": "Включить поддержку вызова функций/инструментов для этого провайдера", "es": "Habilitar soporte de llamadas de función/herramienta para este proveedor", "fr": "Activer le support des appels de fonctions/outils pour ce fournisseur", "de": "Funktion/Tool-Aufruf-Unterstützung für diesen Anbieter aktivieren", "zh": "为此提供商启用函数/工具调用支持", "ja": "このプロバイダーの関数/ツール呼び出しサポートを有効化", "ko": "이 공급자에 대한 함수/도구 호출 지원 활성화", "pt": "Habilitar suporte a chamadas de função/ferramenta para este provedor", "ar": "تفعيل دعم استدعاء الدوال/الأدوات لهذا المزود"],
        "locEnableDisableInstalledPluginsPluginsBundleSkill": ["en": "Enable or disable installed plugins. Plugins bundle skills, commands, and MCP servers.", "ru": "Включите или отключите установленные плагины. Плагины объединяют навыки, команды и MCP-серверы.", "es": "Habilite o deshabilite los plugins instalados. Los plugins incluyen habilidades, comandos y servidores MCP.", "fr": "Activez ou désactivez les plugins installés. Les plugins regroupent les compétences, commandes et serveurs MCP.", "de": "Installierte Plugins aktivieren oder deaktivieren. Plugins bündeln Skills, Befehle und MCP-Server.", "zh": "启用或禁用已安装的插件。插件捆绑技能、命令和 MCP 服务器。", "ja": "インストール済みプラグインの有効化/無効化。プラグインはスキル、コマンド、MCPサーバーをまとめます。", "ko": "설정된 플러그인을 활성화 또는 비활성화합니다. 플러그인은 스킬, 명령 및 MCP 서버를 번들로 제공합니다.", "pt": "Ative ou desative plugins instalados. Plugins agrupam habilidades, comandos وخوادم MCP.", "ar": "تفعيل أو تعطيل الإضافات المثبتة. تجمع الإضافات المهارات والأوامر وخوادم MCP."],
        "locEscClose": ["en": "Esc to close", "ru": "Esc для закрытия", "es": "Esc para cerrar", "fr": "Échap pour fermer", "de": "Esc zum Schließen", "zh": "按 Esc 关闭", "ja": "Esc で閉じる", "ko": "Esc로 닫기", "pt": "Esc para fechar", "ar": "Esc للإغلاق"],
        "locExistingChromeCookies": ["en": "Existing Chrome (cookies)", "ru": "Существующий Chrome (cookies)", "es": "Chrome existente (cookies)", "fr": "Chrome existant (cookies)", "de": "Vorhandener Chrome (Cookies)", "zh": "现有 Chrome（cookies）", "ja": "既存のChrome（cookies）", "ko": "기존 Chrome (cookies)", "pt": "Chrome existente (cookies)", "ar": "Chrome الحالي (ملفات تعريف الارتباط)"],
        "locFavoriteModel": ["en": "Favorite model", "ru": "Избранная модель", "es": "Modelo favorito", "fr": "Modèle favori", "de": "Favoritmodell", "zh": "收藏模型", "ja": "お気に入りモデル", "ko": "즐겨찾기 모델", "pt": "Modelo favorito", "ar": "النموذج المفضل"],
        "locFolder": ["en": "Folder", "ru": "Папка", "es": "Carpeta", "fr": "Dossier", "de": "Ordner", "zh": "文件夹", "ja": "フォルダー", "ko": "폴더", "pt": "Pasta", "ar": "مجلد"],
        "locHttpProxy": ["en": "HTTP Proxy", "ru": "HTTP-прокси", "es": "Proxy HTTP", "fr": "Proxy HTTP", "de": "HTTP-Proxy", "zh": "HTTP 代理", "ja": "HTTPプロキシ", "ko": "HTTP 프록시", "pt": "Proxy HTTP", "ar": "وكيل HTTP"],
        "locImagePreview": ["en": "Image Preview", "ru": "Просмотр изображения", "es": "Vista previa de imagen", "fr": "Aperçu de l'image", "de": "Bildvorschau", "zh": "图片预览", "ja": "画像プレビュー", "ko": "이미지 미리보기", "pt": "Pré-visualização de imagem", "ar": "معاينة الصورة"],
        "locInactiveChatsAreAutomaticallyArchivedAfterTheSe": ["en": "Inactive chats are automatically archived after the selected period to save space. They are loaded on demand and unarchived when you send a new message.", "ru": "Неактивные чаты автоматически архивируются через выбранный период для экономии места. Они загружаются по запросу и разархивируются при отправке нового сообщения.", "es": "Los chats inactivos se archivan automáticamente después del período seleccionado para ahorrar espacio. Se cargan bajo demanda y se desarchivan cuando envía un nuevo mensaje.", "fr": "Les conversations inactives sont automatiquement archivées après la période sélectionnée pour économiser de l'espace. Elles sont chargées à la demande et désarchivées lorsque vous envoyez un nouveau message.", "de": "Inaktive Chats werden nach dem ausgewählten Zeitraum automatisch archiviert, um Speicherplatz zu sparen. Sie werden bei Bedarf geladen und beim Senden einer neuen Nachricht dearchiviert.", "zh": "不活跃的聊天在选定时间段后自动归档以节省空间。它们按需加载，并在发送新消息时取消归档。", "ja": "非アクティブなチャットはスペースを節約するために選択した期間後に自動的にアーカイブされます。新しいメッセージを送信すると、オンデマンドで読み込まれアーカイブが解除されます。", "ko": "비활성 채팅은 공간을 절약하기 위해 선택한 기간 후 자동으로 보관됩니다. 필요 시 로드되며 새 메시지를 보낼 때 보관 해제됩니다.", "pt": "Conversas inativas são automaticamente arquivadas após o período selecionado para economizar espaço. Elas são carregadas sob demanda e desarquivadas quando você envia uma nova mensagem.", "ar": "تتم أرشفة المحادثات غير النشطة تلقائيًا بعد الفترة المحددة لتوفير المساحة. يتم تحميلها عند الطلب وإلغاء أرشفتها عند إرسال رسالة جديدة."],
        "locIndexNewFolders": ["en": "Index new folders", "ru": "Индексировать новые папки", "es": "Indexar carpetas nuevas", "fr": "Indexer les nouveaux dossiers", "de": "Neue Ordner indexieren", "zh": "索引新文件夹", "ja": "新しいフォルダをインデックス", "ko": "새 폴더 인덱싱", "pt": "Indexar pastas novas", "ar": "فهرسة المجلدات الجديدة"],
        "locIndexRepositoriesForInstantGrepBeta": ["en": "Index repositories for instant grep (Beta)", "ru": "Индексировать репозитории для мгновенного grep (Beta)", "es": "Indexar repositorios para grep instantáneo (Beta)", "fr": "Indexer les dépôts pour une recherche grep instantanée (Beta)", "de": "Repositorys für sofortigen Grep indexieren (Beta)", "zh": "索引仓库以实现即时 Grep（Beta）", "ja": "リポジトリをインデックスして即時Grep（ベータ）", "ko": "즉시 grep을 위한 저장소 인덱싱 (베타)", "pt": "Indexar repositórios para grep instantâneo (Beta)", "ar": "فهرسة المستودعات لبحث grep فوري (بيتا)"],
        "locIndexing": ["en": "Indexing", "ru": "Индексация", "es": "Indexación", "fr": "Indexation", "de": "Indexierung", "zh": "索引", "ja": "インデックス", "ko": "인덱싱", "pt": "Indexação", "ar": "الفهرسة"],
        "locKeep": ["en": "Keep", "ru": "Сохранить", "es": "Conservar", "fr": "Conserver", "de": "Behalten", "zh": "保留", "ja": "保持", "ko": "유지", "pt": "Manter", "ar": "إبقاء"],
        "locLibrary": ["en": "Library", "ru": "Библиотека", "es": "Biblioteca", "fr": "Bibliothèque", "de": "Bibliothek", "zh": "库", "ja": "ライブラリ", "ko": "라이브러리", "pt": "Biblioteca", "ar": "المكتبة"],
        "locLightCodeTheme": ["en": "Light code theme", "ru": "Светлая тема кода", "es": "Tema de código claro", "fr": "Thème de code clair", "de": "Helles Code-Theme", "zh": "浅色代码主题", "ja": "ライトコードテーマ", "ko": "라이트 코드 테마", "pt": "Tema de código claro", "ar": "سمة الكود الفاتحة"],
        "locLoadingChat": ["en": "Loading chat…", "ru": "Загрузка чата…", "es": "Cargando chat…", "fr": "Chargement du chat…", "de": "Chat wird geladen…", "zh": "正在加载聊天…", "ja": "チャットを読み込み中…", "ko": "채팅 로딩 중…", "pt": "Carregando chat…", "ar": "جارٍ تحميل الدردشة…"],
        "locLoadingOlderMessages": ["en": "Loading older messages...", "ru": "Загрузка старых сообщений...", "es": "Cargando mensajes anteriores...", "fr": "Chargement des anciens messages...", "de": "Ältere Nachrichten laden...", "zh": "加载较早的消息...", "ja": "古いメッセージを読み込み中...", "ko": "이전 메시지 로딩 중...", "pt": "Carregando mensagens anteriores...", "ar": "تحميل الرسائل القديمة..."],
        "locLocalProviders": ["en": "Local providers", "ru": "Локальные провайдеры", "es": "Proveedores locales", "fr": "Fournisseurs locaux", "de": "Lokale Anbieter", "zh": "本地提供商", "ja": "ローカルプロバイダー", "ko": "로컬 공급자", "pt": "Provedores locais", "ar": "المزودون المحليون"],
        "locMcpServers": ["en": "MCP Servers", "ru": "MCP-серверы", "es": "Servidores MCP", "fr": "Serveurs MCP", "de": "MCP-Server", "zh": "MCP 服务器", "ja": "MCPサーバー", "ko": "MCP 서버", "pt": "Servidores MCP", "ar": "خوادم MCP"],
        "locManageMycoderAgentCommandFilesCommandsCanInvoke": ["en": "Manage myCoder Agent .md command files. Commands can be invoked with /command-name in chat.", "ru": "Управляйте .md файлами команд myCoder Agent. Команды вызываются через /command-name в чате.", "es": "Administre archivos de comandos .md de myCoder Agent. Los comandos se invocan con /command-name en el chat.", "fr": "Gérez les fichiers de commandes .md de myCoder Agent. Les commandes sont invoquées avec /command-name dans le chat.", "de": "Verwalten Sie myCoder Agent .md-Befehlsdateien. Befehle werden mit /command-name im Chat aufgerufen.", "zh": "管理 myCoder Agent .md 命令文件。可通过 /command-name 在聊天中调用命令。", "ja": "myCoder Agent の .md コマンドファイルを管理。チャットで /command-name を使用して呼び出せます。", "ko": "myCoder Agent .md 명령 파일을 관리합니다. 채팅에서 /command-name으로 명령을 호출할 수 있습니다.", "pt": "Gerencie arquivos de comando .md do myCoder Agent. Comandos podem ser invocados com /command-name no chat.", "ar": "إدارة ملفات أوامر myCoder Agent .md. يمكن استدعاء الأوامر باستخدام /command-name في المحادثة."],
        "locManageCustomModelProvidersAndViewServerconnecte": ["en": "Manage custom model providers and view server-connected providers.", "ru": "Управляйте пользовательскими провайдерами моделей и просматривайте подключённые серверы.", "es": "Administre proveedores de modelos personalizados y vea proveedores conectados al servidor.", "fr": "Gérez les fournisseurs de modèles personnalisés et consultez les fournisseurs connectés au serveur.", "de": "Verwalten Sie benutzerdefinierte Modellanbieter und sehen Sie serververbundene Anbieter an.", "zh": "管理自定义模型提供商并查看服务器连接的提供商。", "ja": "カスタムモデルプロバイダーを管理し、サーバー接続プロバイダーを表示します。", "ko": "사용자 정의 모델 공급자를 관리하고 서버 연결 공급자를 봅니다.", "pt": "Gerencie provedores de modelos personalizados e visualize provedores conectados ao servidor.", "ar": "إدارة مزودي النماذج المخصصة وعرض المزودين المتصلين بالخادم."],
        "locManagedBrowser": ["en": "Managed browser", "ru": "Управляемый браузер", "es": "Navegador gestionado", "fr": "Navigateur géré", "de": "Verwalteter Browser", "zh": "受管浏览器", "ja": "管理ブラウザ", "ko": "관리 브라우저", "pt": "Navegador gerenciado", "ar": "متصفح مُدار"],
        "locMessages": ["en": "Messages", "ru": "Сообщения", "es": "Mensajes", "fr": "Messages", "de": "Nachrichten", "zh": "消息", "ja": "メッセージ", "ko": "메시지", "pt": "Mensagens", "ar": "الرسائل"],
        "locMycoder": ["en": "myCoder", "ru": "myCoder", "es": "myCoder", "fr": "myCoder", "de": "myCoder", "zh": "myCoder", "ja": "myCoder", "ko": "myCoder", "pt": "myCoder", "ar": "myCoder"],
        "locModelEffortAreChosenTheChatInputAfterConnecting": ["en": "Model & effort are chosen in the chat input after connecting.", "ru": "Модель и уровень усилий выбираются в поле ввода чата после подключения.", "es": "El modelo y el esfuerzo se eligen en la entrada del chat después de conectarse.", "fr": "Le modèle et l'effort sont choisis dans la saisie de la conversation après connexion.", "de": "Modell und Aufwand werden nach der Verbindung in der Chat-Eingabe ausgewählt.", "zh": "连接后在聊天输入中选择模型和努力程度。", "ja": "接続後にチャット入力でモデルと effort を選択します。", "ko": "연결 후 채팅 입력에서 모델 및 노력을 선택합니다.", "pt": "O modelo e o esforço são escolhidos na entrada do chat após a conexão.", "ar": "يتم اختيار النموذج وجهد في إدخال المحادثة بعد الاتصال."],
        "locModelDetails": ["en": "Model Details", "ru": "Детали модели", "es": "Detalles del modelo", "fr": "Détails du modèle", "de": "Modell-Details", "zh": "模型详情", "ja": "モデル詳細", "ko": "모델 세부 정보", "pt": "Detalhes do modelo", "ar": "تفاصيل النموذج"],
        "locInternalModels": ["en": "Internal models", "ru": "Внутренние модели", "es": "Modelos internos", "fr": "Modèles internes", "de": "Interne Modelle", "zh": "内部模型", "ja": "内部モデル", "ko": "내부 모델", "pt": "Modelos internos", "ar": "النماذج الداخلية"],
        "locInternalModelsDescription": ["en": "Models myCoder uses for background work: session summaries, context compression and unlimited internal requests.", "ru": "Модели, которые myCoder использует для фоновой работы: сводки сессий, сжатие контекста и безлимитные внутренние запросы.", "es": "Modelos que myCoder usa para tareas en segundo plano: resúmenes de sesión, compresión de contexto y solicitudes internas ilimitadas.", "fr": "Modèles que myCoder utilise pour les tâches en arrière-plan : résumés de session, compression du contexte et requêtes internes illimitées.", "de": "Modelle, die myCoder für Hintergrundarbeit verwendet: Sitzungszusammenfassungen, Kontextkomprimierung und unbegrenzte interne Anfragen.", "zh": "myCoder 用于后台工作的模型：会话摘要、上下文压缩和无限内部请求。", "ja": "myCoder がバックグラウンド処理に使用するモデル：セッション要約、コンテキスト圧縮、無制限の内部リクエスト。", "ko": "myCoder가 백그라운드 작업에 사용하는 모델: 세션 요약, 컨텍스트 압축 및 무제한 내부 요청.", "pt": "Modelos que o myCoder usa para trabalho em segundo plano: resumos de sessão, compressão de contexto e solicitações internas ilimitadas.", "ar": "النماذج التي يستخدمها myCoder للعمل في الخلفية: ملخصات الجلسات وضغط السياق والطلبات الداخلية غير المحدودة."],
        "locAddInternalModel": ["en": "Add internal model", "ru": "Добавить внутреннюю модель", "es": "Añadir modelo interno", "fr": "Ajouter un modèle interne", "de": "Internes Modell hinzufügen", "zh": "添加内部模型", "ja": "内部モデルを追加", "ko": "내부 모델 추가", "pt": "Adicionar modelo interno", "ar": "إضافة نموذج داخلي"],
        "locNoInternalModels": ["en": "No internal models selected", "ru": "Внутренние модели не выбраны", "es": "No hay modelos internos seleccionados", "fr": "Aucun modèle interne sélectionné", "de": "Keine internen Modelle ausgewählt", "zh": "未选择内部模型", "ja": "内部モデルが選択されていません", "ko": "선택된 내부 모델 없음", "pt": "Nenhum modelo interno selecionado", "ar": "لم يتم اختيار نماذج داخلية"],
        "locInternalModelsHint": ["en": "Add one or more models. They are tried in order; the next model is used if one fails.", "ru": "Добавьте одну или несколько моделей. Они пробуются по порядку; при ошибке используется следующая.", "es": "Añade uno o más modelos. Se prueban en orden; si uno falla, se usa el siguiente.", "fr": "Ajoutez un ou plusieurs modèles. Ils sont essayés dans l’ordre ; le suivant est utilisé en cas d’échec.", "de": "Fügen Sie ein oder mehrere Modelle hinzu. Sie werden der Reihe nach versucht; bei einem Fehler wird das nächste verwendet.", "zh": "添加一个或多个模型。它们会按顺序尝试；如果某个模型失败，则使用下一个。", "ja": "1 つ以上のモデルを追加してください。順番に試行され、失敗した場合は次のモデルが使用されます。", "ko": "모델을 하나 이상 추가하세요. 순서대로 시도하며 실패하면 다음 모델을 사용합니다.", "pt": "Adicione um ou mais modelos. Eles são tentados em ordem; o próximo é usado se um falhar.", "ar": "أضف نموذجاً واحداً أو أكثر. ستُجرَّب بالترتيب؛ ويُستخدم التالي عند فشل أحدها."],
        "locInternalModelBadge": ["en": "Internal", "ru": "Внутренняя", "es": "Interno", "fr": "Interne", "de": "Intern", "zh": "内部", "ja": "内部", "ko": "내부", "pt": "Interno", "ar": "داخلي"],
        "locInternalModelBadgeHelp": ["en": "Used for myCoder background work", "ru": "Используется для фоновой работы myCoder", "es": "Se usa para el trabajo en segundo plano de myCoder", "fr": "Utilisé pour les tâches d’arrière-plan de myCoder", "de": "Wird für myCoder-Hintergrundarbeit verwendet", "zh": "用于 myCoder 后台工作", "ja": "myCoder のバックグラウンド処理に使用", "ko": "myCoder 백그라운드 작업에 사용", "pt": "Usado para trabalho em segundo plano do myCoder", "ar": "يُستخدم لعمل myCoder في الخلفية"],
        "locMarkAsInternalModel": ["en": "Use as internal model", "ru": "Сделать внутренней моделью", "es": "Usar como modelo interno", "fr": "Utiliser comme modèle interne", "de": "Als internes Modell verwenden", "zh": "用作内部模型", "ja": "内部モデルとして使用", "ko": "내부 모델로 사용", "pt": "Usar como modelo interno", "ar": "استخدام كنموذج داخلي"],
        "locUnmarkAsInternalModel": ["en": "Remove from internal models", "ru": "Убрать из внутренних моделей", "es": "Quitar de los modelos internos", "fr": "Retirer des modèles internes", "de": "Aus internen Modellen entfernen", "zh": "从内部模型中移除", "ja": "内部モデルから削除", "ko": "내부 모델에서 제거", "pt": "Remover dos modelos internos", "ar": "إزالة من النماذج الداخلية"],
        "locInternalModelUnavailable": ["en": "This model cannot run in the background", "ru": "Эта модель не может работать в фоне", "es": "Este modelo no puede ejecutarse en segundo plano", "fr": "Ce modèle ne peut pas s’exécuter en arrière-plan", "de": "Dieses Modell kann nicht im Hintergrund ausgeführt werden", "zh": "此模型无法在后台运行", "ja": "このモデルはバックグラウンドで実行できません", "ko": "이 모델은 백그라운드에서 실행할 수 없습니다", "pt": "Este modelo não pode ser executado em segundo plano", "ar": "لا يمكن تشغيل هذا النموذج في الخلفية"],
        "locMoveUp": ["en": "Move up", "ru": "Выше", "es": "Subir", "fr": "Monter", "de": "Nach oben", "zh": "上移", "ja": "上へ移動", "ko": "위로 이동", "pt": "Mover para cima", "ar": "نقل للأعلى"],
        "locMoveDown": ["en": "Move down", "ru": "Ниже", "es": "Bajar", "fr": "Descendre", "de": "Nach unten", "zh": "下移", "ja": "下へ移動", "ko": "아래로 이동", "pt": "Mover para baixo", "ar": "نقل للأسفل"],
        "locFree": ["en": "Free", "ru": "Бесплатно", "es": "Gratis", "fr": "Gratuit", "de": "Kostenlos", "zh": "免费", "ja": "無料", "ko": "무료", "pt": "Grátis", "ar": "مجاني"],
        "locModelSettings": ["en": "Model settings", "ru": "Настройки модели", "es": "Configuración del modelo", "fr": "Paramètres du modèle", "de": "Modelleinstellungen", "zh": "模型设置", "ja": "モデル設定", "ko": "모델 설정", "pt": "Configurações do modelo", "ar": "إعدادات النموذج"],
        "locModels": ["en": "Models", "ru": "Модели", "es": "Modelos", "fr": "Modèles", "de": "Modelle", "zh": "模型", "ja": "モデル", "ko": "모델", "pt": "Modelos", "ar": "النماذج"],
        "locModels1": ["en": "Models:", "ru": "Модели:", "es": "Modelos:", "fr": "Modèles :", "de": "Modelle:", "zh": "模型：", "ja": "モデル：", "ko": "모델:", "pt": "Modelos:", "ar": "النماذج:"],
        "locName": ["en": "Name", "ru": "Имя", "es": "Nombre", "fr": "Nom", "de": "Name", "zh": "名称", "ja": "名前", "ko": "이름", "pt": "Nome", "ar": "الاسم"],
        "locNewProject": ["en": "New Project", "ru": "Новый проект", "es": "Nuevo proyecto", "fr": "Nouveau projet", "de": "Neues Projekt", "zh": "新建项目", "ja": "新規プロジェクト", "ko": "새 프로젝트", "pt": "Novo projeto", "ar": "مشروع جديد"],
        "locNext": ["en": "Next", "ru": "Далее", "es": "Siguiente", "fr": "Suivant", "de": "Weiter", "zh": "下一步", "ja": "次へ", "ko": "다음", "pt": "Próximo", "ar": "التالي"],
        "locArchivedProjects1": ["en": "No archived projects", "ru": "Нет архивированных проектов", "es": "No hay proyectos archivados", "fr": "Aucun projet archivé", "de": "Keine archivierten Projekte", "zh": "暂无归档项目", "ja": "アーカイブ済みプロジェクトなし", "ko": "보관된 프로젝트 없음", "pt": "Nenhum projeto arquivado", "ar": "لا توجد مشاريع مؤرشفة"],
        "locChanges1": ["en": "No changes", "ru": "Нет изменений", "es": "Sin cambios", "fr": "Aucune modification", "de": "Keine Änderungen", "zh": "无更改", "ja": "変更なし", "ko": "변경 사항 없음", "pt": "Sem alterações", "ar": "لا توجد تغييرات"],
        "locModelsForThisProvider": ["en": "No models for this provider", "ru": "Нет моделей для этого провайдера", "es": "No hay modelos para este proveedor", "fr": "Aucun modèle pour ce fournisseur", "de": "Keine Modelle für diesen Anbieter", "zh": "此提供商没有模型", "ja": "このプロバイダーのモデルはありません", "ko": "이 공급자에 대한 모델이 없습니다", "pt": "Nenhum modelo para este provedor", "ar": "لا توجد نماذج لهذا المزود"],
        "locModelsLoaded": ["en": "No models loaded", "ru": "Модели не загружены", "es": "No se cargaron modelos", "fr": "Aucun modèle chargé", "de": "Keine Modelle geladen", "zh": "未加载模型", "ja": "モデルが読み込まれていません", "ko": "로드된 모델 없음", "pt": "Nenhum modelo carregado", "ar": "لم يتم تحميل أي نماذج"],
        "locNotifications": ["en": "No notifications", "ru": "Нет уведомлений", "es": "Sin notificaciones", "fr": "Aucune notification", "de": "Keine Benachrichtigungen", "zh": "暂无通知", "ja": "通知なし", "ko": "알림 없음", "pt": "Sem notificações", "ar": "لا توجد إشعارات"],
        "locParametersAvailable": ["en": "No parameters available", "ru": "Нет доступных параметров", "es": "Sin parámetros disponibles", "fr": "Aucun paramètre disponible", "de": "Keine Parameter verfügbar", "zh": "没有可用参数", "ja": "利用可能なパラメーターはありません", "ko": "사용 가능한 매개변수 없음", "pt": "Nenhum parâmetro disponível", "ar": "لا توجد معلمات متاحة"],
        "locProjectsRegisteredYet": ["en": "No projects registered yet.", "ru": "Проекты ещё не зарегистрированы.", "es": "Aún no hay proyectos registrados.", "fr": "Aucun projet enregistré pour le moment.", "de": "Noch keine Projekte registriert.", "zh": "尚未注册项目。", "ja": "まだプロジェクトが登録されていません。", "ko": "등록된 프로젝트가 아직 없습니다.", "pt": "Nenhum projeto registrado ainda.", "ar": "لم يتم تسجيل مشاريع بعد."],
        "locProviderSelected": ["en": "No provider selected", "ru": "Провайдер не выбран", "es": "Sin proveedor seleccionado", "fr": "Aucun fournisseur sélectionné", "de": "Kein Anbieter ausgewählt", "zh": "未选择提供商", "ja": "プロバイダー未選択", "ko": "공급자 미선택", "pt": "Nenhum provedor selecionado", "ar": "لم يتم اختيار مزود"],
        "locProvidersConfigured": ["en": "No providers configured", "ru": "Провайдеры не настроены", "es": "Sin proveedores configurados", "fr": "Aucun fournisseur configuré", "de": "Keine Anbieter konfiguriert", "zh": "未配置提供商", "ja": "プロバイダーが設定されていません", "ko": "구성된 공급자 없음", "pt": "Nenhum provedor configurado", "ar": "لا توجد مزودون مكونون"],
        "locProvidersYet": ["en": "No providers yet", "ru": "Провайдеры ещё не добавлены", "es": "Sin proveedores aún", "fr": "Aucun fournisseur pour le moment", "de": "Noch keine Anbieter", "zh": "暂无提供商", "ja": "まだプロバイダーがありません", "ko": "공급자가 아직 없습니다", "pt": "Nenhum provedor ainda", "ar": "لا توجد مزودون بعد"],
        "locTasksYet": ["en": "No tasks yet", "ru": "Задач пока нет", "es": "Sin tareas aún", "fr": "Aucune tâche pour le moment", "de": "Noch keine Aufgaben", "zh": "暂无任务", "ja": "タスクはまだありません", "ko": "작업이 아직 없습니다", "pt": "Nenhuma tarefa ainda", "ar": "لا توجد مهام بعد"],
        "locUsageDataForTheSelectedPeriod": ["en": "No usage data for the selected period.", "ru": "Нет данных об использовании за выбранный период.", "es": "Sin datos de uso para el período seleccionado.", "fr": "Aucune donnée d'utilisation pour la période sélectionnée.", "de": "Keine Nutzungsdaten für den ausgewählten Zeitraum.", "zh": "所选时段没有使用数据。", "ja": "選択した期間の使用データがありません。", "ko": "선택한 기간에 대한 사용 데이터가 없습니다.", "pt": "Nenhum dado de uso para o período selecionado.", "ar": "لا توجد بيانات استخدام للفترة المحددة."],
        "locNotifications1": ["en": "Notifications", "ru": "Уведомления", "es": "Notificaciones", "fr": "Notifications", "de": "Benachrichtigungen", "zh": "通知", "ja": "通知", "ko": "알림", "pt": "Notificações", "ar": "الإشعارات"],
        "locOpenFolder": ["en": "Open folder", "ru": "Открыть папку", "es": "Abrir carpeta", "fr": "Ouvrir le dossier", "de": "Ordner öffnen", "zh": "打开文件夹", "ja": "フォルダを開く", "ko": "폴더 열기", "pt": "Abrir pasta", "ar": "فتح المجلد"],
        "locOpenFullStoragePanel": ["en": "Open full storage panel", "ru": "Открыть полную панель хранилища", "es": "Abrir panel de almacenamiento completo", "fr": "Ouvrir le panneau de stockage complet", "de": "Vollständiges Speicherpanel öffnen", "zh": "打开完整存储面板", "ja": "フルストレージパネルを開く", "ko": "전체 스토리지 패널 열기", "pt": "Abrir painel de armazenamento completo", "ar": "فتح لوحة التخزين الكاملة"],
        "locOrphanedPathMissing": ["en": "Orphaned (path missing)", "ru": "Осиротевший (путь отсутствует)", "es": "Huérfano (ruta faltante)", "fr": "Orphelin (chemin manquant)", "de": "Verwaist (Pfad fehlt)", "zh": "孤立（路径缺失）", "ja": "孤立（パスなし）", "ko": "고아 (경로 누락)", "pt": "Órfão (caminho ausente)", "ar": "يتيم (المسار مفقود)"],
        "locRemoveOrphanedRecords": ["en": "Remove orphaned records", "ru": "Удалить осиротевшие записи", "es": "Eliminar registros huérfanos", "fr": "Supprimer les enregistrements orphelins", "de": "Verwaiste Einträge entfernen", "zh": "移除孤立记录", "ja": "孤立したレコードを削除", "ko": "고아 레코드 제거", "pt": "Remover registos órfãos", "ar": "إزالة السجلات اليتيمة"],
        "locRemoveOrphanedRecordsHelp": ["en": "Remove every registry record whose folder no longer exists. Project data on disk is untouched.", "ru": "Удалить все записи реестра, папки которых больше не существуют. Данные проектов на диске не затрагиваются.", "es": "Elimina todos los registros del registro cuyas carpetas ya no existen. Los datos de los proyectos en disco no se tocan.", "fr": "Supprime tous les enregistrements du registre dont le dossier n'existe plus. Les données des projets sur disque ne sont pas touchées.", "de": "Entfernt alle Registry-Einträge, deren Ordner nicht mehr existiert. Projektdaten auf der Festplatte bleiben unberührt.", "zh": "移除所有文件夹已不存在的注册表记录。磁盘上的项目数据不受影响。", "ja": "フォルダが存在しないレジストリレコードをすべて削除します。ディスク上のプロジェクトデータは変更されません。", "ko": "폴더가 더 이상 존재하지 않는 모든 레지스트리 레코드를 제거합니다. 디스크의 프로젝트 데이터는 건드리지 않습니다.", "pt": "Remove todos os registos do registo cujas pastas já não existem. Os dados dos projetos no disco não são alterados.", "ar": "يزيل كل سجلات السجل التي لم تعد مجلداتها موجودة. لا تتم المساس ببيانات المشاريع على القرص."],
        "locAlertRemoveOrphanedRecords": ["en": "Remove orphaned records?", "ru": "Удалить осиротевшие записи?", "es": "¿Eliminar registros huérfanos?", "fr": "Supprimer les enregistrements orphelins ?", "de": "Verwaiste Einträge entfernen?", "zh": "移除孤立记录？", "ja": "孤立したレコードを削除しますか？", "ko": "고아 레코드를 제거할까요?", "pt": "Remover registos órfãos?", "ar": "إزالة السجلات اليتيمة؟"],
        "locRemoveOrphanedRecordsMessage": ["en": "{0} record(s) will be removed. Their folders are already missing, so no project data is deleted.", "ru": "Будет удалено записей: {0}. Их папки уже отсутствуют, поэтому данные проектов не удаляются.", "es": "Se eliminarán {0} registro(s). Sus carpetas ya no existen, así que no se borran datos de proyectos.", "fr": "{0} enregistrement(s) seront supprimés. Leurs dossiers sont déjà absents, donc aucune donnée de projet n'est supprimée.", "de": "{0} Eintrag/Einträge werden entfernt. Ihre Ordner fehlen bereits, daher werden keine Projektdaten gelöscht.", "zh": "将移除 {0} 条记录。这些文件夹已不存在，因此不会删除项目数据。", "ja": "{0} 件のレコードを削除します。フォルダはすでに存在しないため、プロジェクトデータは削除されません。", "ko": "{0}개의 레코드가 제거됩니다. 해당 폴더는 이미 없으므로 프로젝트 데이터는 삭제되지 않습니다.", "pt": "{0} registo(s) serão removidos. As respetivas pastas já não existem, pelo que nenhum dado de projeto é eliminado.", "ar": "ستتم إزالة {0} سجل. مجلداتها مفقودة بالفعل، لذا لن يتم حذف أي بيانات مشروع."],
        "locOverview": ["en": "Overview", "ru": "Обзор", "es": "Vista general", "fr": "Aperçu", "de": "Übersicht", "zh": "概览", "ja": "概要", "ko": "개요", "pt": "Visão geral", "ar": "نظرة عامة"],
        "locPerProject": ["en": "Per project", "ru": "По проекту", "es": "Por proyecto", "fr": "Par projet", "de": "Pro Projekt", "zh": "按项目", "ja": "プロジェクト別", "ko": "프로젝트별", "pt": "Por projeto", "ar": "لكل مشروع"],
        "locPickProviderTheLeftViewItsConnectionAndSettings": ["en": "Pick a provider on the left to view its connection and settings.", "ru": "Выберите провайдера слева для просмотра его подключения и настроек.", "es": "Seleccione un proveedor a la izquierda para ver su conexión y configuración.", "fr": "Sélectionnez un fournisseur à gauche pour voir sa connexion et ses paramètres.", "de": "Wählen Sie links einen Anbieter aus, um Verbindung und Einstellungen anzuzeigen.", "zh": "在左侧选择提供商以查看其连接和设置。", "ja": "左側からプロバイダーを選択して接続と設定を表示します。", "ko": "왼쪽에서 공급자를 선택하여 연결 및 설정을 봅니다.", "pt": "Selecione um provedor à esquerda para ver sua conexão e configurações.", "ar": "اختر مزودًا على اليسار لعرض اتصاله وإعداداته."],
        "locPickServerFromTheLibraryAboveAndTapInstall": ["en": "Pick a server from the library above and tap Install.", "ru": "Выберите сервер из библиотеки выше и нажмите «Установить».", "es": "Seleccione un servidor de la biblioteca anterior y toque Instalar.", "fr": "Sélectionnez un serveur dans la bibliothèque ci-dessus et appuyez sur Installer.", "de": "Wählen Sie einen Server aus der obigen Bibliothek und tippen Sie auf Installieren.", "zh": "从上方库中选择服务器并点击安装。", "ja": "上のライブラリからサーバーを選択してインストールをタップします。", "ko": "위 라이브러리에서 서버를 선택하고 설치를 탭합니다.", "pt": "Selecione um servidor na biblioteca acima e toque em Instalar.", "ar": "اختر خادمًا من المكتبة أعلاه واضغط على تثبيت."],
        "locPickSkillFromTheLibraryAboveAndTapInstall": ["en": "Pick a skill from the library above and tap Install.", "ru": "Выберите навык из библиотеки выше и нажмите «Установить».", "es": "Seleccione una habilidad de la biblioteca anterior y toque Instalar.", "fr": "Sélectionnez une compétence dans la bibliothèque ci-dessus et appuyez sur Installer.", "de": "Wählen Sie einen Skill aus der obigen Bibliothek und tippen Sie auf Installieren.", "zh": "从上方库中选择技能并点击安装。", "ja": "上のライブラリからスキルを選択してインストールをタップします。", "ko": "위 라이브러리에서 스킬을 선택하고 설치를 탭합니다.", "pt": "Selecione uma habilidade na biblioteca acima e toque em Instalar.", "ar": "اختر مهارة من المكتبة أعلاه واضغط على تثبيت."],
        "locPlugins": ["en": "Plugins", "ru": "Плагины", "es": "Plugins", "fr": "Plugins", "de": "Plugins", "zh": "插件", "ja": "プラグイン", "ko": "플러그인", "pt": "Plugins", "ar": "الإضافات"],
        "locPluginsLiveUnderMycoderplugins": ["en": "Plugins live under ~/.mycoder/plugins", "ru": "Плагины находятся в ~/.mycoder/plugins", "es": "Los plugins están en ~/.mycoder/plugins", "fr": "Les plugins se trouvent dans ~/.mycoder/plugins", "de": "Plugins befinden sich unter ~/.mycoder/plugins", "zh": "插件位于 ~/.mycoder/plugins", "ja": "プラグインは ~/.mycoder/plugins にあります", "ko": "플러그인은 ~/.mycoder/plugins에 있습니다", "pt": "Plugins ficam em ~/.mycoder/plugins", "ar": "الإضافات موجودة في ~/.mycoder/plugins"],
        "locProjectName": ["en": "Project Name", "ru": "Название проекта", "es": "Nombre del proyecto", "fr": "Nom du projet", "de": "Projektname", "zh": "项目名称", "ja": "プロジェクト名", "ko": "프로젝트 이름", "pt": "Nome do projeto", "ar": "اسم المشروع"],
        "locProjects": ["en": "Projects", "ru": "Проекты", "es": "Proyectos", "fr": "Projets", "de": "Projekte", "zh": "项目", "ja": "プロジェクト", "ko": "프로젝트", "pt": "Projetos", "ar": "المشاريع"],
        "locProviderType": ["en": "Provider Type", "ru": "Тип провайдера", "es": "Tipo de proveedor", "fr": "Type de fournisseur", "de": "Anbietertyp", "zh": "提供商类型", "ja": "プロバイダータイプ", "ko": "공급자 유형", "pt": "Tipo de provedor", "ar": "نوع المزود"],
        "locProviders": ["en": "Providers", "ru": "Провайдеры", "es": "Proveedores", "fr": "Fournisseurs", "de": "Anbieter", "zh": "提供商", "ja": "プロバイダー", "ko": "공급자", "pt": "Fornecedores", "ar": "المقدّمون"],
        "locProvidersModels": ["en": "Providers & models", "ru": "Провайдеры и модели", "es": "Proveedores y modelos", "fr": "Fournisseurs et modèles", "de": "Anbieter & Modelle", "zh": "提供商和模型", "ja": "プロバイダーとモデル", "ko": "공급자 및 모델", "pt": "Provedores e modelos", "ar": "المزودون والنماذج"],
        "locRemoteConnection": ["en": "Remote connection", "ru": "Удалённое подключение", "es": "Conexión remota", "fr": "Connexion distante", "de": "Remote-Verbindung", "zh": "远程连接", "ja": "リモート接続", "ko": "원격 연결", "pt": "Conexão remota", "ar": "اتصال بعيد"],
        "locRemove": ["en": "Remove", "ru": "Удалить", "es": "Eliminar", "fr": "Supprimer", "de": "Entfernen", "zh": "移除", "ja": "削除", "ko": "제거", "pt": "Remover", "ar": "إزالة"],
        "locRetry": ["en": "Retry", "ru": "Повторить", "es": "Reintentar", "fr": "Réessayer", "de": "Erneut versuchen", "zh": "重试", "ja": "再試行", "ko": "다시 시도", "pt": "Tentar novamente", "ar": "إعادة المحاولة"],
        "locRouteModelMcpCommandtoolAndAppRendererEgressTra": ["en": "Route model, MCP, command-tool, and app renderer egress traffic through this proxy. Leave blank for direct connections; system environment variables are not read. Restart the app to take effect.", "ru": "Маршрутизируйте трафик моделей, MCP, команд и рендерера приложения через этот прокси. Оставьте пустым для прямых подключений. Перезапустите приложение для применения.", "es": "Enrute el tráfico de modelos, MCP, herramientas de comandos y renderizador de la aplicación a través de este proxy. Deje vacío para conexiones directas. Reinicie la aplicación para que surta efecto.", "fr": "Routez le trafic des modèles, MCP, outils de commande et rendu de l'application via ce proxy. Laissez vide pour les connexions directes. Redémarrez l'application pour appliquer.", "de": "Leiten Sie Modell-, MCP-, Command-Tool- und App-Renderer-Verkehr über diesen Proxy. Leer lassen für direkte Verbindungen. Starten Sie die App neu.", "zh": "通过此代理路由模型、MCP、命令工具和应用渲染器的出站流量。留空使用直连。重启应用生效。", "ja": "このプロキシを通じてモデル、MCP、コマンドツール、アプリレンダラーの通信をルーティング。空白なら直接接続。再起動で適用。", "ko": "이 프록시를 통해 모델, MCP, 명령 도구 및 앱 렌더러의 아웃바운드 트래픽을 라우팅합니다. 비워두면 직접 연결. 앱을 재시작해야 적용됩니다.", "pt": "Roteie o tráfego de modelo, MCP, ferramenta de comando e renderizador do aplicativo por este proxy. Deixe vazio para conexões diretas. Reinicie o aplicativo para efetivar.", "ar": "توجيه حركة نماذج MCP وأداة الأوامر ومُ renderers التطبيق عبر هذا الوكيل. اتركه فارغًا للاتصالات المباشرة. أعد تشغيل التطبيق لتطبيق التغييرات."],
        "locRunModelsLocallyViaOllamaOpencodeMycoderCliserv": ["en": "Run models locally via Ollama, OpenCode, or myCoder CLI/Serve. Enter an address to auto-detect the provider and load its models.", "ru": "Запускайте модели локально через Ollama, OpenCode или myCoder CLI/Serve. Введите адрес для автоопределения провайдера и загрузки моделей.", "es": "Ejecute modelos localmente a través de Ollama, OpenCode o myCoder CLI/Serve. Ingrese una dirección para detectar automáticamente el proveedor y cargar sus modelos.", "fr": "Exécutez des modèles localement via Ollama, OpenCode ou myCoder CLI/Serve. Entrez une adresse pour détecter automatiquement le fournisseur et charger ses modèles.", "de": "Führen Sie Modelle lokal über Ollama, OpenCode oder myCoder CLI/Serve aus. Geben Sie eine Adresse ein, um den Anbieter automatisch zu erkennen und seine Modelle zu laden.", "zh": "通过 Ollama、OpenCode 或 myCoder CLI/Serve 在本地运行模型。输入地址以自动检测提供商并加载其模型。", "ja": "Ollama、OpenCode、myCoder CLI/Serveでローカルにモデルを実行。アドレスを入力してプロバイダーを自動検出します。", "ko": "Ollama, OpenCode 또는 myCoder CLI/Serve를 통해 로컬에서 모델을 실행합니다. 주소를 입력하여 공급자를 자동 감지하고 모델을 로드합니다.", "pt": "Execute modelos localmente via Ollama, OpenCode ou myCoder CLI/Serve. Digite um endereço para detectar automaticamente o provedor e carregar seus modelos.", "ar": "تشغيل النماذج محليًا عبر Ollama أو OpenCode أو myCoder CLI/Serve. أدخل عنصرًا للكشف التلقائي عن المزود وتحميل نماذجه."],
        "locSearch": ["en": "Search", "ru": "Поиск", "es": "Buscar", "fr": "Rechercher", "de": "Suchen", "zh": "搜索", "ja": "検索", "ko": "검색", "pt": "Pesquisar", "ar": "بحث"],
        "locSelectProviderFirst": ["en": "Select a provider first", "ru": "Сначала выберите провайдер", "es": "Seleccione un proveedor primero", "fr": "Sélectionnez d'abord un fournisseur", "de": "Wählen Sie zuerst einen Anbieter", "zh": "请先选择提供商", "ja": "まずプロバイダーを選択してください", "ko": "먼저 공급자를 선택하세요", "pt": "Selecione um provedor primeiro", "ar": "اختر مزودًا أولاً"],
        "locShowLineNumbers": ["en": "Show line numbers", "ru": "Показывать номера строк", "es": "Mostrar números de línea", "fr": "Afficher les numéros de ligne", "de": "Zeilennummern anzeigen", "zh": "显示行号", "ja": "行番号を表示", "ko": "줄 번호 표시", "pt": "Mostrar números de linha", "ar": "عرض أرقام الأسطر"],
        "locSkills": ["en": "Skills", "ru": "Навыки", "es": "Habilidades", "fr": "Compétences", "de": "Skills", "zh": "技能", "ja": "スキル", "ko": "스킬", "pt": "Competências", "ar": "المهارات"],
        "locSnapshots": ["en": "Snapshots", "ru": "Снимки", "es": "Instantáneas", "fr": "Snapshots", "de": "Snapshots", "zh": "快照", "ja": "スナップショット", "ko": "스냅샷", "pt": "Snapshots", "ar": "اللقطات"],
        "locStorageDatabase": ["en": "Storage & Database", "ru": "Хранилище и база данных", "es": "Almacenamiento y base de datos", "fr": "Stockage et base de données", "de": "Speicher & Datenbank", "zh": "存储和数据库", "ja": "ストレージとデータベース", "ko": "스토리지 및 데이터베이스", "pt": "Armazenamento e banco de dados", "ar": "التخزين وقاعدة البيانات"],
        "locStorageQuotaExceeded": ["en": "Storage quota exceeded", "ru": "Превышена квота хранилища", "es": "Cuota de almacenamiento excedida", "fr": "Quota de stockage dépassé", "de": "Speicherlimit überschritten", "zh": "存储配额已超出", "ja": "ストレージ容量を超過しました", "ko": "스토리지 할당량 초과", "pt": "Cota de armazenamento excedida", "ar": "تم تجاوز حصة التخزين"],
        "locSwitchPlanAgent": ["en": "Switch to Plan agent", "ru": "Переключиться на Plan-агента", "es": "Cambiar al agente Plan", "fr": "Passer à l'agent Plan", "de": "Zum Plan-Agenten wechseln", "zh": "切换到 Plan 代理", "ja": "Planエージェントに切替", "ko": "Plan 에이전트로 전환", "pt": "Mudar para o agente Plan", "ar": "التبديل إلى وكيل Plan"],
        "locSystemPrompt": ["en": "System prompt", "ru": "Системный промпт", "es": "Indicación del sistema", "fr": "Invite système", "de": "Systemaufforderung", "zh": "系统提示", "ja": "システムプロンプト", "ko": "시스템 프롬프트", "pt": "Prompt do sistema", "ar": "موجه النظام"],
        "locTaskCompletionsAndSystemAlertsWillAppearHere": ["en": "Task completions and system alerts will appear here.", "ru": "Завершённые задачи и системные оповещения будут отображаться здесь.", "es": "Las finalizaciones de tareas y alertas del sistema aparecerán aquí.", "fr": "Les finalisations de tâches et alertes système apparaîtront ici.", "de": "Aufgabenabschlüsse und Systemwarnungen werden hier angezeigt.", "zh": "任务完成和系统提醒将显示在此处。", "ja": "タスクの完了とシステムアラートはここに表示されます。", "ko": "작업 완료 및 시스템 알림이 여기에 표시됩니다.", "pt": "Conclusões de tarefas e alertas do sistema aparecerão aqui.", "ar": "ستظهر إكمال المهام وتنبيهات النظام هنا."],
        "locTestConnection": ["en": "Test Connection", "ru": "Проверить подключение", "es": "Probar conexión", "fr": "Tester la connexion", "de": "Verbindung testen", "zh": "测试连接", "ja": "接続テスト", "ko": "연결 테스트", "pt": "Testar conexão", "ar": "اختبار الاتصال"],
        "locThemeUsedForCodeBlocksWhileTheInterfaceDarkMode": ["en": "Theme used for code blocks while the interface is in dark mode.", "ru": "Тема для блоков кода в тёмном режиме интерфейса.", "es": "Tema utilizado para bloques de código mientras la interfaz está en modo oscuro.", "fr": "Thème utilisé pour les blocs de code lorsque l'interface est en mode sombre.", "de": "Theme für Codeblöcke im dunklen Interface-Modus.", "zh": "界面处于深色模式时代码块使用的主题。", "ja": "インターフェースがダークモードのコードブロックに使用されるテーマ。", "ko": "인터페이스가 다크 모드일 때 코드 블록에 사용되는 테마.", "pt": "Tema usado para blocos de código enquanto a interface está no modo escuro.", "ar": "السمة المستخدمة لكتل الكود بينما الواجهة في الوضع الداكن."],
        "locThemeUsedForCodeBlocksWhileTheInterfaceLightMod": ["en": "Theme used for code blocks while the interface is in light mode.", "ru": "Тема для блоков кода в светлом режиме интерфейса.", "es": "Tema utilizado para bloques de código mientras la interfaz está en modo claro.", "fr": "Thème utilisé pour les blocs de code lorsque l'interface est en mode clair.", "de": "Theme für Codeblöcke im hellen Interface-Modus.", "zh": "界面处于浅色模式时代码块使用的主题。", "ja": "インターフェースがライトモードのコードブロックに使用されるテーマ。", "ko": "인터페이스가 라이트 모드일 때 코드 블록에 사용되는 테마.", "pt": "Tema usado para blocos de código enquanto a interface está no modo claro.", "ar": "السمة المستخدمة لكتل الكود بينما الواجهة في الوضع الفاتح."],
        "locThinking": ["en": "Thinking", "ru": "Рассуждение", "es": "Pensando", "fr": "Réflexion", "de": "Denken", "zh": "思考中", "ja": "思考中", "ko": "사고 중", "pt": "Pensando", "ar": "جاري التفكير"],
        "locThisWillPermanentlyDeleteAllArchivedChatsAndThe": ["en": "This will permanently delete ALL archived chats and their messages. This action cannot be undone.", "ru": "Это навсегда удалит ВСЕ архивированные чаты и их сообщения. Это действие необратимо.", "es": "Esto eliminará permanentemente TODOS los chats archivados y sus mensajes. Esta acción no se puede deshacer.", "fr": "Cela supprimera définitivement TOUTES les conversations archivées et leurs messages. Cette action est irréversible.", "de": "Dies löscht alle archivierten Chats und deren Nachrichten dauerhaft. Diese Aktion kann nicht rückgängig gemacht werden.", "zh": "这将永久删除所有已归档的聊天及其消息。此操作无法撤销。", "ja": "すべてのアーカイブ済みチャットとそのメッセージが完全に削除されます。この操作は取り消せません。", "ko": "보관된 모든 채팅과 해당 메시지가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.", "pt": "Isso excluirá permanentemente TODAS as conversas arquivadas e suas mensagens. Esta ação não pode ser desfeita.", "ar": "سيؤدي هذا إلى حذف جميع المحادثات المؤرشفة ورسائلها نهائيًا. لا يمكن التراجع عن هذا الإجراء."],
        "locTimeRange": ["en": "Time range", "ru": "Период времени", "es": "Rango de tiempo", "fr": "Plage de temps", "de": "Zeitraum", "zh": "时间范围", "ja": "期間", "ko": "시간 범위", "pt": "Intervalo de tempo", "ar": "نطاق الوقت"],
        "locTitle": ["en": "Title", "ru": "Заголовок", "es": "Título", "fr": "Titre", "de": "Titel", "zh": "标题", "ja": "タイトル", "ko": "제목", "pt": "Título", "ar": "العنوان"],
        "locToolsUnavailableForCurrentModel": ["en": "Tools unavailable for current model", "ru": "Инструменты недоступны для текущей модели", "es": "Herramientas no disponibles para el modelo actual", "fr": "Outils indisponibles pour le modèle actuel", "de": "Tools nicht verfügbar für aktuelles Modell", "zh": "当前模型不支持工具", "ja": "現在のモデルではツールが利用できません", "ko": "현재 모델에서 도구를 사용할 수 없습니다", "pt": "Ferramentas indisponíveis para o modelo atual", "ar": "الأدوات غير متاحة للنموذج الحالي"],
        "locToolsUnavailableForTheCurrentModelProvider": ["en": "Tools unavailable for the current model or provider.", "ru": "Инструменты недоступны для текущей модели или провайдера.", "es": "Herramientas no disponibles para el modelo o proveedor actual.", "fr": "Outils indisponibles pour le modèle ou fournisseur actuel.", "de": "Tools nicht verfügbar für das aktuelle Modell oder den Anbieter.", "zh": "当前模型或提供商不支持工具。", "ja": "現在のモデルまたはプロバイダーではツールが利用できません。", "ko": "현재 모델 또는 공급자에서 도구를 사용할 수 없습니다.", "pt": "Ferramentas indisponíveis para o modelo ou provedor atual.", "ar": "الأدوات غير متاحة للنموذج أو المزود الحالي."],
        "locToolsUnavailableForThisModel": ["en": "Tools unavailable for this model", "ru": "Инструменты недоступны для этой модели", "es": "Herramientas no disponibles para este modelo", "fr": "Outils indisponibles pour ce modèle", "de": "Tools nicht verfügbar für dieses Modell", "zh": "此模型不支持工具", "ja": "このモデルではツールが利用できません", "ko": "이 모델에서 도구를 사용할 수 없습니다", "pt": "Ferramentas indisponíveis para este modelo", "ar": "الأدوات غير متاحة لهذا النموذج"],
        "locTotal": ["en": "Total", "ru": "Итого", "es": "Total", "fr": "Total", "de": "Gesamt", "zh": "总计", "ja": "合計", "ko": "합계", "pt": "Total", "ar": "المجموع"],
        "locTotalCost": ["en": "Total cost", "ru": "Общая стоимость", "es": "Costo total", "fr": "Coût total", "de": "Gesamtkosten", "zh": "总费用", "ja": "合計コスト", "ko": "총 비용", "pt": "Custo total", "ar": "التكلفة الإجمالية"],
        "locTotalTokens": ["en": "Total tokens", "ru": "Всего токенов", "es": "Total de tokens", "fr": "Total des jetons", "de": "Token gesamt", "zh": "总 token 数", "ja": "合計トークン", "ko": "총 토큰", "pt": "Total de tokens", "ar": "إجمالي الرموز"],
        "locTransmit": ["en": "Transmit", "ru": "Отправить", "es": "Transmitir", "fr": "Transmettre", "de": "Übertragen", "zh": "发送", "ja": "送信", "ko": "전송", "pt": "Transmitir", "ar": "إرسال"],
        "locUrl": ["en": "URL:", "ru": "URL:", "es": "URL:", "fr": "URL :", "de": "URL:", "zh": "URL：", "ja": "URL:", "ko": "URL:", "pt": "URL:", "ar": "الرابط:"],
        "locUsage": ["en": "Usage", "ru": "Использование", "es": "Uso", "fr": "Utilisation", "de": "Nutzung", "zh": "使用情况", "ja": "使用量", "ko": "사용량", "pt": "Uso", "ar": "الاستخدام"],
        "locUseFreeWebModelsKimiQwenChatgptThroughControlle": ["en": "Use free web models (Kimi, Qwen, ChatGPT) through a controlled browser. Tools (read_file/write_file/…) are emulated over the chat. Automating a third-party service may violate its Terms of Service — enable only if you accept that.", "ru": "Используйте бесплатные веб-модели (Kimi, Qwen, ChatGPT) через управляемый браузер. Инструменты (read_file/write_file/…) эмулируются через чат. Автоматизация стороннего сервиса может нарушить его условия использования — включайте только если вы согласны.", "es": "Use modelos web gratuitos (Kimi, Qwen, ChatGPT) a través de un navegador controlado. Las herramientas se emulan a través del chat. La automatización de un servicio de terceros puede violar sus Términos de Servicio.", "fr": "Utilisez des modèles web gratuits (Kimi, Qwen, ChatGPT) via un navigateur contrôlé. Les outils sont émulés via la conversation. L'automatisation d'un service tiers peut enfreindre ses Conditions d'utilisation.", "de": "Verwenden Sie kostenlose Web-Modelle (Kimi, Qwen, ChatGPT) über einen kontrollierten Browser. Tools werden über den Chat emuliert. Die Automatisierung eines Drittanbieter-Dienstes kann dessen Nutzungsbedingungen verletzen.", "zh": "通过受控浏览器使用免费网络模型（Kimi、Qwen、ChatGPT）。工具通过聊天模拟。自动化第三方服务可能违反其服务条款。", "ja": "制御されたブラウザを介して無料Webモデル（Kimi、Qwen、ChatGPT）を使用。ツールはチャットでエミュレート。サードパーティサービスの自動化は利用規約違反になる可能性があります。", "ko": "제어된 브라우저를 통해 무료 웹 모델(Kimi, Qwen, ChatGPT)을 사용합니다. 도구는 채팅에서 에뮬레이션됩니다. 타사 서비스 자동화는 서비스 약관을 위반할 수 있습니다.", "pt": "Use modelos web gratuitos (Kimi, Qwen, ChatGPT) por meio de um navegador controlado. Ferramentas são emuladas pelo chat. Automatizar um serviço de terceiros pode violar seus Termos de Serviço.", "ar": "استخدم نماذج الويب المجانية (Kimi، Qwen، ChatGPT) من خلال متصفح مُتحكَّم. يتم محاكاة الأدوات عبر المحادثة. قد ينتهك أتمتة خدمة طرف ثالث شروط الخدمة."],
        "locWebProvidersBrowser": ["en": "Web providers (browser)", "ru": "Веб-провайдеры (браузер)", "es": "Proveedores web (navegador)", "fr": "Fournisseurs web (navigateur)", "de": "Web-Anbieter (Browser)", "zh": "网络提供商（浏览器）", "ja": "Webプロバイダー（ブラウザ）", "ko": "웹 공급자 (브라우저)", "pt": "Provedores web (navegador)", "ar": "مزودو الويب (المتصفح)"],
        "locWrapLongContentInsideThePreviewAreaAutomaticall": ["en": "Wrap long content inside the preview area automatically.", "ru": "Автоматически переносить длинное содержимое в области предпросмотра.", "es": "Ajustar contenido largo dentro del área de vista previa automáticamente.", "fr": "Retourner automatiquement le contenu long dans la zone d'aperçu.", "de": "Lange Inhalte im Vorschaubereich automatisch umbrechen.", "zh": "自动在预览区域内换行长内容。", "ja": "プレビューエリア内で長いコンテンツを自動的に折り返します。", "ko": "미리보기 영역 내에서 긴 콘텐츠를 자동으로 줄 바꿈합니다.", "pt": "Quebrar conteúdo longo dentro da área de pré-visualização automaticamente.", "ar": "طي المحتوى الطويل داخل منطقة المعاينة تلقائيًا."],
        "locWrapLongLines": ["en": "Wrap long lines", "ru": "Перенос длинных строк", "es": "Ajustar líneas largas", "fr": "Retourner les lignes longues", "de": "Lange Zeilen umbrechen", "zh": "自动换行长行", "ja": "長い行を折り返す", "ko": "긴 줄 바꿈", "pt": "Quebrar linhas longas", "ar": "طي الأسطر الطويلة"],
        "locUsage1": ["en": "by usage", "ru": "по использованию", "es": "por uso", "fr": "par utilisation", "de": "nach Nutzung", "zh": "按使用量", "ja": "使用量別", "ko": "사용량별", "pt": "por uso", "ar": "حسب الاستخدام"],
        "locDefault": ["en": "default", "ru": "по умолчанию", "es": "predeterminado", "fr": "par défaut", "de": "Standard", "zh": "默认", "ja": "デフォルト", "ko": "기본", "pt": "padrão", "ar": "افتراضي"],
        "locNow": ["en": "now", "ru": "сейчас", "es": "ahora", "fr": "maintenant", "de": "jetzt", "zh": "现在", "ja": "今", "ko": "지금", "pt": "agora", "ar": "الآن"],
        "settingsBackToWorkspace": ["en": "Back to workspace", "ru": "Назад в workspace", "es": "Volver al área de trabajo", "fr": "Retour à l'espace de travail", "de": "Zurück zum Arbeitsbereich", "zh": "返回工作区", "ja": "ワークスペースに戻る", "ko": "작업 공간으로 돌아가기", "pt": "Voltar à área de trabalho", "ar": "العودة إلى مساحة العمل"],
        "settingsGeneralTitle": ["en": "General", "ru": "Общие", "es": "General", "fr": "Général", "de": "Allgemein", "zh": "通用", "ja": "一般", "ko": "일반", "pt": "Geral", "ar": "عام"],
        "settingsAppThemeTitle": ["en": "App theme", "ru": "Тема приложения", "es": "Tema de la aplicación", "fr": "Thème de l'application", "de": "App-Design", "zh": "应用主题", "ja": "アプリのテーマ", "ko": "앱 테마", "pt": "Tema da aplicação", "ar": "سمة التطبيق"],
        "settingsAppThemeDescription": ["en": "Choose which theme the application interface should use.", "ru": "Выберите тему интерфейса приложения.", "es": "Elija qué tema debe usar la interfaz de la aplicación.", "fr": "Choisissez le thème à utiliser pour l'interface de l'application.", "de": "Wählen Sie, welches Design die Anwendungsoberfläche verwenden soll.", "zh": "选择应用程序界面使用的主题。", "ja": "アプリケーションインターフェースで使用するテーマを選択してください。", "ko": "애플리케이션 인터페이스에서 사용할 테마를 선택하세요.", "pt": "Escolha o tema que a interface da aplicação deve utilizar.", "ar": "اختر السمة التي يجب أن تستخدمها واجهة التطبيق."],
        "settingsLanguageTitle": ["en": "Language", "ru": "Язык", "es": "Idioma", "fr": "Langue", "de": "Sprache", "zh": "语言", "ja": "言語", "ko": "언어", "pt": "Idioma", "ar": "اللغة"],
        "settingsLanguageDescription": ["en": "Choose the display language used by the application UI.", "ru": "Выберите язык интерфейса приложения.", "es": "Elija el idioma de visualización usado por la interfaz.", "fr": "Choisissez la langue d'affichage utilisée par l'interface.", "de": "Wählen Sie die Anzeigesprache der Anwendungsoberfläche.", "zh": "选择应用程序界面使用的显示语言。", "ja": "アプリケーションUIで使用する表示言語を選択してください。", "ko": "애플리케이션 UI에서 사용할 표시 언어를 선택하세요.", "pt": "Escolha o idioma de visualização utilizado pela interface da aplicação.", "ar": "اختر لغة العرض المستخدمة في واجهة المستخدم."],
        "settingsInterfaceZoomTitle": ["en": "Interface zoom", "ru": "Масштаб интерфейса", "es": "Zoom de la interfaz", "fr": "Zoom de l'interface", "de": "Oberfläche-Zoom", "zh": "界面缩放", "ja": "インターフェースのズーム", "ko": "인터페이스 확대/축소", "pt": "Zoom da interface", "ar": "تكبير الواجهة"],
        "settingsInterfaceZoomDescription": ["en": "Adjust the overall size of text and controls in the current window.", "ru": "Измените общий размер текста и элементов управления в окне.", "es": "Ajuste el tamaño general del texto y los controles.", "fr": "Ajustez la taille globale du texte et des contrôles.", "de": "Passen Sie die Gesamtgröße von Text und Steuerelementen im aktuellen Fenster an.", "zh": "调整当前窗口中文字和控件的整体大小。", "ja": "現在のウィンドウでテキストとコントロールの全体的なサイズを調整します。", "ko": "현재 창에서 텍스트와 컨트롤의 전체 크기를 조정합니다.", "pt": "Ajuste o tamanho geral do texto e dos controlos na janela atual.", "ar": "اضبط الحجم العام للنص وعناصر التحكم في النافذة الحالية."],
        "settingsInheritTerminalTitle": ["en": "Inherit system terminal profile", "ru": "Наследовать профиль системного Terminal", "es": "Heredar perfil del terminal del sistema", "fr": "Hériter du profil du terminal système", "de": "System-Terminalprofil übernehmen", "zh": "继承系统终端配置文件", "ja": "システムターミナルプロファイルを継承", "ko": "시스템 터미널 프로필 상속", "pt": "Herdar perfil do terminal do sistema", "ar": "وراثة ملف تعريف طرفية النظام"],
        "settingsInheritTerminalDescription": ["en": "When launching the built-in terminal, inherit login shell environment, proxy, Kubernetes variables, and local terminal font when possible.", "ru": "При запуске встроенного терминала наследовать окружение shell, proxy, Kubernetes и шрифт Terminal.app, если возможно.", "es": "Al iniciar el terminal integrado, herede el entorno del shell, proxy, variables de Kubernetes y fuente del terminal local cuando sea posible.", "fr": "Lors du lancement du terminal intégré, héritez de l'environnement de connexion, du proxy, des variables Kubernetes et de la police du terminal local lorsque cela est possible.", "de": "Beim Starten des eingebetteten Terminals nach Möglichkeit Login-Shell-Umgebung, Proxy, Kubernetes-Variablen und lokale Terminal-Schriftart übernehmen.", "zh": "启动内置终端时，尽可能继承登录 shell 环境、代理、Kubernetes 变量和本地终端字体。", "ja": "内蔵ターミナルを起動する際、可能であればログインシェル環境、プロキシ、Kubernetes変数、ローカルターミナルフォントを継承します。", "ko": "내장 터미널을 실행할 때, 가능한 경우 로그인 셸 환경, 프록시, Kubernetes 변수 및 로컬 터미널 글꼴을 상속합니다.", "pt": "Ao iniciar o terminal integrado, herdar o ambiente de shell de início de sessão, proxy, variáveis Kubernetes e fonte do terminal local quando possível.", "ar": "عند تشغيل الطرفية المدمجة، قم بوراثة بيئة shell الدخول، والوكيل، ومتغيرات Kubernetes، وخط الطرفية المحلي عند الإمكان."],
        "settingsInputDropdownTitle": ["en": "In-input command palette", "ru": "Командная палитра в поле ввода", "es": "Paleta de comandos en el campo de entrada", "fr": "Palette de commandes dans le champ de saisie", "de": "Befehlspalette im Eingabefeld", "zh": "输入框内命令面板", "ja": "入力欄のコマンドパレット", "ko": "입력 필드의 명령 팔레트", "pt": "Paleta de comandos no campo de entrada", "ar": "لوحة الأوامر داخل حقل الإدخال"],
        "settingsInputDropdownDescription": ["en": "Show the / @ # $ command palette dropdown above the input field.", "ru": "Показывать выпадающую палитру команд / @ # $ над полем ввода.", "es": "Mostrar el menú desplegable de la paleta de comandos / @ # $ sobre el campo de entrada.", "fr": "Afficher la palette de commandes / @ # $ au-dessus du champ de saisie.", "de": "Zeigt die Befehlspalette / @ # $ über dem Eingabefeld an.", "zh": "在输入框上方显示 / @ # $ 命令面板下拉菜单。", "ja": "入力欄の上に / @ # $ コマンドパレットのドロップダウンを表示します。", "ko": "입력 필드 위에 / @ # $ 명령 팔레트 드롭다운을 표시합니다.", "pt": "Mostrar a paleta de comandos / @ # $ acima do campo de entrada.", "ar": "إظهار القائمة المنسدلة للوحة الأوامر / @ # $ فوق حقل الإدخال."],
        "settingsTerminalFontTitle": ["en": "Terminal font", "ru": "Шрифт терминала", "es": "Fuente del terminal", "fr": "Police du terminal", "de": "Terminal-Schriftart", "zh": "终端字体", "ja": "ターミナルフォント", "ko": "터미널 글꼴", "pt": "Fonte do terminal", "ar": "خط الطرفية"],
        "settingsTerminalFontDescription": ["en": "Leave blank to auto-detect system terminal settings; set a value to override the MiMo terminal font.", "ru": "Оставьте пустым для автоопределения; укажите имя шрифта для переопределения.", "es": "Deje en blanco para detectar automáticamente la configuración; establezca un valor para sobrescribir la fuente.", "fr": "Laissez vide pour détecter automatiquement les paramètres ; définissez une valeur pour remplacer la police MiMo.", "de": "Leer lassen zur automatischen Erkennung; setzen Sie einen Wert, um die MiMo-Terminal-Schriftart zu überschreiben.", "zh": "留空以自动检测系统终端设置；设置一个值以覆盖 MiMo 终端字体。", "ja": "空白にするとシステムターミナル設定を自動検出します。MiMoターミナルフォントを上書きする値を設定します。", "ko": "시스템 터미널 설정을 자동 감지하려면 비워두세요. MiMo 터미널 글꼴을 재정의하려면 값을 설정하세요.", "pt": "Deixe em branco para detetar automaticamente as definições do terminal do sistema; defina um valor para substituir a fonte do terminal MiMo.", "ar": "اتركه فارغًا للكشف التلقائي عن إعدادات طرفية النظام؛ حدد قيمة لتجاوز خط طرفية MiMo."],
        "settingsTerminalFontPlaceholder": ["en": "e.g. MesloLGS NF", "ru": "например MesloLGS NF", "es": "p. ej., MesloLGS NF", "fr": "par ex. MesloLGS NF", "de": "z. B. MesloLGS NF", "zh": "例如 MesloLGS NF", "ja": "例: MesloLGS NF", "ko": "예: MesloLGS NF", "pt": "ex.: MesloLGS NF", "ar": "مثال: MesloLGS NF"],
        "settingsTerminalFontCurrentInherited": ["en": "Current: %@ (inherited)", "ru": "Сейчас: %@ (унаследован)", "es": "Actual: %@ (heredado)", "fr": "Actuel : %@ (hérité)", "de": "Aktuell: %@ (übernommen)", "zh": "当前：%@（已继承）", "ja": "現在: %@（継承済み）", "ko": "현재: %@ (상속됨)", "pt": "Atual: %@ (herdado)", "ar": "الحالي: %@ (موروث)"],
        "settingsTerminalFontCurrentOverride": ["en": "Current: %@", "ru": "Сейчас: %@", "es": "Actual: %@", "fr": "Actuel : %@", "de": "Aktuell: %@", "zh": "当前：%@", "ja": "現在: %@", "ko": "현재: %@", "pt": "Atual: %@", "ar": "الحالي: %@"],
        "settingsTabGeneral": ["en": "General", "ru": "Общие", "es": "General", "fr": "Général", "de": "Allgemein", "zh": "通用", "ja": "一般", "ko": "일반", "pt": "Geral", "ar": "عام"],
        "settingsTabCodePreview": ["en": "Code preview", "ru": "Превью кода", "es": "Vista previa del código", "fr": "Aperçu du code", "de": "Code-Vorschau", "zh": "代码预览", "ja": "コードプレビュー", "ko": "코드 미리보기", "pt": "Pré-visualização de código", "ar": "معاينة الكود"],
        "settingsTabModelSettings": ["en": "Model settings", "ru": "Настройки моделей", "es": "Configuración del modelo", "fr": "Paramètres du modèle", "de": "Modelleinstellungen", "zh": "模型设置", "ja": "モデル設定", "ko": "모델 설정", "pt": "Definições do modelo", "ar": "إعدادات النموذج"],
        "settingsTabProviders": ["en": "Providers", "ru": "Провайдеры", "es": "Proveedores", "fr": "Fournisseurs", "de": "Anbieter", "zh": "提供商", "ja": "プロバイダー", "ko": "공급자", "pt": "Fornecedores", "ar": "المقدّمون"],
        "settingsTabSkills": ["en": "Skills", "ru": "Навыки", "es": "Habilidades", "fr": "Compétences", "de": "Fähigkeiten", "zh": "技能", "ja": "スキル", "ko": "스킬", "pt": "Competências", "ar": "المهارات"],
        "settingsTabMCPServers": ["en": "MCP Servers", "ru": "MCP серверы", "es": "Servidores MCP", "fr": "Serveurs MCP", "de": "MCP-Server", "zh": "MCP 服务器", "ja": "MCP サーバー", "ko": "MCP 서버", "pt": "Servidores MCP", "ar": "خوادم MCP"],
        "settingsTabPlugins": ["en": "Plugins", "ru": "Плагины", "es": "Complementos", "fr": "Plugins", "de": "Plugins", "zh": "插件", "ja": "プラグイン", "ko": "플러그인", "pt": "Plugins", "ar": "الإضافات"],
        "settingsTabCommands": ["en": "Commands", "ru": "Команды", "es": "Comandos", "fr": "Commandes", "de": "Befehle", "zh": "命令", "ja": "コマンド", "ko": "명령", "pt": "Comandos", "ar": "الأوامر"],
        "settingsTabIndexing": ["en": "Indexing", "ru": "Индексация", "es": "Indexación", "fr": "Indexation", "de": "Indizierung", "zh": "索引", "ja": "インデックス", "ko": "인덱싱", "pt": "Indexação", "ar": "الفهرسة"],
        "settingsTabUsage": ["en": "Usage", "ru": "Использование", "es": "Uso", "fr": "Utilisation", "de": "Nutzung", "zh": "使用情况", "ja": "使用状況", "ko": "사용량", "pt": "Utilização", "ar": "الاستخدام"],
        "settingsCodePreviewTitle": ["en": "Code preview", "ru": "Предпросмотр кода", "es": "Vista previa de código", "fr": "Aperçu du code", "de": "Code-Vorschau", "zh": "代码预览", "ja": "コードプレビュー", "ko": "코드 미리보기", "pt": "Pré-visualização de código", "ar": "معاينة الكود"],
        "settingsLightCodeThemeTitle": ["en": "Light code theme", "ru": "Светлая тема кода", "es": "Tema de código claro", "fr": "Thème de code clair", "de": "Helles Code-Theme", "zh": "浅色代码主题", "ja": "ライトコードテーマ", "ko": "라이트 코드 테마", "pt": "Tema de código claro", "ar": "سمة الكود الفاتحة"],
        "settingsLightCodeThemeDescription": ["en": "Color scheme for light mode", "ru": "Цветовая схема для светлого режима", "es": "Esquema de colores para el modo claro", "fr": "Palette de couleurs pour le mode clair", "de": "Farbschema für den hellen Modus", "zh": "浅色模式配色方案", "ja": "ライトモードの配色", "ko": "라이트 모드 색 구성", "pt": "Esquema de cores para o modo claro", "ar": "نظام ألوان للوضع الفاتح"],
        "settingsDarkCodeThemeTitle": ["en": "Dark code theme", "ru": "Тёмная тема кода", "es": "Tema de código oscuro", "fr": "Thème de code sombre", "de": "Dunkles Code-Theme", "zh": "深色代码主题", "ja": "ダークコードテーマ", "ko": "다크 코드 테마", "pt": "Tema de código escuro", "ar": "سمة الكود الداكنة"],
        "settingsDarkCodeThemeDescription": ["en": "Color scheme for dark mode", "ru": "Цветовая схема для тёмного режима", "es": "Esquema de colores para el modo oscuro", "fr": "Palette de couleurs pour le mode sombre", "de": "Farbschema für den dunklen Modus", "zh": "深色模式配色方案", "ja": "ダークモードの配色", "ko": "다크 모드 색 구성", "pt": "Esquema de cores para o modo escuro", "ar": "نظام ألوان للوضع الداكن"],
        "settingsShowLineNumbersTitle": ["en": "Show line numbers", "ru": "Показать номера строк", "es": "Mostrar números de línea", "fr": "Afficher les numéros de ligne", "de": "Zeilennummern anzeigen", "zh": "显示行号", "ja": "行番号を表示", "ko": "줄 번호 표시", "pt": "Mostrar números de linha", "ar": "إظهار أرقام الأسطر"],
        "settingsShowLineNumbersDescription": ["en": "Display line numbers in the code editor", "ru": "Отображать номера строк в редакторе кода", "es": "Mostrar números de línea en el editor de código", "fr": "Afficher les numéros de ligne dans l'éditeur de code", "de": "Zeilennummern im Code-Editor anzeigen", "zh": "在代码编辑器中显示行号", "ja": "コードエディターに行番号を表示", "ko": "코드 편집기에 줄 번호 표시", "pt": "Exibir números de linha no editor de código", "ar": "عرض أرقام الأسطر في محرر الكود"],
        "settingsWrapLongLinesTitle": ["en": "Wrap long lines", "ru": "Перенос длинных строк", "es": "Ajustar líneas largas", "fr": "Renvoyer les longues lignes", "de": "Lange Zeilen umbrechen", "zh": "自动换行", "ja": "長い行を折り返す", "ko": "긴 줄 줄 바꿈", "pt": "Quebrar linhas longas", "ar": "التفاف الأسطر الطويلة"],
        "settingsWrapLongLinesDescription": ["en": "Automatically wrap lines that exceed the screen width", "ru": "Автоматический перенос строк, выходящих за ширину экрана", "es": "Ajustar automáticamente las líneas que superan el ancho de pantalla", "fr": "Renvoi automatique des lignes dépassant la largeur de l'écran", "de": "Zeilen automatisch umbrechen, die die Bildschirmbreite überschreiten", "zh": "自动换行超出屏幕宽度的行", "ja": "画面幅を超える行を自動的に折り返す", "ko": "화면 너비를 초과하는 줄을 자동으로 줄 바꿈", "pt": "Quebrar automaticamente linhas que excedem a largura da tela", "ar": "التفاف تلقائي للأسطر التي تتجاوز عرض الشاشة"],
        "settingsCodeFontSizeTitle": ["en": "Code font size", "ru": "Размер шрифта кода", "es": "Tamaño de fuente del código", "fr": "Taille de police du code", "de": "Code-Schriftgröße", "zh": "代码字体大小", "ja": "コードのフォントサイズ", "ko": "코드 글꼴 크기", "pt": "Tamanho da fonte do código", "ar": "حجم خط الكود"],
        "settingsCodeFontSizeDescription": ["en": "Font size in the code editor", "ru": "Размер шрифта в редакторе кода", "es": "Tamaño de fuente en el editor de código", "fr": "Taille de police dans l'éditeur de code", "de": "Schriftgröße im Code-Editor", "zh": "代码编辑器中的字体大小", "ja": "コードエディターのフォントサイズ", "ko": "코드 편집기의 글꼴 크기", "pt": "Tamanho da fonte no editor de código", "ar": "حجم الخط في محرر الكود"],
        "settingsModelSettingsTitle": ["en": "Model settings", "ru": "Настройки модели", "es": "Configuración del modelo", "fr": "Paramètres du modèle", "de": "Modelleinstellungen", "zh": "模型设置", "ja": "モデル設定", "ko": "모델 설정", "pt": "Configurações do modelo", "ar": "إعدادات النموذج"],
        "settingsModelSettingsDescription": ["en": "Configuration of the AI model and generation parameters", "ru": "Конфигурация AI-модели и параметров генерации", "es": "Configuración del modelo de IA y parámetros de generación", "fr": "Configuration du modèle IA et des paramètres de génération", "de": "Konfiguration des KI-Modells und der Generierungsparameter", "zh": "AI 模型与生成参数的配置", "ja": "AIモデルと生成パラメーターの設定", "ko": "AI 모델 및 생성 매개변수 구성", "pt": "Configuração do modelo de IA e parâmetros de geração", "ar": "إعداد نموذج الذكاء الاصطناعي ومعلمات التوليد"],
        "settingsSkillsTitle": ["en": "Skills", "ru": "Навыки", "es": "Habilidades", "fr": "Compétences", "de": "Skills", "zh": "技能", "ja": "スキル", "ko": "스킬", "pt": "Habilidades", "ar": "المهارات"],
        "settingsSkillsDescription": ["en": "Manage agent skills", "ru": "Управление навыками агента", "es": "Administrar habilidades del agente", "fr": "Gérer les compétences de l'agent", "de": "Agent-Skills verwalten", "zh": "管理代理技能", "ja": "エージェントのスキルを管理", "ko": "에이전트 스킬 관리", "pt": "Gerenciar habilidades do agente", "ar": "إدارة مهارات الوكيل"],
        "settingsSearchSkillsPlaceholder": ["en": "Search skills", "ru": "Поиск навыков", "es": "Buscar habilidades", "fr": "Rechercher des compétences", "de": "Skills suchen", "zh": "搜索技能", "ja": "スキルを検索", "ko": "스킬 검색", "pt": "Pesquisar habilidades", "ar": "البحث عن المهارات"],
        "settingsNoSkillsInstalled": ["en": "No skills installed", "ru": "Навыки не установлены", "es": "No hay habilidades instaladas", "fr": "Aucune compétence installée", "de": "Keine Skills installiert", "zh": "未安装技能", "ja": "インストール済みのスキルがありません", "ko": "설치된 스킬이 없습니다", "pt": "Nenhuma habilidade instalada", "ar": "لا توجد مهارات مثبتة"],
        "settingsNoSkillsInstalledSubtitle": ["en": "Place skill files in ~/.mycoder/skills", "ru": "Поместите файлы навыков в ~/.mycoder/skills", "es": "Coloque los archivos de habilidades en ~/.mycoder/skills", "fr": "Placez les fichiers de compétences dans ~/.mycoder/skills", "de": "Legen Sie Skill-Dateien unter ~/.mycoder/skills ab", "zh": "将技能文件放入 ~/.mycoder/skills", "ja": "~/.mycoder/skills にスキルファイルを配置してください", "ko": "스킬 파일을 ~/.mycoder/skills에 넣으세요", "pt": "Coloque os arquivos de habilidades em ~/.mycoder/skills", "ar": "ضع ملفات المهارات في ~/.mycoder/skills"],
        "settingsMCPServersTitle": ["en": "MCP servers", "ru": "MCP-серверы", "es": "Servidores MCP", "fr": "Serveurs MCP", "de": "MCP-Server", "zh": "MCP 服务器", "ja": "MCPサーバー", "ko": "MCP 서버", "pt": "Servidores MCP", "ar": "خوادم MCP"],
        "settingsMCPServersDescription": ["en": "Manage Model Context Protocol servers", "ru": "Управление серверами Model Context Protocol", "es": "Administrar servidores del Model Context Protocol", "fr": "Gérer les serveurs du Model Context Protocol", "de": "Model Context Protocol-Server verwalten", "zh": "管理 Model Context Protocol 服务器", "ja": "Model Context Protocol サーバーを管理", "ko": "Model Context Protocol 서버 관리", "pt": "Gerenciar servidores do Model Context Protocol", "ar": "إدارة خوادم بروتوكول سياق النموذج"],
        "settingsSearchMCPServersPlaceholder": ["en": "Search MCP servers", "ru": "Поиск MCP-серверов", "es": "Buscar servidores MCP", "fr": "Rechercher des serveurs MCP", "de": "MCP-Server suchen", "zh": "搜索 MCP 服务器", "ja": "MCPサーバーを検索", "ko": "MCP 서버 검색", "pt": "Pesquisar servidores MCP", "ar": "البحث عن خوادم MCP"],
        "settingsNoMCPServersConfigured": ["en": "No MCP servers configured", "ru": "MCP-серверы не настроены", "es": "No hay servidores MCP configurados", "fr": "Aucun serveur MCP configuré", "de": "Keine MCP-Server konfiguriert", "zh": "未配置 MCP 服务器", "ja": "MCPサーバーが設定されていません", "ko": "구성된 MCP 서버가 없습니다", "pt": "Nenhum servidor MCP configurado", "ar": "لا توجد خوادم MCP مكونة"],
        "settingsNoMCPServersConfiguredSubtitle": ["en": "Add a configuration in ~/.mycoder/mcp.json", "ru": "Добавьте конфигурацию в ~/.mycoder/mcp.json", "es": "Agregue una configuración en ~/.mycoder/mcp.json", "fr": "Ajoutez une configuration dans ~/.mycoder/mcp.json", "de": "Fügen Sie eine Konfiguration in ~/.mycoder/mcp.json hinzu", "zh": "在 ~/.mycoder/mcp.json 中添加配置", "ja": "~/.mycoder/mcp.json に設定を追加してください", "ko": "~/.mycoder/mcp.json에 구성을 추가하세요", "pt": "Adicione uma configuração em ~/.mycoder/mcp.json", "ar": "أضف إعدادًا في ~/.mycoder/mcp.json"],
        "settingsPluginsTitle": ["en": "Plugins", "ru": "Плагины", "es": "Complementos", "fr": "Plugins", "de": "Plugins", "zh": "插件", "ja": "プラグイン", "ko": "플러그인", "pt": "Plugins", "ar": "الإضافات"],
        "settingsPluginsDescription": ["en": "Manage myCoder plugins", "ru": "Управление плагинами myCoder", "es": "Administrar los complementos de myCoder", "fr": "Gérer les plugins myCoder", "de": "myCoder-Plugins verwalten", "zh": "管理 myCoder 插件", "ja": "myCoder プラグインを管理", "ko": "myCoder 플러그인 관리", "pt": "Gerenciar plugins do myCoder", "ar": "إدارة إضافات myCoder"],
        "settingsSearchPluginsPlaceholder": ["en": "Search plugins", "ru": "Поиск плагинов", "es": "Buscar complementos", "fr": "Rechercher des plugins", "de": "Plugins suchen", "zh": "搜索插件", "ja": "プラグインを検索", "ko": "플러그인 검색", "pt": "Pesquisar plugins", "ar": "البحث عن الإضافات"],
        "settingsNoPluginsInstalled": ["en": "No plugins installed", "ru": "Плагины не установлены", "es": "No hay complementos instalados", "fr": "Aucun plugin installé", "de": "Keine Plugins installiert", "zh": "未安装插件", "ja": "インストール済みのプラグインがありません", "ko": "설치된 플러그인이 없습니다", "pt": "Nenhum plugin instalado", "ar": "لا توجد إضافات مثبتة"],
        "settingsNoPluginsInstalledSubtitle": ["en": "Place plugins in ~/.mycoder/plugins", "ru": "Поместите плагины в ~/.mycoder/plugins", "es": "Coloque los complementos en ~/.mycoder/plugins", "fr": "Placez les plugins dans ~/.mycoder/plugins", "de": "Legen Sie Plugins unter ~/.mycoder/plugins ab", "zh": "将插件放入 ~/.mycoder/plugins", "ja": "~/.mycoder/plugins にプラグインを配置してください", "ko": "플러그인을 ~/.mycoder/plugins에 넣으세요", "pt": "Coloque os plugins em ~/.mycoder/plugins", "ar": "ضع الإضافات في ~/.mycoder/plugins"],
        "settingsEnabled": ["en": "Enabled", "ru": "Включено", "es": "Habilitado", "fr": "Activé", "de": "Aktiviert", "zh": "已启用", "ja": "有効", "ko": "활성화됨", "pt": "Ativado", "ar": "مفعّل"],
        "settingsDisabled": ["en": "Disabled", "ru": "Выключено", "es": "Deshabilitado", "fr": "Désactivé", "de": "Deaktiviert", "zh": "已禁用", "ja": "無効", "ko": "비활성화됨", "pt": "Desativado", "ar": "معطّل"],
        "settingsCommandsTitle": ["en": "Commands", "ru": "Команды", "es": "Comandos", "fr": "Commandes", "de": "Befehle", "zh": "命令", "ja": "コマンド", "ko": "명령", "pt": "Comandos", "ar": "الأوامر"],
        "settingsCommandsDescription": ["en": "Manage the agent's user commands", "ru": "Управление пользовательскими командами агента", "es": "Administrar los comandos de usuario del agente", "fr": "Gérer les commandes utilisateur de l'agent", "de": "Benutzerbefehle des Agenten verwalten", "zh": "管理代理的用户命令", "ja": "エージェントのユーザーコマンドを管理", "ko": "에이전트 사용자 명령 관리", "pt": "Gerenciar comandos de usuário do agente", "ar": "إدارة أوامر المستخدم للوكيل"],
        "settingsSearchCommandsPlaceholder": ["en": "Search commands", "ru": "Поиск команд", "es": "Buscar comandos", "fr": "Rechercher des commandes", "de": "Befehle suchen", "zh": "搜索命令", "ja": "コマンドを検索", "ko": "명령 검색", "pt": "Pesquisar comandos", "ar": "البحث عن الأوامر"],
        "settingsNoUserCommands": ["en": "No user commands", "ru": "Пользовательские команды отсутствуют", "es": "No hay comandos de usuario", "fr": "Aucune commande utilisateur", "de": "Keine Benutzerbefehle", "zh": "没有用户命令", "ja": "ユーザーコマンドがありません", "ko": "사용자 명령이 없습니다", "pt": "Nenhum comando de usuário", "ar": "لا توجد أوامر مستخدم"],
        "settingsNoUserCommandsSubtitle": ["en": "Create command files in ~/.mycoder/commands", "ru": "Создайте файлы команд в ~/.mycoder/commands", "es": "Cree archivos de comandos en ~/.mycoder/commands", "fr": "Créez des fichiers de commandes dans ~/.mycoder/commands", "de": "Erstellen Sie Befehlsdateien unter ~/.mycoder/commands", "zh": "在 ~/.mycoder/commands 中创建命令文件", "ja": "~/.mycoder/commands にコマンドファイルを作成してください", "ko": "~/.mycoder/commands에 명령 파일을 만드세요", "pt": "Crie arquivos de comandos em ~/.mycoder/commands", "ar": "أنشئ ملفات الأوامر في ~/.mycoder/commands"],
        "settingsIndexingTitle": ["en": "Indexing", "ru": "Индексация", "es": "Indexación", "fr": "Indexation", "de": "Indizierung", "zh": "索引", "ja": "インデックス", "ko": "인덱싱", "pt": "Indexação", "ar": "الفهرسة"],
        "settingsIndexingCodebaseTitle": ["en": "Codebase indexing", "ru": "Индексация кодовой базы", "es": "Indexación del código fuente", "fr": "Indexation de la base de code", "de": "Codebasis-Indexierung", "zh": "代码库索引", "ja": "コードベースのインデックス", "ko": "코드베이스 인덱싱", "pt": "Indexação da base de código", "ar": "فهرسة قاعدة الكود"],
        "settingsIndexNewFoldersTitle": ["en": "Index new folders", "ru": "Индексировать новые папки", "es": "Indexar nuevas carpetas", "fr": "Indexer les nouveaux dossiers", "de": "Neue Ordner indexieren", "zh": "索引新文件夹", "ja": "新しいフォルダーをインデックス", "ko": "새 폴더 인덱싱", "pt": "Indexar novas pastas", "ar": "فهرسة المجلدات الجديدة"],
        "settingsIndexNewFoldersDescription": ["en": "Automatically index newly added folders", "ru": "Автоматически индексировать вновь добавленные папки", "es": "Indexar automáticamente las carpetas recién agregadas", "fr": "Indexer automatiquement les dossiers récemment ajoutés", "de": "Neu hinzugefügte Ordner automatisch indexieren", "zh": "自动索引新添加的文件夹", "ja": "新しく追加されたフォルダーを自動的にインデックス", "ko": "새로 추가된 폴더를 자동으로 인덱싱", "pt": "Indexar automaticamente pastas recém-adicionadas", "ar": "فهرسة تلقائية للمجلدات المضافة حديثًا"],
        "settingsIndexRepositoriesTitle": ["en": "Index repositories", "ru": "Индексировать репозитории", "es": "Indexar repositorios", "fr": "Indexer les dépôts", "de": "Repositorys indexieren", "zh": "索引仓库", "ja": "リポジトリをインデックス", "ko": "저장소 인덱싱", "pt": "Indexar repositórios", "ar": "فهرسة المستودعات"],
        "settingsIndexRepositoriesDescription": ["en": "Index git repositories in the workspace", "ru": "Индексировать git-репозитории в рабочей области", "es": "Indexar repositorios git en el área de trabajo", "fr": "Indexer les dépôts git dans l'espace de travail", "de": "Git-Repositorys im Arbeitsbereich indexieren", "zh": "索引工作区中的 Git 仓库", "ja": "ワークスペース内の Git リポジトリをインデックス", "ko": "작업 공간의 git 저장소 인덱싱", "pt": "Indexar repositórios git na área de trabalho", "ar": "فهرسة مستودعات git في مساحة العمل"],
        "settingsStorageTitle": ["en": "Storage", "ru": "Хранилище", "es": "Almacenamiento", "fr": "Stockage", "de": "Speicher", "zh": "存储", "ja": "ストレージ", "ko": "저장소", "pt": "Armazenamento", "ar": "التخزين"],
        "settingsUsageTitle": ["en": "Usage", "ru": "Статистика", "es": "Uso", "fr": "Utilisation", "de": "Nutzung", "zh": "用量", "ja": "使用状況", "ko": "사용량", "pt": "Uso", "ar": "الاستخدام"],
        "settingsUsageSubtitle": ["en": "Overview of token and model usage", "ru": "Обзор использования токенов и моделей", "es": "Resumen del uso de tokens y modelos", "fr": "Aperçu de l'utilisation des jetons et des modèles", "de": "Übersicht über Token- und Modellnutzung", "zh": "令牌与模型使用概览", "ja": "トークンとモデルの使用状況の概要", "ko": "토큰 및 모델 사용 개요", "pt": "Visão geral do uso de tokens e modelos", "ar": "نظرة عامة على استخدام الرموز والنماذج"],
        "settingsUsageTimeRange": ["en": "Time range", "ru": "Период", "es": "Período", "fr": "Période", "de": "Zeitraum", "zh": "时间范围", "ja": "期間", "ko": "기간", "pt": "Período", "ar": "النطاق الزمني"],
        "settingsUsageTotalTokens": ["en": "Total tokens", "ru": "Всего токенов", "es": "Tokens totales", "fr": "Jetons au total", "de": "Tokens gesamt", "zh": "总令牌数", "ja": "合計トークン", "ko": "총 토큰", "pt": "Total de tokens", "ar": "إجمالي الرموز"],
        "settingsUsageTotalCost": ["en": "Total cost", "ru": "Общая стоимость", "es": "Costo total", "fr": "Coût total", "de": "Gesamtkosten", "zh": "总成本", "ja": "合計コスト", "ko": "총 비용", "pt": "Custo total", "ar": "التكلفة الإجمالية"],
        "settingsUsageMessages": ["en": "Messages", "ru": "Сообщения", "es": "Mensajes", "fr": "Messages", "de": "Nachrichten", "zh": "消息", "ja": "メッセージ", "ko": "메시지", "pt": "Mensagens", "ar": "الرسائل"],
        "settingsUsageActiveDays": ["en": "Active days", "ru": "Активные дни", "es": "Días activos", "fr": "Jours actifs", "de": "Aktive Tage", "zh": "活跃天数", "ja": "アクティブ日数", "ko": "활성 일수", "pt": "Dias ativos", "ar": "الأيام النشطة"],
        "settingsUsageDatabaseSize": ["en": "Database size", "ru": "Размер базы данных", "es": "Tamaño de la base de datos", "fr": "Taille de la base de données", "de": "Datenbankgröße", "zh": "数据库大小", "ja": "データベースサイズ", "ko": "데이터베이스 크기", "pt": "Tamanho do banco de dados", "ar": "حجم قاعدة البيانات"],
        "settingsUsageFavoriteModel": ["en": "Favorite model", "ru": "Основная модель", "es": "Modelo favorito", "fr": "Modèle favori", "de": "Bevorzugtes Modell", "zh": "常用模型", "ja": "お気に入りモデル", "ko": "즐겨찾는 모델", "pt": "Modelo favorito", "ar": "النموذج المفضل"],
        "settingsUsageFavoriteModelSubtitle": ["en": "The model used most often", "ru": "Модель, используемая чаще всего", "es": "El modelo más utilizado", "fr": "Le modèle le plus utilisé", "de": "Das am häufigsten verwendete Modell", "zh": "使用最频繁的模型", "ja": "最もよく使用されるモデル", "ko": "가장 자주 사용되는 모델", "pt": "O modelo mais usado", "ar": "النموذج الأكثر استخدامًا"],
        "settingsUsageByModel": ["en": "By model", "ru": "По моделям", "es": "Por modelo", "fr": "Par modèle", "de": "Nach Modell", "zh": "按模型", "ja": "モデル別", "ko": "모델별", "pt": "Por modelo", "ar": "حسب النموذج"],
        "settingsUsageNoData": ["en": "No data", "ru": "Нет данных", "es": "Sin datos", "fr": "Aucune donnée", "de": "Keine Daten", "zh": "暂无数据", "ja": "データがありません", "ko": "데이터 없음", "pt": "Sem dados", "ar": "لا توجد بيانات"],
        "settingsLocalProvidersTitle": ["en": "Local providers", "ru": "Локальные провайдеры", "es": "Proveedores locales", "fr": "Fournisseurs locaux", "de": "Lokale Anbieter", "zh": "本地提供商", "ja": "ローカルプロバイダー", "ko": "로컬 공급자", "pt": "Provedores locais", "ar": "المزودون المحليون"],
        "settingsLocalProvidersDescription": ["en": "Providers running on this computer", "ru": "Провайдеры, запущенные на этом компьютере", "es": "Proveedores que se ejecutan en esta computadora", "fr": "Fournisseurs exécutés sur cet ordinateur", "de": "Auf diesem Computer laufende Anbieter", "zh": "在此计算机上运行的提供商", "ja": "このコンピューターで実行中のプロバイダー", "ko": "이 컴퓨터에서 실행 중인 공급자", "pt": "Provedores em execução neste computador", "ar": "المزودون الذين يعملون على هذا الكمبيوتر"],
        "settingsLocalProvidersAddressPlaceholder": ["en": "Address (host:port)", "ru": "Адрес (host:port)", "es": "Dirección (host:puerto)", "fr": "Adresse (hôte:port)", "de": "Adresse (Host:Port)", "zh": "地址（host:port）", "ja": "アドレス（host:port）", "ko": "주소 (host:port)", "pt": "Endereço (host:port)", "ar": "العنوان (host:port)"],
        "settingsLocalProvidersAutoDetect": ["en": "Auto-detect", "ru": "Автоопределение", "es": "Detección automática", "fr": "Détection automatique", "de": "Automatisch erkennen", "zh": "自动检测", "ja": "自動検出", "ko": "자동 감지", "pt": "Detecção automática", "ar": "كشف تلقائي"],
        "settingsLocalProvidersDetecting": ["en": "Detecting...", "ru": "Определение...", "es": "Detectando...", "fr": "Détection...", "de": "Wird erkannt...", "zh": "正在检测…", "ja": "検出中…", "ko": "감지 중...", "pt": "A detetar...", "ar": "جارٍ الكشف..."],
        "settingsLocalProvidersAdded": ["en": "Added", "ru": "Добавлено", "es": "Agregado", "fr": "Ajouté", "de": "Hinzugefügt", "zh": "已添加", "ja": "追加済み", "ko": "추가됨", "pt": "Adicionado", "ar": "تمت الإضافة"],
        "settingsLocalProvidersAdd": ["en": "Add", "ru": "Добавить", "es": "Agregar", "fr": "Ajouter", "de": "Hinzufügen", "zh": "添加", "ja": "追加", "ko": "추가", "pt": "Adicionar", "ar": "إضافة"],
        "settingsLocalProvidersEnabled": ["en": "Enabled", "ru": "Включён", "es": "Habilitado", "fr": "Activé", "de": "Aktiviert", "zh": "已启用", "ja": "有効", "ko": "활성화됨", "pt": "Ativado", "ar": "مفعّل"],
        "settingsLocalProvidersDisabled": ["en": "Disabled", "ru": "Выключен", "es": "Deshabilitado", "fr": "Désactivé", "de": "Deaktiviert", "zh": "已禁用", "ja": "無効", "ko": "비활성화됨", "pt": "Desativado", "ar": "معطّل"],
        "settingsProvidersTitle": ["en": "Providers", "ru": "Провайдеры", "es": "Proveedores", "fr": "Fournisseurs", "de": "Anbieter", "zh": "提供商", "ja": "プロバイダー", "ko": "공급자", "pt": "Provedores", "ar": "المزودون"],
        "settingsProvidersDescription": ["en": "Manage external API providers", "ru": "Управление внешними API-провайдерами", "es": "Administrar proveedores de API externos", "fr": "Gérer les fournisseurs d'API externes", "de": "Externe API-Anbieter verwalten", "zh": "管理外部 API 提供商", "ja": "外部 API プロバイダーを管理", "ko": "외부 API 공급자 관리", "pt": "Gerenciar provedores de API externos", "ar": "إدارة مزودي واجهات برمجة التطبيقات الخارجية"],
        "settingsProvidersStatsProviders": ["en": "Providers", "ru": "Провайдеры", "es": "Proveedores", "fr": "Fournisseurs", "de": "Anbieter", "zh": "提供商", "ja": "プロバイダー", "ko": "공급자", "pt": "Provedores", "ar": "المزودون"],
        "settingsProvidersStatsModels": ["en": "Models", "ru": "Модели", "es": "Modelos", "fr": "Modèles", "de": "Modelle", "zh": "模型", "ja": "モデル", "ko": "모델", "pt": "Modelos", "ar": "النماذج"],
        "settingsProvidersSearchPlaceholder": ["en": "Search providers", "ru": "Поиск провайдеров", "es": "Buscar proveedores", "fr": "Rechercher des fournisseurs", "de": "Anbieter suchen", "zh": "搜索提供商", "ja": "プロバイダーを検索", "ko": "공급자 검색", "pt": "Pesquisar provedores", "ar": "البحث عن المزودين"],
        "settingsProvidersAdd": ["en": "Add provider", "ru": "Добавить провайдер", "es": "Agregar proveedor", "fr": "Ajouter un fournisseur", "de": "Anbieter hinzufügen", "zh": "添加提供商", "ja": "プロバイダーを追加", "ko": "공급자 추가", "pt": "Adicionar provedor", "ar": "إضافة مزود"],
        "settingsProvidersNoProviders": ["en": "No providers added", "ru": "Провайдеры не добавлены", "es": "No hay proveedores agregados", "fr": "Aucun fournisseur ajouté", "de": "Keine Anbieter hinzugefügt", "zh": "未添加提供商", "ja": "プロバイダーが追加されていません", "ko": "추가된 공급자가 없습니다", "pt": "Nenhum provedor adicionado", "ar": "لا توجد مزودون مضافون"],
        "settingsProvidersModelsCount": ["en": "models", "ru": "моделей", "es": "modelos", "fr": "modèles", "de": "Modelle", "zh": "个模型", "ja": "モデル", "ko": "개 모델", "pt": "modelos", "ar": "نموذج"],
        "settingsProvidersToolsEnabled": ["en": "Tools enabled", "ru": "Инструменты включены", "es": "Herramientas habilitadas", "fr": "Outils activés", "de": "Werkzeuge aktiviert", "zh": "工具已启用", "ja": "ツール有効", "ko": "도구 활성화됨", "pt": "Ferramentas ativadas", "ar": "الأدوات مفعّلة"],
        "settingsProvidersACPEnabled": ["en": "ACP enabled", "ru": "ACP включён", "es": "ACP habilitado", "fr": "ACP activé", "de": "ACP aktiviert", "zh": "已启用 ACP", "ja": "ACP 有効", "ko": "ACP 활성화됨", "pt": "ACP ativado", "ar": "ACP مفعّل"],
        "settingsProvidersRemove": ["en": "Remove", "ru": "Удалить", "es": "Eliminar", "fr": "Supprimer", "de": "Entfernen", "zh": "移除", "ja": "削除", "ko": "제거", "pt": "Remover", "ar": "إزالة"],
        "settingsConfirm": ["en": "Confirm", "ru": "Подтвердить", "es": "Confirmar", "fr": "Confirmer", "de": "Bestätigen", "zh": "确认", "ja": "確認", "ko": "확인", "pt": "Confirmar", "ar": "تأكيد"],
        "settingsCancel": ["en": "Cancel", "ru": "Отмена", "es": "Cancelar", "fr": "Annuler", "de": "Abbrechen", "zh": "取消", "ja": "キャンセル", "ko": "취소", "pt": "Cancelar", "ar": "إلغاء"],
        "settingsRemove": ["en": "Remove", "ru": "Удалить", "es": "Eliminar", "fr": "Supprimer", "de": "Entfernen", "zh": "移除", "ja": "削除", "ko": "제거", "pt": "Remover", "ar": "إزالة"],
        "settingsDelete": ["en": "Delete", "ru": "Удалить", "es": "Eliminar", "fr": "Supprimer", "de": "Löschen", "zh": "删除", "ja": "削除", "ko": "삭제", "pt": "Eliminar", "ar": "حذف"],
        "settingsArchive": ["en": "Archive", "ru": "Архивировать", "es": "Archivar", "fr": "Archiver", "de": "Archivieren", "zh": "归档", "ja": "アーカイブ", "ko": "보관", "pt": "Arquivar", "ar": "أرشفة"],
        "settingsRestore": ["en": "Restore", "ru": "Восстановить", "es": "Restaurar", "fr": "Restaurer", "de": "Wiederherstellen", "zh": "恢复", "ja": "復元", "ko": "복원", "pt": "Restaurar", "ar": "استعادة"],
        "settingsFindNewPath": ["en": "Find new path", "ru": "Найти новый путь", "es": "Buscar nueva ruta", "fr": "Trouver un nouveau chemin", "de": "Neuen Pfad suchen", "zh": "查找新路径", "ja": "新しいパスを探す", "ko": "새 경로 찾기", "pt": "Encontrar novo caminho", "ar": "البحث عن مسار جديد"],
        "settingsExportBackup": ["en": "Export backup", "ru": "Экспорт бэкапа", "es": "Exportar copia de seguridad", "fr": "Exporter la sauvegarde", "de": "Backup exportieren", "zh": "导出备份", "ja": "バックアップをエクスポート", "ko": "백업 내보내기", "pt": "Exportar backup", "ar": "تصدير النسخة الاحتياطية"],
        "settingsImportBackup": ["en": "Import backup", "ru": "Импорт бэкапа", "es": "Importar copia de seguridad", "fr": "Importer la sauvegarde", "de": "Backup importieren", "zh": "导入备份", "ja": "バックアップをインポート", "ko": "백업 가져오기", "pt": "Importar backup", "ar": "استيراد النسخة الاحتياطية"],
        "settingsCompress": ["en": "Compress", "ru": "Сжать", "es": "Comprimir", "fr": "Compresser", "de": "Komprimieren", "zh": "压缩", "ja": "圧縮", "ko": "압축", "pt": "Comprimir", "ar": "ضغط"],
        "settingsArchiveNow": ["en": "Archive now", "ru": "Архивировать сейчас", "es": "Archivar ahora", "fr": "Archiver maintenant", "de": "Jetzt archivieren", "zh": "立即归档", "ja": "今すぐアーカイブ", "ko": "지금 보관", "pt": "Arquivar agora", "ar": "أرشفة الآن"],
        "settingsDeleteOlderThan": ["en": "Delete older than", "ru": "Удалить старше", "es": "Eliminar más antiguos que", "fr": "Supprimer plus anciens que", "de": "Älter als löschen", "zh": "删除早于", "ja": "より古いものを削除", "ko": "보다 오래된 항목 삭제", "pt": "Eliminar mais antigos que", "ar": "حذف الأقدم من"],
        "settingsTypeNameToConfirm": ["en": "Type the name to confirm", "ru": "Введите название для подтверждения", "es": "Escriba el nombre para confirmar", "fr": "Saisissez le nom pour confirmer", "de": "Geben Sie den Namen zur Bestätigung ein", "zh": "输入名称以确认", "ja": "確認のため名前を入力してください", "ko": "확인을 위해 이름을 입력하세요", "pt": "Digite o nome para confirmar", "ar": "اكتب الاسم للتأكيد"],
        "settingsDeleteProjectDescription": ["en": "This action cannot be undone. All project chats and files will be deleted.", "ru": "Это действие необратимо. Все чаты и файлы проекта будут удалены.", "es": "Esta acción no se puede deshacer. Se eliminarán todos los chats y archivos del proyecto.", "fr": "Cette action est irréversible. Tous les chats et fichiers du projet seront supprimés.", "de": "Diese Aktion kann nicht rückgängig gemacht werden. Alle Projekt-Chats und -Dateien werden gelöscht.", "zh": "此操作无法撤销。项目中的所有聊天和文件都将被删除。", "ja": "この操作は元に戻せません。プロジェクトのすべてのチャットとファイルが削除されます。", "ko": "이 작업은 되돌릴 수 없습니다. 프로젝트의 모든 채팅과 파일이 삭제됩니다.", "pt": "Esta ação não pode ser desfeita. Todos os chats e arquivos do projeto serão excluídos.", "ar": "لا يمكن التراجع عن هذا الإجراء. سيتم حذف جميع محادثات وملفات المشروع."],
        "settingsStorageQuotaExceeded": ["en": "Storage quota exceeded", "ru": "Превышена квота хранилища", "es": "Cuota de almacenamiento superada", "fr": "Quota de stockage dépassé", "de": "Speicherkontingent überschritten", "zh": "超出存储配额", "ja": "ストレージ容量を超えました", "ko": "저장소 할당량 초과", "pt": "Cota de armazenamento excedida", "ar": "تم تجاوز حصة التخزين"],
        "settingsStorageQuotaDescription": ["en": "Free up space by archiving or deleting old projects.", "ru": "Освободите место, архивируя или удаляя старые проекты.", "es": "Libere espacio archivando o eliminando proyectos antiguos.", "fr": "Libérez de l'espace en archivant ou supprimant les anciens projets.", "de": "Geben Sie Speicherplatz frei, indem Sie alte Projekte archivieren oder löschen.", "zh": "通过归档或删除旧项目来释放空间。", "ja": "古いプロジェクトをアーカイブまたは削除して容量を確保してください。", "ko": "오래된 프로젝트를 보관하거나 삭제하여 공간을 확보하세요.", "pt": "Libere espaço arquivando ou excluindo projetos antigos.", "ar": "وفّر مساحة عن طريق أرشفة أو حذف المشاريع القديمة."],
        "settingsStorageQuotaArchiveInactive": ["en": "Archive inactive projects", "ru": "Архивировать неактивные проекты", "es": "Archivar proyectos inactivos", "fr": "Archiver les projets inactifs", "de": "Inaktive Projekte archivieren", "zh": "归档非活动项目", "ja": "非アクティブなプロジェクトをアーカイブ", "ko": "비활성 프로젝트 보관", "pt": "Arquivar projetos inativos", "ar": "أرشفة المشاريع غير النشطة"],
        "settingsNoProjectsRegistered": ["en": "No registered projects", "ru": "Нет зарегистрированных проектов", "es": "No hay proyectos registrados", "fr": "Aucun projet enregistré", "de": "Keine registrierten Projekte", "zh": "没有已注册的项目", "ja": "登録されたプロジェクトがありません", "ko": "등록된 프로젝트가 없습니다", "pt": "Nenhum projeto registrado", "ar": "لا توجد مشاريع مسجلة"],
        "settingsActive": ["en": "Active", "ru": "Активный", "es": "Activo", "fr": "Actif", "de": "Aktiv", "zh": "活跃", "ja": "アクティブ", "ko": "활성", "pt": "Ativo", "ar": "نشط"],
        "settingsArchived": ["en": "Archived", "ru": "Архивирован", "es": "Archivado", "fr": "Archivé", "de": "Archiviert", "zh": "已归档", "ja": "アーカイブ済み", "ko": "보관됨", "pt": "Arquivado", "ar": "مؤرشف"],
        "settingsOrphaned": ["en": "Orphaned", "ru": "Потерянный", "es": "Huérfano", "fr": "Orphelin", "de": "Verwaist", "zh": "孤立", "ja": "孤立", "ko": "고아", "pt": "Órfão", "ar": "يتيم"],
        "settingsAutoArchiveDescription": ["en": "Automatically archive inactive projects", "ru": "Автоматически архивировать неактивные проекты", "es": "Archivar automáticamente los proyectos inactivos", "fr": "Archiver automatiquement les projets inactifs", "de": "Inaktive Projekte automatisch archivieren", "zh": "自动归档非活动项目", "ja": "非アクティブなプロジェクトを自動的にアーカイブ", "ko": "비활성 프로젝트를 자동으로 보관", "pt": "Arquivar automaticamente projetos inativos", "ar": "أرشفة تلقائية للمشاريع غير النشطة"],
        "settingsArchiveAfter": ["en": "Archive after", "ru": "Архивировать после", "es": "Archivar después de", "fr": "Archiver après", "de": "Archivieren nach", "zh": "归档时间", "ja": "アーカイブ期限", "ko": "보관 기준", "pt": "Arquivar após", "ar": "الأرشفة بعد"],
        "settingsCleanupTitle": ["en": "Cleanup", "ru": "Очистка", "es": "Limpieza", "fr": "Nettoyage", "de": "Bereinigung", "zh": "清理", "ja": "クリーンアップ", "ko": "정리", "pt": "Limpeza", "ar": "التنظيف"],
        "settingsCleanupDeleteChatsOlderThan": ["en": "Delete chats older than", "ru": "Удалить чаты старше", "es": "Eliminar chats más antiguos que", "fr": "Supprimer les conversations plus anciennes que", "de": "Chats löschen, die älter sind als", "zh": "删除早于以下时间的聊天", "ja": "より古いチャットを削除", "ko": "다음보다 오래된 채팅 삭제", "pt": "Eliminar conversas mais antigas que", "ar": "حذف المحادثات الأقدم من"],
        "settingsDeleteButton": ["en": "Delete", "ru": "Удалить", "es": "Eliminar", "fr": "Supprimer", "de": "Löschen", "zh": "删除", "ja": "削除", "ko": "삭제", "pt": "Excluir", "ar": "حذف"],
        "settingsDeleteAllArchivedChats": ["en": "Delete all archived chats", "ru": "Удалить все архивированные чаты", "es": "Eliminar todos los chats archivados", "fr": "Supprimer toutes les conversations archivées", "de": "Alle archivierten Chats löschen", "zh": "删除所有已归档聊天", "ja": "アーカイブ済みのチャットをすべて削除", "ko": "보관된 모든 채팅 삭제", "pt": "Excluir todas as conversas arquivadas", "ar": "حذف جميع المحادثات المؤرشفة"],
        "settingsCompressDatabase": ["en": "Compress database", "ru": "Сжать базу данных", "es": "Comprimir base de datos", "fr": "Compresser la base de données", "de": "Datenbank komprimieren", "zh": "压缩数据库", "ja": "データベースを圧縮", "ko": "데이터베이스 압축", "pt": "Comprimir base de dados", "ar": "ضغط قاعدة البيانات"],
        "settingsResetStorageTitle": ["en": "Reset storage", "ru": "Сброс хранилища", "es": "Restablecer almacenamiento", "fr": "Réinitialiser le stockage", "de": "Speicher zurücksetzen", "zh": "重置存储", "ja": "ストレージをリセット", "ko": "저장소 초기화", "pt": "Redefinir armazenamento", "ar": "إعادة تعيين التخزين"],
        "settingsResetAppCache": ["en": "Reset app cache", "ru": "Сбросить кэш приложения", "es": "Restablecer la caché de la aplicación", "fr": "Réinitialiser le cache de l'application", "de": "App-Cache zurücksetzen", "zh": "重置应用缓存", "ja": "アプリのキャッシュをリセット", "ko": "앱 캐시 초기화", "pt": "Redefinir o cache do aplicativo", "ar": "إعادة تعيين ذاكرة التخزين المؤقت للتطبيق"],
        "settingsClearAppCache": ["en": "Clear app cache", "ru": "Очистить кэш приложения", "es": "Borrar la caché de la aplicación", "fr": "Vider le cache de l'application", "de": "App-Cache leeren", "zh": "清除应用缓存", "ja": "アプリのキャッシュをクリア", "ko": "앱 캐시 지우기", "pt": "Limpar o cache do aplicativo", "ar": "مسح ذاكرة التخزين المؤقت للتطبيق"],
        "settingsArchiveInactive": ["en": "Archive inactive", "ru": "Архивировать неактивные", "es": "Archivar inactivos", "fr": "Archiver les inactifs", "de": "Inaktive archivieren", "zh": "归档非活动", "ja": "非アクティブをアーカイブ", "ko": "비활성 보관", "pt": "Arquivar inativos", "ar": "أرشفة غير النشطين"],
        "terminalTab": ["en": "Terminal", "ru": "Терминал", "es": "Terminal", "fr": "Terminal", "de": "Terminal", "zh": "终端", "ja": "ターミナル", "ko": "터미널", "pt": "Terminal", "ar": "الطرفية"],
        "gitTab": ["en": "Git", "ru": "Git", "es": "Git", "fr": "Git", "de": "Git", "zh": "Git", "ja": "Git", "ko": "Git", "pt": "Git", "ar": "Git"],
        "terminalWelcome": ["en": "Welcome to myCoder Terminal", "ru": "Добро пожаловать в терминал myCoder", "es": "Bienvenido al terminal de myCoder", "fr": "Bienvenue dans le terminal myCoder", "de": "Willkommen beim myCoder-Terminal", "zh": "欢迎使用 myCoder 终端", "ja": "myCoder ターミナルへようこそ", "ko": "myCoder 터미널에 오신 것을 환영합니다", "pt": "Bem-vindo ao myCoder Terminal", "ar": "مرحبًا بك في طرفية myCoder"],
        "terminalHelpOutput": ["en": "Available commands: clear, help, ls, pwd", "ru": "Доступные команды: clear, help, ls, pwd", "es": "Comandos disponibles: clear, help, ls, pwd", "fr": "Commandes disponibles : clear, help, ls, pwd", "de": "Verfügbare Befehle: clear, help, ls, pwd", "zh": "可用命令：clear、help、ls、pwd", "ja": "利用可能なコマンド: clear, help, ls, pwd", "ko": "사용 가능한 명령: clear, help, ls, pwd", "pt": "Comandos disponíveis: clear, help, ls, pwd", "ar": "الأوامر المتاحة: clear, help, ls, pwd"],
        "terminalHelpHint": ["en": "Type /help for a list of available commands", "ru": "Введите /help для списка доступных команд", "es": "Escriba /help para ver la lista de comandos disponibles", "fr": "Saisissez /help pour la liste des commandes disponibles", "de": "Geben Sie /help ein, um die verfügbaren Befehle anzuzeigen", "zh": "输入 /help 查看可用命令列表", "ja": "利用可能なコマンドの一覧を表示するには /help と入力してください", "ko": "사용 가능한 명령 목록을 보려면 /help를 입력하세요", "pt": "Digite /help para ver a lista de comandos disponíveis", "ar": "اكتب /help لعرض قائمة الأوامر المتاحة"],
        "terminalCommandNotFound": ["en": "Command not found: %@", "ru": "Команда не найдена: %@", "es": "Comando no encontrado: %@", "fr": "Commande introuvable : %@", "de": "Befehl nicht gefunden: %@", "zh": "找不到命令：%@", "ja": "コマンドが見つかりません: %@", "ko": "명령을 찾을 수 없습니다: %@", "pt": "Comando não encontrado: %@", "ar": "الأمر غير موجود: %@"],
        "gitToolsTitle": ["en": "Git tools", "ru": "Инструменты Git", "es": "Herramientas de Git", "fr": "Outils Git", "de": "Git-Werkzeuge", "zh": "Git 工具", "ja": "Git ツール", "ko": "Git 도구", "pt": "Ferramentas Git", "ar": "أدوات Git"],
        "subagentsTitle": ["en": "Subagents", "ru": "Субагенты", "es": "Subagentes", "fr": "Sous-agents", "de": "Subagenten", "zh": "子代理", "ja": "サブエージェント", "ko": "서브에이전트", "pt": "Subagentes", "ar": "الوكلاء الفرعيون"],
        "gitChanges": ["en": "Changes", "ru": "Изменения", "es": "Cambios", "fr": "Modifications", "de": "Änderungen", "zh": "更改", "ja": "変更", "ko": "변경 사항", "pt": "Alterações", "ar": "التغييرات"],
        "gitNoChanges": ["en": "No changes", "ru": "Нет изменений", "es": "Sin cambios", "fr": "Aucune modification", "de": "Keine Änderungen", "zh": "无更改", "ja": "変更なし", "ko": "변경 사항 없음", "pt": "Sem alterações", "ar": "لا توجد تغييرات"],
        "gitBranch": ["en": "Branch", "ru": "Ветка", "es": "Rama", "fr": "Branche", "de": "Zweig", "zh": "分支", "ja": "ブランチ", "ko": "브랜치", "pt": "Ramo", "ar": "الفرع"],
        "gitCommit": ["en": "Commit", "ru": "Коммит", "es": "Confirmación", "fr": "Valider", "de": "Commit", "zh": "提交", "ja": "コミット", "ko": "커밋", "pt": "Commit", "ar": "الالتزام"],
        "gitCommitAuto": ["en": "Auto-generate from changes", "ru": "Авто-создать из изменений", "es": "Generar automáticamente a partir de los cambios", "fr": "Générer automatiquement à partir des modifications", "de": "Automatisch aus Änderungen generieren", "zh": "从更改自动生成", "ja": "変更から自動生成", "ko": "변경 사항에서 자동 생성", "pt": "Gerar automaticamente a partir das alterações", "ar": "إنشاء تلقائي من التغييرات"],
        "gitCommitCustom": ["en": "Write custom message", "ru": "Написать своё сообщение", "es": "Escribir mensaje personalizado", "fr": "Écrire un message personnalisé", "de": "Benutzerdefinierte Nachricht schreiben", "zh": "编写自定义消息", "ja": "カスタムメッセージを書く", "ko": "사용자 정의 메시지 작성", "pt": "Escrever mensagem personalizada", "ar": "كتابة رسالة مخصصة"],
        "gitReviewPush": ["en": "Review & Push", "ru": "Обзор и пуш", "es": "Revisar y enviar", "fr": "Vérifier et pousser", "de": "Überprüfen & Pushen", "zh": "审查并推送", "ja": "レビューしてプッシュ", "ko": "검토 및 푸시", "pt": "Rever e Push", "ar": "مراجعة ودفع"],
        "gitPublish": ["en": "Publish", "ru": "Публикация", "es": "Publicar", "fr": "Publier", "de": "Veröffentlichen", "zh": "发布", "ja": "公開", "ko": "게시", "pt": "Publicar", "ar": "نشر"],
        "gitPublishTitle": ["en": "Publish to GitHub", "ru": "Опубликовать на GitHub", "es": "Publicar en GitHub", "fr": "Publier sur GitHub", "de": "Auf GitHub veröffentlichen", "zh": "发布到 GitHub", "ja": "GitHubに公開", "ko": "GitHub에 게시", "pt": "Publicar no GitHub", "ar": "النشر على GitHub"],
        "gitRepoName": ["en": "Repository name", "ru": "Имя репозитория", "es": "Nombre del repositorio", "fr": "Nom du dépôt", "de": "Repository-Name", "zh": "仓库名称", "ja": "リポジトリ名", "ko": "저장소 이름", "pt": "Nome do repositório", "ar": "اسم المستودع"],
        "gitInitTitle": ["en": "Initialize Git Repository", "ru": "Инициализировать Git репозиторий", "es": "Inicializar repositorio Git", "fr": "Initialiser le dépôt Git", "de": "Git-Repository initialisieren", "zh": "初始化 Git 仓库", "ja": "Git リポジトリを初期化", "ko": "Git 저장소 초기화", "pt": "Inicializar repositório Git", "ar": "تهيئة مستودع Git"],
        "gitVisibility": ["en": "Visibility", "ru": "Видимость", "es": "Visibilidad", "fr": "Visibilité", "de": "Sichtbarkeit", "zh": "可见性", "ja": "公開範囲", "ko": "공개 범위", "pt": "Visibilidade", "ar": "الظهور"],
        "gitPublic": ["en": "Public", "ru": "Публичный", "es": "Público", "fr": "Public", "de": "Öffentlich", "zh": "公开", "ja": "公開", "ko": "공개", "pt": "Público", "ar": "عام"],
        "gitPrivate": ["en": "Private", "ru": "Приватный", "es": "Privado", "fr": "Privé", "de": "Privat", "zh": "私有", "ja": "非公開", "ko": "비공개", "pt": "Privado", "ar": "خاص"],
        "gitInitialize": ["en": "Initialize", "ru": "Инициализировать", "es": "Inicializar", "fr": "Initialiser", "de": "Initialisieren", "zh": "初始化", "ja": "初期化", "ko": "초기화", "pt": "Inicializar", "ar": "تهيئة"],
        "gitPublishToGithub": ["en": "Publish to GitHub", "ru": "Опубликовать на GitHub", "es": "Publicar en GitHub", "fr": "Publier sur GitHub", "de": "Auf GitHub veröffentlichen", "zh": "发布到 GitHub", "ja": "GitHubに公開", "ko": "GitHub에 게시", "pt": "Publicar no GitHub", "ar": "النشر على GitHub"],
        "gitBusyRetrying": ["en": "Session busy, aborting and retrying...", "ru": "Сессия занята, отмена и повтор...", "es": "Sesión ocupada, cancelando y reintentando...", "fr": "Session occupée, abandon et nouvelle tentative...", "de": "Sitzung belegt, Abbruch und Wiederholung...", "zh": "会话繁忙，正在中止并重试...", "ja": "セッションがビジーです。中止して再試行しています...", "ko": "세션이 사용 중입니다. 중단 후 재시도하는 중...", "pt": "Sessão ocupada, a abortar e a tentar novamente...", "ar": "الجلسة مشغولة، يتم الإلغاء وإعادة المحاولة..."],
        "gitInstallGHTitle": ["en": "Install GitHub CLI", "ru": "Установить GitHub CLI", "es": "Instalar GitHub CLI", "fr": "Installer GitHub CLI", "de": "GitHub CLI installieren", "zh": "安装 GitHub CLI", "ja": "GitHub CLIをインストール", "ko": "GitHub CLI 설치", "pt": "Instalar GitHub CLI", "ar": "تثبيت GitHub CLI"],
        "gitInstallGHSubtitle": ["en": "GitHub CLI (gh) is required to create repositories from MiMo. Install it with Homebrew, or open the docs to install manually.", "ru": "Для создания репозиториев из MiMo нужен GitHub CLI (gh). Установите его через Homebrew или откройте документацию для ручной установки.", "es": "Se requiere GitHub CLI (gh) para crear repositorios desde MiMo. Instálelo con Homebrew o abra la documentación para instalarlo manualmente.", "fr": "GitHub CLI (gh) est requis pour créer des dépôts depuis MiMo. Installez-le avec Homebrew ou ouvrez la documentation pour l'installer manuellement.", "de": "GitHub CLI (gh) ist erforderlich, um Repositorys aus MiMo zu erstellen. Installieren Sie es mit Homebrew oder öffnen Sie die Doku für die manuelle Installation.", "zh": "需要 GitHub CLI (gh) 才能从 MiMo 创建仓库。请用 Homebrew 安装，或打开文档手动安装。", "ja": "MiMo からリポジトリを作成するには GitHub CLI（gh）が必要です。Homebrew でインストールするか、手動でインストールするためのドキュメントを開いてください。", "ko": "MiMo에서 저장소를 만들려면 GitHub CLI(gh)가 필요합니다. Homebrew로 설치하거나 수동 설치 문서를 여세요.", "pt": "O GitHub CLI (gh) é necessário para criar repositórios a partir do MiMo. Instale-o com o Homebrew ou abra a documentação para instalar manualmente.", "ar": "يلزم GitHub CLI (gh) لإنشاء المستودعات من MiMo. ثبّته باستخدام Homebrew، أو افتح الوثائق للتثبيت اليدوي."],
        "gitInstallGHButton": ["en": "Install with Homebrew", "ru": "Установить через Homebrew", "es": "Instalar con Homebrew", "fr": "Installer avec Homebrew", "de": "Mit Homebrew installieren", "zh": "使用 Homebrew 安装", "ja": "Homebrewでインストール", "ko": "Homebrew로 설치", "pt": "Instalar com Homebrew", "ar": "التثبيت عبر Homebrew"],
        "gitSignInTitle": ["en": "Sign in to GitHub", "ru": "Войти в GitHub", "es": "Iniciar sesión en GitHub", "fr": "Se connecter à GitHub", "de": "Bei GitHub anmelden", "zh": "登录 GitHub", "ja": "GitHubにサインイン", "ko": "GitHub에 로그인", "pt": "Iniciar sessão no GitHub", "ar": "تسجيل الدخول إلى GitHub"],
        "gitSignInSubtitle": ["en": "Authorize GitHub CLI in your browser. A one-time code flow will open on github.com.", "ru": "Авторизуйте GitHub CLI в браузере. Откроется страница github.com с одноразовым кодом.", "es": "Autorice GitHub CLI en su navegador. Se abrirá un flujo de código único en github.com.", "fr": "Autorisez GitHub CLI dans votre navigateur. Un flux de code à usage unique s'ouvrira sur github.com.", "de": "Autorisieren Sie GitHub CLI in Ihrem Browser. Auf github.com wird ein Einmalcode-Flow geöffnet.", "zh": "在浏览器中授权 GitHub CLI。github.com 上将打开一次性代码流程。", "ja": "ブラウザで GitHub CLI を認証してください。github.com でワンタイムコードフローが開きます。", "ko": "브라우저에서 GitHub CLI를 승인하세요. github.com에서 일회용 코드 흐름이 열립니다.", "pt": "Autorize o GitHub CLI no seu navegador. Um fluxo de código único será aberto em github.com.", "ar": "أذن لـ GitHub CLI في متصفحك. سيتم فتح تدفق رمز لمرة واحدة على github.com."],
        "gitSignInButton": ["en": "Sign in with browser", "ru": "Войти через браузер", "es": "Iniciar sesión con el navegador", "fr": "Se connecter via le navigateur", "de": "Mit Browser anmelden", "zh": "使用浏览器登录", "ja": "ブラウザでサインイン", "ko": "브라우저로 로그인", "pt": "Iniciar sessão com o navegador", "ar": "تسجيل الدخول عبر المتصفح"],
        "gitCreateAndPush": ["en": "Create & Push", "ru": "Создать и запушить", "es": "Crear y enviar", "fr": "Créer et pousser", "de": "Erstellen & Pushen", "zh": "创建并推送", "ja": "作成してプッシュ", "ko": "생성 및 푸시", "pt": "Criar e Push", "ar": "إنشاء ودفع"],
        "gitCancel": ["en": "Cancel", "ru": "Отмена", "es": "Cancelar", "fr": "Annuler", "de": "Abbrechen", "zh": "取消", "ja": "キャンセル", "ko": "취소", "pt": "Cancelar", "ar": "إلغاء"],
        "gitInitSubtitle": ["en": "Create a local Git repository for this workspace. You can publish it to GitHub afterwards.", "ru": "Создать локальный Git-репозиторий для этого workspace. После этого его можно опубликовать на GitHub.", "es": "Cree un repositorio Git local para esta área de trabajo. Puede publicarlo en GitHub después.", "fr": "Créez un dépôt Git local pour cet espace de travail. Vous pourrez le publier sur GitHub par la suite.", "de": "Erstellen Sie ein lokales Git-Repository für diesen Arbeitsbereich. Sie können es anschließend auf GitHub veröffentlichen.", "zh": "为此工作区创建一个本地 Git 仓库。之后您可以将其发布到 GitHub。", "ja": "このワークスペース用のローカル Git リポジトリを作成します。後でGitHubに公開できます。", "ko": "이 작업 공간에 로컬 Git 저장소를 만듭니다. 나중에 GitHub에 게시할 수 있습니다.", "pt": "Crie um repositório Git local para esta área de trabalho. Pode publicá-lo no GitHub posteriormente.", "ar": "أنشئ مستودع Git محلي لمساحة العمل هذه. يمكنك نشره على GitHub لاحقًا."],
        "gitReviewComment": ["en": "Your comment", "ru": "Ваш комментарий", "es": "Su comentario", "fr": "Votre commentaire", "de": "Ihr Kommentar", "zh": "您的评论", "ja": "コメント", "ko": "내 댓글", "pt": "O seu comentário", "ar": "تعليقك"],
        "gitReviewCommentPlaceholder": ["en": "What did you change? (optional)", "ru": "Что вы изменили? (необязательно)", "es": "¿Qué cambió? (opcional)", "fr": "Qu'avez-vous modifié ? (facultatif)", "de": "Was haben Sie geändert? (optional)", "zh": "您更改了什么？（可选）", "ja": "何を変更しましたか？（任意）", "ko": "무엇을 변경했나요? (선택 사항)", "pt": "O que alterou? (opcional)", "ar": "ما الذي غيّرته؟ (اختياري)"],
        "gitReviewSummary": ["en": "Auto summary of changes", "ru": "Автосводка изменений", "es": "Resumen automático de cambios", "fr": "Résumé automatique des modifications", "de": "Automatische Zusammenfassung der Änderungen", "zh": "更改的自动摘要", "ja": "変更の自動要約", "ko": "변경 사항 자동 요약", "pt": "Resumo automático das alterações", "ar": "ملخص تلقائي للتغييرات"],
        "gitCommitAndPush": ["en": "Commit & Push", "ru": "Коммит и пуш", "es": "Confirmar y enviar", "fr": "Valider et pousser", "de": "Commit & Pushen", "zh": "提交并推送", "ja": "コミットしてプッシュ", "ko": "커밋 및 푸시", "pt": "Commit e Push", "ar": "التزام ودفع"],
        "gitOpenGitHubDocs": ["en": "Open install docs", "ru": "Открыть документацию", "es": "Abrir documentación de instalación", "fr": "Ouvrir la documentation d'installation", "de": "Installationsdokumentation öffnen", "zh": "打开安装文档", "ja": "インストールドキュメントを開く", "ko": "설치 문서 열기", "pt": "Abrir documentação de instalação", "ar": "فتح وثائق التثبيت"],
        "planTitle": ["en": "Plan", "ru": "План", "es": "Plan", "fr": "Plan", "de": "Plan", "zh": "计划", "ja": "プラン", "ko": "계획", "pt": "Plano", "ar": "الخطة"],
        "noStepsYet": ["en": "No steps yet", "ru": "Нет шагов", "es": "Sin pasos aún", "fr": "Aucune étape pour le moment", "de": "Noch keine Schritte", "zh": "暂无步骤", "ja": "まだステップがありません", "ko": "아직 단계가 없습니다", "pt": "Ainda sem passos", "ar": "لا توجد خطوات بعد"],
        "completedSteps": ["en": "%d completed", "ru": "%d завершено", "es": "%d completados", "fr": "%d terminés", "de": "%d abgeschlossen", "zh": "%d 已完成", "ja": "%d 完了", "ko": "%d 완료", "pt": "%d concluídos", "ar": "%d مكتملة"],
        "waitingSteps": ["en": "%d waiting", "ru": "%d ожидает", "es": "%d en espera", "fr": "%d en attente", "de": "%d warten", "zh": "%d 等待中", "ja": "%d 待機中", "ko": "%d 대기 중", "pt": "%d aguardando", "ar": "%d في الانتظار"],
        "appDisplayName": ["en": "myCoder", "ru": "myCoder", "es": "myCoder", "fr": "myCoder", "de": "myCoder", "zh": "myCoder", "ja": "myCoder", "ko": "myCoder", "pt": "myCoder", "ar": "myCoder"],
        "statusBarIdle": ["en": "Idle", "ru": "Ожидание", "es": "Inactivo", "fr": "Inactif", "de": "Leerlauf", "zh": "空闲", "ja": "アイドル", "ko": "대기 중", "pt": "Inativo", "ar": "خامل"],
        "statusBarGenerating": ["en": "Generating...", "ru": "Генерация...", "es": "Generando...", "fr": "Génération...", "de": "Wird generiert...", "zh": "正在生成...", "ja": "生成中...", "ko": "생성 중...", "pt": "A gerar...", "ar": "جارٍ الإنشاء..."],
        "statusBarProcessing": ["en": "Processing...", "ru": "Обработка...", "es": "Procesando...", "fr": "Traitement...", "de": "Wird verarbeitet...", "zh": "正在处理...", "ja": "処理中...", "ko": "처리 중...", "pt": "A processar...", "ar": "جارٍ المعالجة..."],
        "newProjectTitle": ["en": "New Project", "ru": "Новый проект", "es": "Nuevo proyecto", "fr": "Nouveau projet", "de": "Neues Projekt", "zh": "新建项目", "ja": "新規プロジェクト", "ko": "새 프로젝트", "pt": "Novo Projeto", "ar": "مشروع جديد"],
        "newProjectName": ["en": "Project Name", "ru": "Имя проекта", "es": "Nombre del proyecto", "fr": "Nom du projet", "de": "Projektname", "zh": "项目名称", "ja": "プロジェクト名", "ko": "프로젝트 이름", "pt": "Nome do Projeto", "ar": "اسم المشروع"],
        "newProjectFolder": ["en": "Folder", "ru": "Папка", "es": "Carpeta", "fr": "Dossier", "de": "Ordner", "zh": "文件夹", "ja": "フォルダー", "ko": "폴더", "pt": "Pasta", "ar": "المجلد"],
        "newProjectChooseFolder": ["en": "Choose Folder", "ru": "Выбрать папку", "es": "Elegir carpeta", "fr": "Choisir un dossier", "de": "Ordner wählen", "zh": "选择文件夹", "ja": "フォルダーを選択", "ko": "폴더 선택", "pt": "Escolher pasta", "ar": "اختر مجلدًا"],
        "newProjectCreate": ["en": "Create Project", "ru": "Создать проект", "es": "Crear proyecto", "fr": "Créer le projet", "de": "Projekt erstellen", "zh": "创建项目", "ja": "プロジェクトを作成", "ko": "프로젝트 생성", "pt": "Criar projeto", "ar": "إنشاء مشروع"],
        "newProjectCancel": ["en": "Cancel", "ru": "Отмена", "es": "Cancelar", "fr": "Annuler", "de": "Abbrechen", "zh": "取消", "ja": "キャンセル", "ko": "취소", "pt": "Cancelar", "ar": "إلغاء"],
        "notificationsTitle": ["en": "Notifications", "ru": "Уведомления", "es": "Notificaciones", "fr": "Notifications", "de": "Benachrichtigungen", "zh": "通知", "ja": "通知", "ko": "알림", "pt": "Notificações", "ar": "الإشعارات"],
        "notificationsEmpty": ["en": "No notifications", "ru": "Нет уведомлений", "es": "Sin notificaciones", "fr": "Aucune notification", "de": "Keine Benachrichtigungen", "zh": "暂无通知", "ja": "通知はありません", "ko": "알림 없음", "pt": "Sem notificações", "ar": "لا توجد إشعارات"],
        "notificationsEmptySubtitle": ["en": "Task completions and system alerts will appear here.", "ru": "Здесь будет история уведомлений и системных событий.", "es": "Las finalizaciones de tareas y alertas del sistema aparecerán aquí.", "fr": "Les fins de tâches et alertes système apparaîtront ici.", "de": "Aufgabenerledigungen und Systemwarnungen werden hier angezeigt.", "zh": "任务完成和系统提醒将显示在此处。", "ja": "タスク完了とシステムアラートがここに表示されます。", "ko": "작업 완료 및 시스템 알림이 여기에 표시됩니다.", "pt": "As conclusões de tarefas e os alertas do sistema aparecerão aqui.", "ar": "ستظهر هنا إكمالات المهام وتنبيهات النظام."],
        "workspacesTitle": ["en": "Workspaces", "ru": "Проекты", "es": "Áreas de trabajo", "fr": "Espaces de travail", "de": "Arbeitsbereiche", "zh": "工作区", "ja": "ワークスペース", "ko": "작업 공간", "pt": "Áreas de trabalho", "ar": "مساحات العمل"],
        "noTasksYet": ["en": "No tasks yet", "ru": "Пока нет задач", "es": "Sin tareas aún", "fr": "Aucune tâche pour le moment", "de": "Noch keine Aufgaben", "zh": "暂无任务", "ja": "まだタスクがありません", "ko": "아직 작업이 없습니다", "pt": "Ainda sem tarefas", "ar": "لا توجد مهام بعد"],
        "justNow": ["en": "now", "ru": "только что", "es": "ahora", "fr": "maintenant", "de": "jetzt", "zh": "刚刚", "ja": "たった今", "ko": "지금", "pt": "agora", "ar": "الآن"],
        "storageTabTitle": ["en": "Storage", "ru": "Хранилище", "es": "Almacenamiento", "fr": "Stockage", "de": "Speicher", "zh": "存储", "ja": "ストレージ", "ko": "저장소", "pt": "Armazenamento", "ar": "التخزين"],
        "storageStatsTitle": ["en": "Storage", "ru": "Хранилище", "es": "Almacenamiento", "fr": "Stockage", "de": "Speicher", "zh": "存储", "ja": "ストレージ", "ko": "저장소", "pt": "Armazenamento", "ar": "التخزين"],
        "storageDatabaseSize": ["en": "Database", "ru": "База данных", "es": "Base de datos", "fr": "Base de données", "de": "Datenbank", "zh": "数据库", "ja": "データベース", "ko": "데이터베이스", "pt": "Base de dados", "ar": "قاعدة البيانات"],
        "storageSnapshotSize": ["en": "Snapshots", "ru": "Снимки", "es": "Instantáneas", "fr": "Instantanés", "de": "Schnappschüsse", "zh": "快照", "ja": "スナップショット", "ko": "스냅샷", "pt": "Instantâneos", "ar": "اللقطات"],
        "storageMessageCount": ["en": "Messages", "ru": "Сообщений", "es": "Mensajes", "fr": "Messages", "de": "Nachrichten", "zh": "消息", "ja": "メッセージ", "ko": "메시지", "pt": "Mensagens", "ar": "الرسائل"],
        "storageActiveSessions": ["en": "Active sessions", "ru": "Активные сессии", "es": "Sesiones activas", "fr": "Sessions actives", "de": "Aktive Sitzungen", "zh": "活跃会话", "ja": "アクティブセッション", "ko": "활성 세션", "pt": "Sessões ativas", "ar": "الجلسات النشطة"],
        "storageArchivedSessions": ["en": "Archived sessions", "ru": "Архивные сессии", "es": "Sesiones archivadas", "fr": "Sessions archivées", "de": "Archivierte Sitzungen", "zh": "已归档会话", "ja": "アーカイブ済みセッション", "ko": "보관된 세션", "pt": "Sessões arquivadas", "ar": "الجلسات المؤرشفة"],
        "cleanupTitle": ["en": "Cleanup", "ru": "Очистка", "es": "Limpieza", "fr": "Nettoyage", "de": "Bereinigung", "zh": "清理", "ja": "クリーンアップ", "ko": "정리", "pt": "Limpeza", "ar": "التنظيف"],
        "deleteChatsOlderThan": ["en": "Delete chats older than:", "ru": "Удалить чаты старше:", "es": "Eliminar chats anteriores a:", "fr": "Supprimer les conversations de plus de :", "de": "Chats löschen, die älter sind als:", "zh": "删除早于以下时间的聊天：", "ja": "次の日数より古いチャットを削除:", "ko": "다음보다 오래된 채팅 삭제:", "pt": "Eliminar conversas com mais de:", "ar": "حذف المحادثات الأقدم من:"],
        "deleteChats7Days": ["en": "7 days", "ru": "7 дней", "es": "7 días", "fr": "7 jours", "de": "7 Tage", "zh": "7 天", "ja": "7日", "ko": "7일", "pt": "7 dias", "ar": "7 أيام"],
        "deleteChats30Days": ["en": "30 days", "ru": "30 дней", "es": "30 días", "fr": "30 jours", "de": "30 Tage", "zh": "30 天", "ja": "30日", "ko": "30일", "pt": "30 dias", "ar": "30 يومًا"],
        "deleteChats90Days": ["en": "90 days", "ru": "90 дней", "es": "90 días", "fr": "90 jours", "de": "90 Tage", "zh": "90 天", "ja": "90日", "ko": "90일", "pt": "90 dias", "ar": "90 يومًا"],
        "deleteChats180Days": ["en": "180 days", "ru": "180 дней", "es": "180 días", "fr": "180 jours", "de": "180 Tage", "zh": "180 天", "ja": "180日", "ko": "180일", "pt": "180 dias", "ar": "180 يومًا"],
        "deleteChats1Year": ["en": "1 year", "ru": "1 год", "es": "1 año", "fr": "1 an", "de": "1 Jahr", "zh": "1 年", "ja": "1年", "ko": "1년", "pt": "1 ano", "ar": "سنة واحدة"],
        "deleteChatsConfirmTitle": ["en": "Delete old chats?", "ru": "Удалить старые чаты?", "es": "¿Eliminar chats antiguos?", "fr": "Supprimer les anciennes conversations ?", "de": "Alte Chats löschen?", "zh": "删除旧聊天？", "ja": "古いチャットを削除しますか？", "ko": "오래된 채팅을 삭제하시겠습니까?", "pt": "Eliminar conversas antigas?", "ar": "هل تريد حذف المحادثات القديمة؟"],
        "deleteChatsConfirmMessage": ["en": "This will permanently delete all chats older than %d days, including their messages. This action cannot be undone.", "ru": "Это навсегда удалит все чаты старше %d дней со всеми сообщениями. Действие нельзя отменить.", "es": "Esto eliminará permanentemente todos los chats anteriores a %d días, incluidos sus mensajes. Esta acción no se puede deshacer.", "fr": "Cela supprimera définitivement toutes les conversations de plus de %d jours, y compris leurs messages. Cette action est irréversible.", "de": "Dies löscht dauerhaft alle Chats, die älter als %d Tage sind, einschließlich ihrer Nachrichten. Diese Aktion kann nicht rückgängig gemacht werden.", "zh": "这将永久删除所有早于 %d 天的聊天及其消息。此操作无法撤销。", "ja": "%d日より古いすべてのチャット（メッセージ含む）が完全に削除されます。この操作は元に戻せません。", "ko": "%d일보다 오래된 모든 채팅(메시지 포함)이 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.", "pt": "Isto eliminará permanentemente todas as conversas com mais de %d dias, incluindo as suas mensagens. Esta ação não pode ser anulada.", "ar": "سيؤدي هذا إلى حذف جميع المحادثات الأقدم من %d يومًا بشكل دائم، بما في ذلك رسائلها. لا يمكن التراجع عن هذا الإجراء."],
        "deleteButton": ["en": "Delete", "ru": "Удалить", "es": "Eliminar", "fr": "Supprimer", "de": "Löschen", "zh": "删除", "ja": "削除", "ko": "삭제", "pt": "Eliminar", "ar": "حذف"],
        "cancelButton": ["en": "Cancel", "ru": "Отмена", "es": "Cancelar", "fr": "Annuler", "de": "Abbrechen", "zh": "取消", "ja": "キャンセル", "ko": "취소", "pt": "Cancelar", "ar": "إلغاء"],
        "deleteAllArchivedChats": ["en": "Delete all archived chats", "ru": "Удалить все архивные чаты", "es": "Eliminar todos los chats archivados", "fr": "Supprimer toutes les conversations archivées", "de": "Alle archivierten Chats löschen", "zh": "删除所有已归档的聊天", "ja": "すべてのアーカイブ済みチャットを削除", "ko": "보관된 모든 채팅 삭제", "pt": "Eliminar todas as conversas arquivadas", "ar": "حذف جميع المحادثات المؤرشفة"],
        "compressDatabase": ["en": "Compress database (VACUUM)", "ru": "Сжать базу (VACUUM)", "es": "Comprimir base de datos (VACUUM)", "fr": "Compresser la base de données (VACUUM)", "de": "Datenbank komprimieren (VACUUM)", "zh": "压缩数据库 (VACUUM)", "ja": "データベースを圧縮 (VACUUM)", "ko": "데이터베이스 압축(VACUUM)", "pt": "Comprimir base de dados (VACUUM)", "ar": "ضغط قاعدة البيانات (VACUUM)"],
        "resetStorageTitle": ["en": "Reset storage", "ru": "Сброс хранилища", "es": "Restablecer almacenamiento", "fr": "Réinitialiser le stockage", "de": "Speicher zurücksetzen", "zh": "重置存储", "ja": "ストレージをリセット", "ko": "저장소 재설정", "pt": "Repor armazenamento", "ar": "إعادة تعيين التخزين"],
        "resetAppCache": ["en": "Clear app cache", "ru": "Очистить кеш приложения", "es": "Borrar caché de la aplicación", "fr": "Vider le cache de l'application", "de": "App-Cache leeren", "zh": "清除应用缓存", "ja": "アプリキャッシュをクリア", "ko": "앱 캐시 지우기", "pt": "Limpar cache da aplicação", "ar": "مسح ذاكرة التخزين المؤقت للتطبيق"],
        "resetAppCacheConfirmTitle": ["en": "Clear app cache?", "ru": "Очистить кеш приложения?", "es": "¿Borrar caché de la aplicación?", "fr": "Vider le cache de l'application ?", "de": "App-Cache leeren?", "zh": "清除应用缓存？", "ja": "アプリキャッシュをクリアしますか？", "ko": "앱 캐시를 지우시겠습니까?", "pt": "Limpar cache da aplicação?", "ar": "هل تريد مسح ذاكرة التخزين المؤقت للتطبيق؟"],
        "resetButton": ["en": "Reset", "ru": "Сбросить", "es": "Restablecer", "fr": "Réinitialiser", "de": "Zurücksetzen", "zh": "重置", "ja": "リセット", "ko": "재설정", "pt": "Repor", "ar": "إعادة تعيين"],
        "resetFullDatabase": ["en": "Wipe database completely", "ru": "Обнулить базу полностью", "es": "Borrar la base de datos por completo", "fr": "Effacer complètement la base de données", "de": "Datenbank vollständig löschen", "zh": "完全清空数据库", "ja": "データベースを完全に消去", "ko": "데이터베이스 완전 초기화", "pt": "Apagar a base de dados por completo", "ar": "محو قاعدة البيانات بالكامل"],
        "resetFullDatabaseConfirmTitle": ["en": "Wipe the entire database?", "ru": "Полностью обнулить базу?", "es": "¿Borrar toda la base de datos?", "fr": "Effacer toute la base de données ?", "de": "Gesamte Datenbank löschen?", "zh": "清空整个数据库？", "ja": "データベース全体を消去しますか？", "ko": "전체 데이터베이스를 초기화하시겠습니까?", "pt": "Apagar toda a base de dados?", "ar": "هل تريد محو قاعدة البيانات بالكامل؟"],
        "resetAppCacheWarning": ["en": "The app database with all chats and messages will be permanently deleted. This action cannot be undone.", "ru": "База приложения со всеми чатами и сообщениями будет удалена навсегда. Это действие необратимо.", "es": "La base de datos de la aplicación con todos los chats y mensajes se eliminará permanentemente. Esta acción no se puede deshacer.", "fr": "La base de données de l’application, avec toutes les conversations et messages, sera définitivement supprimée. Cette action est irréversible.", "de": "Die App-Datenbank mit allen Chats und Nachrichten wird dauerhaft gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.", "zh": "应用数据库及所有聊天和消息将被永久删除。此操作无法撤销。", "ja": "アプリのデータベースとすべてのチャット・メッセージが完全に削除されます。この操作は取り消せません。", "ko": "앱 데이터베이스와 모든 채팅 및 메시지가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.", "pt": "A base de dados da aplicação com todas as conversas e mensagens será eliminada permanentemente. Esta ação não pode ser anulada.", "ar": "سيتم حذف قاعدة بيانات التطبيق وجميع المحادثات والرسائل نهائيًا. لا يمكن التراجع عن هذا الإجراء."],
        "resetFullDatabaseWarning": ["en": "All chats, messages, projects and per-project databases will be permanently deleted. This action cannot be undone.", "ru": "Все чаты, сообщения, проекты и базы проектов будут удалены навсегда. Это действие необратимо.", "es": "Todos los chats, mensajes, proyectos y bases de datos de proyectos se eliminarán permanentemente. Esta acción no se puede deshacer.", "fr": "Toutes les conversations, messages, projets et bases de données de projets seront définitivement supprimés. Cette action est irréversible.", "de": "Alle Chats, Nachrichten, Projekte und Projekt-Datenbanken werden dauerhaft gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.", "zh": "所有聊天、消息、项目及项目数据库将被永久删除。此操作无法撤销。", "ja": "すべてのチャット、メッセージ、プロジェクト、プロジェクトデータベースが完全に削除されます。この操作は取り消せません。", "ko": "모든 채팅, 메시지, 프로젝트 및 프로젝트 데이터베이스가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.", "pt": "Todas as conversas, mensagens, projetos e bases de dados de projetos serão eliminados permanentemente. Esta ação não pode ser anulada.", "ar": "سيتم حذف جميع المحادثات والرسائل والمشاريع وقواعد بيانات المشاريع نهائيًا. لا يمكن التراجع عن هذا الإجراء."],
        "resetPlanPathsTitle": ["en": "Files to delete:", "ru": "Будут удалены:", "es": "Archivos que se eliminarán:", "fr": "Fichiers à supprimer :", "de": "Zu löschende Dateien:", "zh": "将删除的文件：", "ja": "削除されるファイル:", "ko": "삭제할 파일:", "pt": "Ficheiros a eliminar:", "ar": "الملفات التي ستُحذف:"],
        "archiveNow": ["en": "Archive now", "ru": "Архивировать сейчас", "es": "Archivar ahora", "fr": "Archiver maintenant", "de": "Jetzt archivieren", "zh": "立即归档", "ja": "今すぐアーカイブ", "ko": "지금 보관", "pt": "Arquivar agora", "ar": "أرشفة الآن"],
        "locSearchCommands": ["en": "Search commands...", "ru": "Поиск команд...", "es": "Buscar comandos...", "fr": "Rechercher des commandes...", "de": "Befehle suchen...", "zh": "搜索命令...", "ja": "コマンドを検索...", "ko": "명령 검색...", "pt": "Pesquisar comandos...", "ar": "البحث عن الأوامر..."],
        "locSearchPlugins": ["en": "Search plugins...", "ru": "Поиск плагинов...", "es": "Buscar plugins...", "fr": "Rechercher des plugins...", "de": "Plugins suchen...", "zh": "搜索插件...", "ja": "プラグインを検索...", "ko": "플러그인 검색...", "pt": "Pesquisar plugins...", "ar": "البحث عن الإضافات..."],
        "locSearchSkills": ["en": "Search skills...", "ru": "Поиск навыков...", "es": "Buscar habilidades...", "fr": "Rechercher des compétences...", "de": "Skills suchen...", "zh": "搜索技能...", "ja": "スキルを検索...", "ko": "스킬 검색...", "pt": "Pesquisar habilidades...", "ar": "البحث عن المهارات..."],
        "locSearchMCPServers": ["en": "Search MCP servers...", "ru": "Поиск MCP-серверов...", "es": "Buscar servidores MCP...", "fr": "Rechercher des serveurs MCP...", "de": "MCP-Server suchen...", "zh": "搜索 MCP 服务器...", "ja": "MCPサーバーを検索...", "ko": "MCP 서버 검색...", "pt": "Pesquisar servidores MCP...", "ar": "البحث عن خوادم MCP..."],
        "locSearchProviders": ["en": "Search providers...", "ru": "Поиск провайдеров...", "es": "Buscar proveedores...", "fr": "Rechercher des fournisseurs...", "de": "Anbieter suchen...", "zh": "搜索提供商...", "ja": "プロバイダーを検索...", "ko": "공급자 검색...", "pt": "Pesquisar provedores...", "ar": "البحث عن الموفرين..."],
        "locEnable": ["en": "Enable", "ru": "Включить", "es": "Habilitar", "fr": "Activer", "de": "Aktivieren", "zh": "启用", "ja": "有効化", "ko": "활성화", "pt": "Ativar", "ar": "تفعيل"],
        "locDisable": ["en": "Disable", "ru": "Отключить", "es": "Deshabilitar", "fr": "Désactiver", "de": "Deaktivieren", "zh": "禁用", "ja": "無効化", "ko": "비활성화", "pt": "Desativar", "ar": "تعطيل"],
        "locEnabled": ["en": "Enabled", "ru": "Включено", "es": "Habilitado", "fr": "Activé", "de": "Aktiviert", "zh": "已启用", "ja": "有効", "ko": "활성화됨", "pt": "Ativo", "ar": "مُفعّل"],
        "locDisabled": ["en": "Disabled", "ru": "Отключено", "es": "Deshabilitado", "fr": "Désactivé", "de": "Deaktiviert", "zh": "已禁用", "ja": "無効", "ko": "비활성화됨", "pt": "Desativado", "ar": "مُعطّل"],
        "locAdded": ["en": "Added", "ru": "Добавлено", "es": "Añadido", "fr": "Ajouté", "de": "Hinzugefügt", "zh": "已添加", "ja": "追加済み", "ko": "추가됨", "pt": "Adicionado", "ar": "مُضاف"],
        "locSaveConfiguration": ["en": "Save configuration", "ru": "Сохранить конфигурацию", "es": "Guardar configuración", "fr": "Enregistrer la configuration", "de": "Konfiguration speichern", "zh": "保存配置", "ja": "設定を保存", "ko": "구성 저장", "pt": "Guardar configuração", "ar": "حفظ الإعدادات"],
        "locRefreshModels": ["en": "Refresh models", "ru": "Обновить модели", "es": "Actualizar modelos", "fr": "Actualiser les modèles", "de": "Modelle aktualisieren", "zh": "刷新模型", "ja": "モデルを更新", "ko": "모델 새로고침", "pt": "Atualizar modelos", "ar": "تحديث النماذج"],
        "locRefreshWebModels": ["en": "Refresh web models", "ru": "Обновить веб-модели", "es": "Actualizar modelos web", "fr": "Actualiser les modèles web", "de": "Web-Modelle aktualisieren", "zh": "刷新网络模型", "ja": "ウェブモデルを更新", "ko": "웹 모델 새로고침", "pt": "Atualizar modelos web", "ar": "تحديث نماذج الويب"],
        "locWebSession": ["en": "Web session", "ru": "Веб-сессия", "es": "Sesión web", "fr": "Session web", "de": "Web-Sitzung", "zh": "网络会话", "ja": "ウェブセッション", "ko": "웹 세션", "pt": "Sessão web", "ar": "جلسة ويب"],
        "locCustomProvider": ["en": "Custom provider", "ru": "Пользовательский провайдер", "es": "Proveedor personalizado", "fr": "Fournisseur personnalisé", "de": "Benutzerdefinierter Anbieter", "zh": "自定义提供商", "ja": "カスタムプロバイダー", "ko": "사용자 정의 공급자", "pt": "Provedor personalizado", "ar": "مزود مخصص"],
        "locLocalAgent": ["en": "Local Agent", "ru": "Локальный агент", "es": "Agente local", "fr": "Agent local", "de": "Lokaler Agent", "zh": "本地代理", "ja": "ローカルエージェント", "ko": "로컬 에이전트", "pt": "Agente local", "ar": "الوكيل المحلي"],
        "locConfigure": ["en": "Configure", "ru": "Настроить", "es": "Configurar", "fr": "Configurer", "de": "Konfigurieren", "zh": "配置", "ja": "設定", "ko": "구성", "pt": "Configurar", "ar": "إعداد"],
        "locConnect": ["en": "Connect", "ru": "Подключить", "es": "Conectar", "fr": "Connecter", "de": "Verbinden", "zh": "连接", "ja": "接続", "ko": "연결", "pt": "Ligar", "ar": "اتصال"],
        "locDisconnect": ["en": "Disconnect", "ru": "Отключить", "es": "Desconectar", "fr": "Déconnecter", "de": "Trennen", "zh": "断开", "ja": "切断", "ko": "연결 해제", "pt": "Desligar", "ar": "قطع الاتصال"],
        "locAutoDetect": ["en": "Auto-detect", "ru": "Автоопределение", "es": "Auto-detectar", "fr": "Auto-détection", "de": "Automatische Erkennung", "zh": "自动检测", "ja": "自動検出", "ko": "자동 감지", "pt": "Detecção automática", "ar": "اكتشاف تلقائي"],
        "locDetecting": ["en": "Detecting…", "ru": "Определение…", "es": "Detectando…", "fr": "Détection…", "de": "Erkennung…", "zh": "检测中…", "ja": "検出中…", "ko": "감지 중…", "pt": "A detectar…", "ar": "جارٍ الاكتشاف…"],
        "locSave": ["en": "Save", "ru": "Сохранить", "es": "Guardar", "fr": "Enregistrer", "de": "Speichern", "zh": "保存", "ja": "保存", "ko": "저장", "pt": "Guardar", "ar": "حفظ"],
        "locLeaveBlankDirect": ["en": "Leave blank for direct connection", "ru": "Оставьте пустым для прямого подключения", "es": "Dejar en blanco para conexión directa", "fr": "Laisser vide pour une connexion directe", "de": "Für direkte Verbindung leer lassen", "zh": "留空以直接连接", "ja": "直接接続の場合は空白にする", "ko": "직접 연결하려면 비워두세요", "pt": "Deixar em branco para ligação direta", "ar": "اتركه فارغًا للاتصال المباشر"],
        "locAll": ["en": "All", "ru": "Все", "es": "Todos", "fr": "Tous", "de": "Alle", "zh": "全部", "ja": "すべて", "ko": "모두", "pt": "Todos", "ar": "الكل"],
        "locSelectProviderToBrowse": ["en": "Select a provider to browse its models.", "ru": "Выберите провайдера для просмотра его моделей.", "es": "Seleccione un proveedor para explorar sus modelos.", "fr": "Sélectionnez un fournisseur pour parcourir ses modèles.", "de": "Wählen Sie einen Anbieter, um seine Modelle zu durchsuchen.", "zh": "选择提供商以浏览其模型。", "ja": "プロバイダーを選択してモデルを閲覧してください。", "ko": "모델을 탐색할 공급자를 선택하세요.", "pt": "Selecione um provedor para explorar os seus modelos.", "ar": "اختر مزودًا لاستعراض نماذجه."],
        "locStartLocalAgent": ["en": "Start the local agent or check the provider connection to load models.", "ru": "Запустите локального агента или проверьте подключение провайдера для загрузки моделей.", "es": "Inicie el agente local o compruebe la conexión del proveedor para cargar modelos.", "fr": "Démarrez l'agent local ou vérifiez la connexion du fournisseur pour charger les modèles.", "de": "Starten Sie den lokalen Agenten oder überprüfen Sie die Anbieterverbindung, um Modelle zu laden.", "zh": "启动本地代理或检查提供商连接以加载模型。", "ja": "ローカルエージェントを起動するか、プロバイダーの接続を確認してモデルを読み込みます。", "ko": "로컬 에이전트를 시작하거나 공급자 연결을 확인하여 모델을 로드하세요.", "pt": "Inicie o agente local ou verifique a ligação do provedor para carregar modelos.", "ar": "ابدأ الوكيل المحلي أو تحقق من اتصال المزود لتحميل النماذج."],
        "locYes": ["en": "Yes", "ru": "Да", "es": "Sí", "fr": "Oui", "de": "Ja", "zh": "是", "ja": "はい", "ko": "예", "pt": "Sim", "ar": "نعم"],
        "locNo": ["en": "No", "ru": "Нет", "es": "No", "fr": "Non", "de": "Nein", "zh": "否", "ja": "いいえ", "ko": "아니요", "pt": "Não", "ar": "لا"],
        "locSupported": ["en": "Supported", "ru": "Поддерживается", "es": "Soportado", "fr": "Pris en charge", "de": "Unterstützt", "zh": "支持", "ja": "サポートあり", "ko": "지원됨", "pt": "Suportado", "ar": "مدعوم"],
        "locNotSupported": ["en": "Not supported", "ru": "Не поддерживается", "es": "No soportado", "fr": "Non pris en charge", "de": "Nicht unterstützt", "zh": "不支持", "ja": "サポートなし", "ko": "지원되지 않음", "pt": "Não suportado", "ar": "غير مدعوم"],
        "locPer1KTokens": ["en": "per 1K tokens", "ru": "за 1K токенов", "es": "por 1K tokens", "fr": "par 1K tokens", "de": "pro 1K Tokens", "zh": "每 1K token", "ja": "1Kトークンあたり", "ko": "1K 토큰당", "pt": "por 1K tokens", "ar": "لكل 1K رمز"],
        "locToolResultFixOn": ["en": "Tool result fix: ON", "ru": "Исправление результата инструмента: ВКЛ", "es": "Corrección de resultado de herramienta: ON", "fr": "Correction du résultat d'outil : ON", "de": "Tool-Ergebnis-Fix: EIN", "zh": "工具结果修复：开", "ja": "ツール結果修正：ON", "ko": "도구 결과 수정: 켜기", "pt": "Correção do resultado da ferramenta: ON", "ar": "إصلاح نتيجة الأداة: تشغيل"],
        "locToolResultFixOff": ["en": "Tool result fix: OFF", "ru": "Исправление результата инструмента: ВЫКЛ", "es": "Corrección de resultado de herramienta: OFF", "fr": "Correction du résultat d'outil : OFF", "de": "Tool-Ergebnis-Fix: AUS", "zh": "工具结果修复：关", "ja": "ツール結果修正：OFF", "ko": "도구 결과 수정: 끄기", "pt": "Correção do resultado da ferramenta: OFF", "ar": "إصلاح نتيجة الأداة: إيقاف"],
        "locConnectionSuccess": ["en": "Success! Provider is reachable.", "ru": "Успех! Провайдер доступен.", "es": "¡Éxito! El proveedor es accesible.", "fr": "Succès ! Le fournisseur est accessible.", "de": "Erfolg! Anbieter ist erreichbar.", "zh": "成功！提供商可达。", "ja": "成功！プロバイダーにアクセスできます。", "ko": "성공! 공급자에 연결할 수 있습니다.", "pt": "Sucesso! O provedor está acessível.", "ar": "نجح! المزود قابل للوصول."],
        "locWebLoginTitle": ["en": "Log in to", "ru": "Войти в", "es": "Iniciar sesión en", "fr": "Se connecter à", "de": "Anmelden bei", "zh": "登录", "ja": "ログイン", "ko": "로그인", "pt": "Entrar em", "ar": "تسجيل الدخول إلى"],
        "locWebDetectModels": ["en": "Detect models", "ru": "Определить модели", "es": "Detectar modelos", "fr": "Détecter les modèles", "de": "Modelle erkennen", "zh": "检测模型", "ja": "モデルを検出", "ko": "모델 감지", "pt": "Detectar modelos", "ar": "اكتشاف النماذج"],
        "locWebDetectModelsHelp": ["en": "Auto-detect available models from the page", "ru": "Автоопределение моделей со страницы", "es": "Auto-detectar modelos de la página", "fr": "Auto-détecter les modèles de la página", "de": "Modelle automatisch von der Seite erkennen", "zh": "从页面自动检测模型", "ja": "ページからモデルを自動検出", "ko": "페이지에서 모델 자동 감지", "pt": "Auto-detectar modelos da página", "ar": "اكتشاف النماذج تلقائيًا من الصفحة"],
        "locWebCaptureSession": ["en": "Capture session & close", "ru": "Захватить сессию и закрыть", "es": "Capturar sesión y cerrar", "fr": "Capturer la session et fermer", "de": "Sitzung erfassen & schließen", "zh": "捕获会话并关闭", "ja": "セッションをキャプチャして閉じる", "ko": "세션 캡처 및 닫기", "pt": "Capturar sessão e fechar", "ar": "التقاط الجلسة وإغلاقها"],
        "locWebDetecting": ["en": "Detecting models...", "ru": "Определение моделей...", "es": "Detectando modelos...", "fr": "Détection des modèles...", "de": "Modelle werden erkannt...", "zh": "正在检测模型...", "ja": "モデルを検出中...", "ko": "모델 감지 중...", "pt": "Detectando modelos...", "ar": "جارٍ اكتشاف النماذج..."],
        "locWebModelsFound": ["en": "models found", "ru": "моделей найдено", "es": "modelos encontrados", "fr": "modèles trouvés", "de": "Modelle gefunden", "zh": "个模型已找到", "ja": "モデルが見つかりました", "ko": "모델 발견", "pt": "modelos encontrados", "ar": "نماذج تم العثور عليها"],
        "locWebNoSelector": ["en": "No model selector configured for this vendor", "ru": "Селектор моделей не настроен", "es": "Selector de modelos no configurado", "fr": "Sélecteur de modèles non configuré", "de": "Modellauswahl nicht konfiguriert", "zh": "未配置模型选择器", "ja": "モデルセレクター未設定", "ko": "모델 선택기가 구성되지 않음", "pt": "Seletor de modelos não configurado", "ar": "لم يتم تكوين محدد النماذج"],
        "locShowInFinder": ["en": "Show in Finder", "ru": "Показать в Finder", "es": "Mostrar en Finder", "fr": "Afficher dans le Finder", "de": "Im Finder anzeigen", "zh": "在 Finder 中显示", "ja": "Finder に表示", "ko": "Finder에 표시", "pt": "Mostrar no Finder", "ar": "إظهار في Finder"],
        "locStop": ["en": "Stop", "ru": "Остановить", "es": "Detener", "fr": "Arrêter", "de": "Stoppen", "zh": "停止", "ja": "停止", "ko": "중지", "pt": "Parar", "ar": "إيقاف"],
        "locModelPlaceholder": ["en": "Model", "ru": "Модель", "es": "Modelo", "fr": "Modèle", "de": "Modell", "zh": "模型", "ja": "モデル", "ko": "모델", "pt": "Modelo", "ar": "النموذج"],
        "locVariantPlaceholder": ["en": "Variant", "ru": "Вариант", "es": "Variante", "fr": "Variante", "de": "Variante", "zh": "变体", "ja": "バリアント", "ko": "변형", "pt": "Variante", "ar": "المتغير"],
        "locManageModels": ["en": "Manage models", "ru": "Управление моделями", "es": "Gestionar modelos", "fr": "Gérer les modèles", "de": "Modelle verwalten", "zh": "管理模型", "ja": "モデルを管理", "ko": "모델 관리", "pt": "Gerir modelos", "ar": "إدارة النماذج"],
        "locManageProviders": ["en": "Manage providers", "ru": "Управление провайдерами", "es": "Gestionar proveedores", "fr": "Gérer les fournisseurs", "de": "Anbieter verwalten", "zh": "管理提供商", "ja": "プロバイダーを管理", "ko": "공급자 관리", "pt": "Gerir provedores", "ar": "إدارة الموفرين"],
        "locHost": ["en": "Host", "ru": "Хост", "es": "Host", "fr": "Hôte", "de": "Host", "zh": "主机", "ja": "ホスト", "ko": "호스트", "pt": "Host", "ar": "المضيف"],
        "locPort": ["en": "Port", "ru": "Порт", "es": "Puerto", "fr": "Port", "de": "Port", "zh": "端口", "ja": "ポート", "ko": "포트", "pt": "Porta", "ar": "المنفذ"],
        "locNoVariants": ["en": "No variants available", "ru": "Нет доступных вариантов", "es": "No hay variantes disponibles", "fr": "Aucune variante disponible", "de": "Keine Varianten verfügbar", "zh": "没有可用的变体", "ja": "バリアントがありません", "ko": "사용 가능한 변형 없음", "pt": "Nenhuma variante disponível", "ar": "لا توجد متغيرات متاحة"],
        "locSearchWorkspaces": ["en": "Search workspaces", "ru": "Поиск рабочих областей", "es": "Buscar espacios de trabajo", "fr": "Rechercher des espaces de travail", "de": "Arbeitsbereiche suchen", "zh": "搜索工作区", "ja": "ワークスペースを検索", "ko": "작업 공간 검색", "pt": "Pesquisar espaços de trabalho", "ar": "البحث عن مساحات العمل"],
        "locSelectWorkspace": ["en": "Select workspace", "ru": "Выберите рабочую область", "es": "Seleccionar espacio de trabajo", "fr": "Sélectionner un espace de travail", "de": "Arbeitsbereich auswählen", "zh": "选择工作区", "ja": "ワークスペースを選択", "ko": "작업 공간 선택", "pt": "Selecionar espaço de trabalho", "ar": "حدد مساحة العمل"],
                "locPlanModeUnavailable": ["en": "Plan mode is unavailable for the selected provider/model.", "ru": "Режим планирования недоступен для выбранного провайдера/модели.", "es": "El modo de planificación no está disponible para el proveedor/modelo seleccionado.", "fr": "Le mode planification n'est pas disponible pour le fournisseur/modèle sélectionné.", "de": "Planmodus ist für den gewählten Anbieter/Modell nicht verfügbar.", "zh": "计划模式对所选提供商/模型不可用。", "ja": "選択したプロバイダー/モデルでは計画モードは利用できません。", "ko": "선택한 공급자/모델에 대해 계획 모드를 사용할 수 없습니다.", "pt": "O modo de planejamento não está disponível para o provedor/modelo selecionado.", "ar": "وضع التخطيط غير متوفر للموفر/النموذج المحدد."],
        "locProvider": ["en": "Provider", "ru": "Провайдер", "es": "Proveedor", "fr": "Fournisseur", "de": "Anbieter", "zh": "提供商", "ja": "プロバイダー", "ko": "공급자", "pt": "Provedor", "ar": "الموفر"],
        "locModelParameters": ["en": "Model parameters", "ru": "Параметры модели", "es": "Parámetros del modelo", "fr": "Paramètres du modèle", "de": "Modellparameter", "zh": "模型参数", "ja": "モデルパラメータ", "ko": "모델 매개변수", "pt": "Parâmetros do modelo", "ar": "معلمات النموذج"],
        "locAccessAskBefore": ["en": "Ask before changes", "ru": "Спрашивать перед изменениями", "es": "Preguntar antes de cambios", "fr": "Demander avant les modifications", "de": "Vor Änderungen fragen", "zh": "更改前询问", "ja": "変更前に確認", "ko": "변경 전 묻기", "pt": "Perguntar antes das alterações", "ar": "اسأل قبل التغييرات"],
        "locAccessEditAuto": ["en": "Edit automatically", "ru": "Редактировать автоматически", "es": "Editar automáticamente", "fr": "Modifier automatisch", "de": "Automatisch bearbeiten", "zh": "自动编辑", "ja": "自動編集", "ko": "자동 편집", "pt": "Editar automaticamente", "ar": "تحرير تلقائي"],
        "locAccessFull": ["en": "Full access", "ru": "Полный доступ", "es": "Acceso completo", "fr": "Accès complet", "de": "Volлер Zugriff", "zh": "完全访问", "ja": "フルアクセス", "ko": "전체 접근", "pt": "Acesso total", "ar": "وصول كامل"],
        "locAccessAskBeforeDesc": ["en": "Ask before file changes.", "ru": "Спрашивать перед изменением файлов.", "es": "Preguntar antes de cambios.", "fr": "Demander avant les modifications.", "de": "Vor Änderungen fragen.", "zh": "文件更改前询问。", "ja": "ファイル変更前に確認します。", "ko": "파일 변경 전 묻습니다.", "pt": "Perguntar antes de alterações.", "ar": "اسأل قبل تغيير الملفات."],
        "locAccessEditAutoDesc": ["en": "Edit files automatically.", "ru": "Автоматически редактировать файлы.", "es": "Editar archivos automáticamente.", "fr": "Modifier les fichiers automatisch.", "de": "Dateien automatisch bearbeitен.", "zh": "自动编辑文件。", "ja": "ファイルを自動編集します。", "ko": "파일을 자동으로 편집합니다.", "pt": "Editar ficheiros automaticamente.", "ar": "تحرير الملفات تلقائيًا."],
        "locAccessFullDesc": ["en": "Run with fewer confirmations.", "ru": "Работать с меньшим количеством подтверждений.", "es": "Ejecutar с меньшим числом подтверждений.", "fr": "Exécutер с moins de confirmations.", "de": "Mit weniger Bestätigungen ausführen.", "zh": "运行需要更少的确认。", "ja": "確認を減らして実行します。", "ko": "확인 횟수를 줄여 실行します.", "pt": "Executer с меньшим числом подтверждений.", "ar": "تشغيل بتأكيدات меньше."],
        "locModeBuild": ["en": "Build", "ru": "Кодинг", "es": "Construir", "fr": "Construire", "de": "Build", "zh": "构建", "ja": "ビルド", "ko": "빌드", "pt": "Construir", "ar": "بناء"],
        "locModePlan": ["en": "Plan", "ru": "План", "es": "Plan", "fr": "Plan", "de": "Plan", "zh": "计划", "ja": "プラン", "ko": "계획", "pt": "Plano", "ar": "خطة"],
        "locModeCompose": ["en": "Compose", "ru": "Сочинение", "es": "Componer", "fr": "Composer", "de": "Verfassen", "zh": "撰写", "ja": "コンポーズ", "ko": "작성", "pt": "Compor", "ar": "تأليف"],
        "locParametersFor": ["en": "Parameters", "ru": "Параметры", "es": "Parámetros", "fr": "Paramètres", "de": "Parameter", "zh": "参数", "ja": "パラメータ", "ko": "매개변수", "pt": "Parâmetros", "ar": "المعلمات"],
        "locStopGeneration": ["en": "Stop generation", "ru": "Остановить генерацию", "es": "Detener generación", "fr": "Arrêter la génération", "de": "Generierung stoppen", "zh": "停止生成", "ja": "生成を停止", "ko": "생성 중지", "pt": "Parar geração", "ar": "إيقاف التوليد"],
        "locSendMessage": ["en": "Send message", "ru": "Отправить сообщение", "es": "Enviar mensaje", "fr": "Envoyer le message", "de": "Nachricht senden", "zh": "发送消息", "ja": "メッセージを送信", "ko": "메시지 보내기", "pt": "Enviar mensagem", "ar": "إرسال الرسالة"],
        "locSendNow": ["en": "Send now", "ru": "Отправить сейчас", "es": "Enviar ahora", "fr": "Envoyer maintenant", "de": "Jetzt senden", "zh": "立即发送", "ja": "今すぐ送信", "ko": "지금 보내기", "pt": "Enviar agora", "ar": "إرسال الآن"],
        "locQueueMessage": ["en": "Add to queue", "ru": "Добавить в очередь", "es": "Añadir a la cola", "fr": "Ajouter à la file d'attente", "de": "Zur Warteschlange hinzufügen", "zh": "加入队列", "ja": "キューに追加", "ko": "대기열에 추가", "pt": "Adicionar à fila", "ar": "إضافة إلى قائمة الانتظار"],
        "locEditQueuedMessage": ["en": "Edit queued message", "ru": "Редактировать сообщение в очереди", "es": "Editar mensaje en cola", "fr": "Modifier le message en file d'attente", "de": "Wartende Nachricht bearbeiten", "zh": "编辑排队消息", "ja": "待機中のメッセージを編集", "ko": "대기 중인 메시지 편집", "pt": "Editar mensagem na fila", "ar": "تحرير الرسالة في قائمة الانتظار"],
        "locDeleteQueuedMessage": ["en": "Delete queued message", "ru": "Удалить сообщение из очереди", "es": "Eliminar mensaje en cola", "fr": "Supprimer le message en file d'attente", "de": "Wartende Nachricht löschen", "zh": "删除排队消息", "ja": "待機中のメッセージを削除", "ko": "대기 중인 메시지 삭제", "pt": "Eliminar mensagem na fila", "ar": "حذف الرسالة من قائمة الانتظار"],
        "locPointContext": ["en": "Point context", "ru": "Точечный контекст", "es": "Contexto puntual", "fr": "Contexte ciblé", "de": "Gezielter Kontext", "zh": "精准上下文", "ja": "ポイントコンテキスト", "ko": "포인트 컨텍스트", "pt": "Contexto pontual", "ar": "سياق نقطي"],
        "locPointContextDescription": ["en": "Before each send, collect the exact files, symbols and line ranges the message is about and attach them as evidence. Runs locally; the displayed message stays unchanged.", "ru": "Перед каждой отправкой собирать из индекса точные файлы, символы и строки, о которых идёт речь, и прикладывать их как доказательства. Работает локально; текст сообщения не меняется.", "es": "Antes de cada envío, reúne los archivos, símbolos y líneas exactos del mensaje y los adjunta como evidencia. Se ejecuta localmente; el mensaje mostrado no cambia.", "fr": "Avant chaque envoi, rassemble les fichiers, symboles et lignes exacts du message et les joint comme preuves. S'exécute localement ; le message affiché reste inchangé.", "de": "Vor jedem Senden die genauen Dateien, Symbole und Zeilen der Nachricht sammeln und als Belege anhängen. Läuft lokal; die angezeigte Nachricht bleibt unverändert.", "zh": "每次发送前，收集消息涉及的精确文件、符号和行范围，并作为证据附加。本地运行；显示的消息保持不变。", "ja": "送信前に、メッセージが対象とするファイル・シンボル・行範囲を正確に集めて証拠として添付します。ローカルで動作し、表示されるメッセージは変わりません。", "ko": "보낼 때마다 메시지가 가리키는 파일, 심볼, 줄 범위를 정확히 모아 증거로 첨부합니다. 로컬에서 실행되며 표시되는 메시지는 그대로입니다.", "pt": "Antes de cada envio, reúne os arquivos, símbolos e linhas exatos da mensagem e os anexa como evidência. Roda localmente; a mensagem exibida não muda.", "ar": "قبل كل إرسال، اجمع الملفات والرموز ونطاقات الأسطر المقصودة بدقة وأرفقها كأدلة. يعمل محليًا؛ الرسالة المعروضة لا تتغير."],
        "locCompilingPointContext": ["en": "Building point context…", "ru": "Собираем точечный контекст…", "es": "Preparando contexto puntual…", "fr": "Préparation du contexte ciblé…", "de": "Gezielter Kontext wird erstellt…", "zh": "正在构建精准上下文…", "ja": "ポイントコンテキストを準備中…", "ko": "포인트 컨텍스트 구성 중…", "pt": "Preparando contexto pontual…", "ar": "جارٍ تجهيز السياق النقطي…"],
        "locShowCompiledContext": ["en": "Context", "ru": "Контекст", "es": "Contexto", "fr": "Contexte", "de": "Kontext", "zh": "上下文", "ja": "コンテキスト", "ko": "컨텍스트", "pt": "Contexto", "ar": "السياق"],
        "locCompiledContextTitle": ["en": "Compiled point context", "ru": "Собранный точечный контекст", "es": "Contexto puntual compilado", "fr": "Contexte ciblé compilé", "de": "Kompilierter gezielter Kontext", "zh": "已编译的精准上下文", "ja": "コンパイル済みポイントコンテキスト", "ko": "컴파일된 포인트 컨텍스트", "pt": "Contexto pontual compilado", "ar": "السياق النقطي المُجمَّع"],
        "locContextCompilationFailed": ["en": "Could not build the point context", "ru": "Не удалось собрать точечный контекст", "es": "No se pudo preparar el contexto puntual", "fr": "Impossible de préparer le contexte ciblé", "de": "Gezielter Kontext konnte nicht erstellt werden", "zh": "无法构建精准上下文", "ja": "ポイントコンテキストを構築できませんでした", "ko": "포인트 컨텍스트를 만들지 못했습니다", "pt": "Não foi possível preparar o contexto pontual", "ar": "تعذر تجهيز السياق النقطي"],
        "locMemorySaved": ["en": "Remembered", "ru": "Запомнил", "es": "Recordado", "fr": "Mémorisé", "de": "Gemerkt", "zh": "已记住", "ja": "記憶しました", "ko": "기억함", "pt": "Memorizado", "ar": "تم التذكر"],
        "locMemoryFailed": ["en": "Could not save this to project memory", "ru": "Не удалось сохранить это в память проекта", "es": "No se pudo guardar en la memoria del proyecto", "fr": "Impossible d'enregistrer dans la mémoire du projet", "de": "Konnte nicht im Projektgedächtnis gespeichert werden", "zh": "无法保存到项目记忆", "ja": "プロジェクトメモリに保存できませんでした", "ko": "프로젝트 메모리에 저장하지 못했습니다", "pt": "Não foi possível salvar na memória do projeto", "ar": "تعذر حفظ هذا في ذاكرة المشروع"],
        "locMemoryUsage": ["en": "Usage: /remember <fact about the project>", "ru": "Использование: /remember <факт о проекте>", "es": "Uso: /remember <dato sobre el proyecto>", "fr": "Usage : /remember <fait sur le projet>", "de": "Verwendung: /remember <Fakt zum Projekt>", "zh": "用法：/remember <项目事实>", "ja": "使い方: /remember <プロジェクトに関する事実>", "ko": "사용법: /remember <프로젝트에 대한 사실>", "pt": "Uso: /remember <fato sobre o projeto>", "ar": "الاستخدام: /remember <حقيقة عن المشروع>"],
        "locMemoryLoadFailed": ["en": "Project memory could not be read; this answer uses files only", "ru": "Память проекта не прочитана; ответ опирается только на файлы", "es": "No se pudo leer la memoria del proyecto; la respuesta usa solo archivos", "fr": "La mémoire du projet n'a pas pu être lue ; la réponse s'appuie uniquement sur les fichiers", "de": "Das Projektgedächtnis konnte nicht gelesen werden; die Antwort nutzt nur Dateien", "zh": "无法读取项目记忆；本次回答仅基于文件", "ja": "プロジェクトメモリを読み込めませんでした。この回答はファイルのみを使用します", "ko": "프로젝트 메모리를 읽지 못했습니다. 이 답변은 파일만 사용합니다", "pt": "Não foi possível ler a memória do projeto; esta resposta usa apenas arquivos", "ar": "تعذرت قراءة ذاكرة المشروع؛ تعتمد هذه الإجابة على الملفات فقط"],
        "locLedgerFailed": ["en": "Task state could not be saved; this answer may miss earlier constraints", "ru": "Состояние задачи не сохранено; в ответе могут потеряться прежние ограничения", "es": "No se pudo guardar el estado de la tarea; la respuesta puede omitir restricciones anteriores", "fr": "L'état de la tâche n'a pas pu être enregistré ; la réponse peut manquer de contraintes antérieures", "de": "Der Aufgabenstand konnte nicht gespeichert werden; der Antwort können frühere Einschränkungen fehlen", "zh": "任务状态未能保存；回答可能遗漏之前的约束", "ja": "タスク状態を保存できませんでした。以前の制約が回答に含まれない可能性があります", "ko": "작업 상태를 저장하지 못했습니다. 이전 제약이 답변에서 빠질 수 있습니다", "pt": "Não foi possível salvar o estado da tarefa; a resposta pode omitir restrições anteriores", "ar": "تعذر حفظ حالة المهمة؛ قد تفوت هذه الإجابة قيودًا سابقة"],
        "locWebNoSelectorYet": ["en": "This provider does not expose a model-list selector yet.", "ru": "У этого провайдера нет селектора списка моделей.", "es": "Este proveedor no expone un selector de lista de modelos.", "fr": "Ce fournisseur n'expose pas encore de sélecteur de liste de modèles.", "de": "Dieser Anbieter stellt noch keine Modellauswahl bereit.", "zh": "此提供商尚未公开模型列表选择器。", "ja": "このプロバイダーはモデルリストセレクターを公開していません。", "ko": "이 공급자는 모델 목록 선택기를 노출하지 않습니다.", "pt": "Este provedor aindaне expõe um seletor de lista de modelos.", "ar": "لا يعرض هذا الموفر محدد قائمة النماذج после."],

        "locWebLoginFirst": ["en": "Log in first, then capture the web session before refreshing models.", "ru": "Сначала войдите, затем захватите веб-сессию.", "es": "Inicia sesión primero, luego captura la sesión web.", "fr": "Connectез-vous d'abord, puis capturez la session web.", "de": "Melden Sie sich zuerst an, dann erfassen Sie die Web-Sitzунг.", "zh": "请先登录，然后捕获网络会话。", "ja": "最初にログインしてから、Webセッションをキャプチャしてください。", "ko": "먼저 로그인한 다음 웹 세션을 캡처하세요.", "pt": "Faça login primeiro, depois capture a sessão web.", "ar": "سجل الدخول أولاً، ثم التقط جلسة 的ويب."],
        "locWebModelListFailed": ["en": "Could not read model list from %@. The model selector may only appear after starting a chat. Try the 🔎 element picker in the login window.", "ru": "Не удалось прочитать список моделей из %@. Попробуйте 🔎 в окне входа.", "es": "No se pudo leer la lista de modelос из %@. Prueba 🔎 en la ventana de inicio de sesión.", "fr": "Impossible de lire la liste из %@. Essayez 🔎 dans la fenêtre de connexion.", "de": "Modelliste konnte nicht von %@ gelesen werden. Versуйте 🔎.", "zh": "无法从 %@ 读取模型列表。请在登录窗口中尝试 🔎。", "ja": "%@ から モデルリストを読み取れมせん。ログインウィンドウで 🔎 をお試しください。", "ko": "%@에서 モ델 목록을 読めません。ログイン 창에서 🔎를 시도하세요.", "pt": "Não foi possível ler a lista de modelос из %@. Tente 🔎 na janela de login.", "ar": "تعذرت قراءة قائمة النماذج من %@. جرب 🔎 في نافذة تسجيل الدخول."],
        "locWebLoadedModels": ["en": "Loaded %d model%@ from %@.", "ru": "Загружено %d моделей из %@.", "es": "Cargados %d modelос из %@.", "fr": "%d modèles chargés depuis %@.", "de": "%d Modelле из %@ geladen.", "zh": "已从 %@ 加载 %d 个模型。", "ja": "%@ から %d モデルを読み込みました。", "ko": "%@에서 %d개 모델을 로드했습니다.", "pt": "%d modelос carregados de %@.", "ar": "تم تحميل %d نموذج من %@."],
        "locWebRefreshFailed": ["en": "Could not refresh models: %@", "ru": "Не удалось обновить модели: %@", "es": "No se pudieron actualizar los modelос: %@", "fr": "Impossible d'actualiser les modèles: %@", "de": "Modelle konnten nicht aktualisiert werden: %@", "zh": "无法刷新模型：%@", "ja": "モデルを更新できませんでした：%@", "ko": "モ델을 새로고침할 수 없습니다: %@", "pt": "Não fue possível atualizar los modelос: %@", "ar": "تعذر تحديث النماذج: %@"],
        "locWebEffortNoSelector": ["en": "This provider does not expose an effort/thinking dropdown selector yet.", "ru": "У этого провайдера нет селектора уровней мышления.", "es": "Este proveedor no expone un selector de esfuerzo/pensamiento.", "fr": "Ce fournisseur n'expose pas de sélecteur d'effort/réflexion.", "de": "Diesер Anbieter stellt noch keine Denkstufen-Auswahl bereit.", "zh": "此提供商尚未公开推理级别选择器。", "ja": "このプロバイダーは思考レベルセレクターを公開していません。", "ko": "이 공급자는 사고 수준 선택기를 노출하지 않습니다.", "pt": "Este provedor não expõe um seletor de esforço/pensamento.", "ar": "لا يعرض هذا الموفر محدد مستوى التفكير بعد."],
        "locWebEffortLoginFirst": ["en": "Log in first, then capture the web session before refreshing effort levels.", "ru": "Сначала войдите, затем захватите сессию для обновления уровней.", "es": "Inicia sesión primero, luego captura la sesión para actualizar niveles.", "fr": "Connectез-vous d'abord, puis capturez la session.", "de": "Melдитесь zuerst an, dann erfassen Sie die Sitzung.", "zh": "请先登录，然后捕获会话。", "ja": "最初にログインしてから、Webセッションをキャプチャしてください。", "ko": "먼저 로그인한 다음 세SSION을 캡처하세요.", "pt": "Faça login primeiro, depois capture a sessão.", "ar": "سجل الدخول أولاً، ثم التقط جلسة."],
        "locWebEffortInputNotFound": ["en": "Chat input was not found. The saved session may have expired; log in again.", "ru": "Поле ввода не найдено. Сессия истекла; войдите снова.", "es": "No se encontró el campо. La sesión expiró; inicia sesión.", "fr": "Champ introuvable. Session expiré; reconnectез-vous.", "de": "Eingabe nicht gefunden. Sitzング abgelaufен; erneut anmelден.", "zh": "未找到输入。会话已过期；请重新登录。", "ja": "入力が見つかりาせん。セSSIONが切れました。", "ko": "입력을 찾을 수 없습니다. 세SSION이 만료되었습니다.", "pt": "Entрada de chat não encontrada. A sessão expirou; faça login.", "ar": "لم Пользователь: НАКОНЕЦТО ПОКАЗЫВАЕТСЬ! الآن أيقونة .app! возможно docker кешировал старую!"],
        "locWebEffortReadFailed": ["en": "Could not read the effort levels from %@. Try Refresh after the chat page finishes loading.", "ru": "Не удалось прочитать уровни из %@. Попробуйте обновить после загрузки.", "es": "No se pudo leer los níveles de %@. Intenta actualizar después de cargar.", "fr": "Impossible de read the effort levels from %@. Essayez d'actualiser.", "de": "Stufen konnte nicht von %@ gelesen werden.", "zh": "无法从 %@ 读取级别。加载完成后重试。", "ja": "%@ から レベル을 読み取れませんでした。", "ko": "%@에서 수준을 読めません。", "pt": "Não fue possível ler os níveles de %@.", "ar": "تعذرت чтение уровней 从 %@."],
        "locWebLoadedEffort": ["en": "Loaded %d effort level%@ from %@.", "ru": "Загружено %d уровней из %@.", "es": "Cargados %d níveles de %@.", "fr": "%d níveis chargés depuis %@.", "de": "%d Stufen von %@ geladen.", "zh": "已从 %@ 加载 %d 个级别。", "ja": "%@ から %d レベル을 読み込みました。", "ko": "%@에서 %d개 수준을 로드했습니다.", "pt": "%d níveles carregados de %@.", "ar": "تم تحميل %d مستوى من %@."],
        "locWebEffortRefreshFailed": ["en": "Could not refresh effort levels: %@", "ru": "Не удалось обновить уровни: %@", "es": "No se pudo actualizar os níveles: %@", "fr": "Impossible d'actualiser les níveles: %@", "de": "Stufen konnten nicht aktualisiert werden: %@", "zh": "无法刷新级别：%@", "ja": "レベルを更新できませんでした：%@", "ko": "数준을 새로고침할 수 없습니다: %@", "pt": "Não fue possível atualizar os níveles: %@", "ar": "تعذر تحديث المستويات: %@"],
        "locWebRequiresWebKit": ["en": "Web providers require WebKit (macOS).", "ru": "Веб-провайдеры требуют WebKit (macOS).", "es": "Los proveedores web requiren WebKit (macOS).", "fr": "Les fournisseurs web nécessitent WebKit (macOS).", "de": "Web-Anbieter erfordern WebKit (macOS).", "zh": "网络提供商需要 WebKit (macOS)。", "ja": "WebプロバイダーにはWebkit（macOS）が必要です。", "ko": "웹 공급자는 Webkit(macOS)가 필요합니다.", "pt": "Provedores web requerem WebKit (macOS).", "ar": "موفرو الويب يتطلبون Webkit (macOS)."],
        "locToolCallDelay": ["en": "Tool-call delay", "ru": "Задержка вызова инструментов", "es": "Retraso de llamada a herramientas", "fr": "Délai d'appel d'outils", "de": "Tool-Aufruf-Verzögerung", "zh": "工具调用延迟", "ja": "ツール呼び出し遅延", "ko": "도구 호출 지연", "pt": "Atraso na chamada de ferramentas", "ar": "تأخير استدعاء الأدوات"],
        "locKeepalive": ["en": "Keep-alive", "ru": "Поддержание соединения", "es": "Mantener activo", "fr": "Maintenir actif", "de": "Keep-alive", "zh": "保活", "ja": "キープアライブ", "ko": "연결 유지", "pt": "Manter ativo", "ar": "البقاء متصلًا"],
        "locTransport": ["en": "Transport", "ru": "Транспорт", "es": "Transporte", "fr": "Transport", "de": "Transport", "zh": "传输", "ja": "トランスポート", "ko": "전송", "pt": "Transporte", "ar": "نقل"],
        "locGitHubCliNotInstalled": ["en": "GitHub CLI is not installed or not signed in. Use the publish wizard to set it up.", "ru": "GitHub CLI не установлен или не выполнен вход. Используйте мастер публикации.", "es": "GitHub CLI no está instalado o no has iniciado sesión. Usa el asistente de publicación.", "fr": "GitHub CLI n'est pas installé ou non connecté. Utilisez l'assistant de publication.", "de": "GitHub CLI ist nicht installiert oder nicht angemeldet. Verwenden Sie den Veröffentlichungsassistenten.", "zh": "GitHub CLI 未安装或未登录。使用发布向导进行设置。", "ja": "GitHub CLIがインストールされていないか、サインインしていません。公開ウィザードを使用してください。", "ko": "GitHub CLI가 설치되지 않았거나 로그인되지 않았습니다. 게시 마법사를 사용하세요.", "pt": "GitHub CLI não está instalado ou não está.connectado. Use o assistente de publicação.", "ar": "لم يتم تثبيت GitHub CLI أو لم تسجل الدخول. استخدم معالج النشر."],
        "locAddModel": ["en": "Add model name…", "ru": "Добавить имя модели…", "es": "Agregar nombre de modelo…", "fr": "Ajouter un nom de modèle…", "de": "Modellname hinzufügen…", "zh": "添加模型名称…", "ja": "モデル名を追加…", "ko": "모델 이름 추가…", "pt": "Adicionar nome do modelo…", "ar": "إضافة اسم النموذج…"],
        "locPickerTitle": ["en": "Picked Element", "ru": "Выбранный элемент", "es": "Elemento seleccionado", "fr": "Élément sélectionné", "de": "Ausgewähltes Element", "zh": "选取的元素", "ja": "選択された要素", "ko": "선택한 요소", "pt": "Elemento selecionado", "ar": "العنصر المحدد"],
        "locPickerSelector": ["en": "Selector:", "ru": "Селектор:", "es": "Selector:", "fr": "Sélecteur:", "de": "Selektor:", "zh": "选择器：", "ja": "セレクター：", "ko": "선택자:", "pt": "Seletor:", "ar": "المحدد:"],
        "locPickerTag": ["en": "Tag:", "ru": "Тег:", "es": "Etiqueta:", "fr": "Balise:", "de": "Tag:", "zh": "标签：", "ja": "タグ：", "ko": "태그:", "pt": "Etiqueta:", "ar": "العلامة:"],
        "locPickerClass": ["en": "Class:", "ru": "Класс:", "es": "Clase:", "fr": "Classe:", "de": "Klasse:", "zh": "类：", "ja": "クラス：", "ko": "클래스:", "pt": "Classe:", "ar": "الفئة:"],
        "locPickerText": ["en": "Text:", "ru": "Текст:", "es": "Texto:", "fr": "Texte:", "de": "Text:", "zh": "文本：", "ja": "テキスト：", "ko": "텍스트:", "pt": "Texto:", "ar": "النص:"],
        "locTosViolation": ["en": "I understand this may violate the service's Terms of Service", "ru": "Я понимаю, что это может нарушить условия использования сервиса", "es": "Entiendo que esto puede violar los Términos de Servicio", "fr": "Je comprends que cela peut violer les conditions d'utilisation", "de": "Ich verstehen, dass dies die Nutzungsbedingungen verletzen kann", "zh": "我理解这可能违反服务条款", "ja": "サービスの利用規約に違反する可能性があることを理解しています", "ko": "서비스 이용 약관을 위반할 수 있음을 이해합니다", "pt": "Entendo que isso pode violar os Termos de Serviço", "ar": "أفهم أن هذا قد ينتهك شروط الخدمة"],
        "locModelsCount": ["en": "%d models", "ru": "%d моделей", "es": "%d modelos", "fr": "%d modèles", "de": "%d Modelle", "zh": "%d 个模型", "ja": "%d モデル", "ko": "%d개 모델", "pt": "%d modelos", "ar": "%d نموذج"],
        "locActiveCount": ["en": "%d active", "ru": "%d активных", "es": "%d activos", "fr": "%d actifs", "de": "%d aktiv", "zh": "%d 活跃", "ja": "%d アクティブ", "ko": "%d개 활성", "pt": "%d ativos", "ar": "%d نشط"],
        "locArchivedCount": ["en": "%d archived", "ru": "%d в архиве", "es": "%d archivados", "fr": "%d archivés", "de": "%d archiviert", "zh": "%d 已归档", "ja": "%d アーカイブ", "ko": "%d개 보관됨", "pt": "%d arquivados", "ar": "%d مؤرشف"],
        "locMessageCount": ["en": "%d msg", "ru": "%d сообщ.", "es": "%d msj", "fr": "%d msg", "de": "%d Nachr.", "zh": "%d 条消息", "ja": "%d メッセージ", "ko": "%d개 메시지", "pt": "%d mens.", "ar": "%d رسالة"],
        "locEffortLow": ["en": "Low", "ru": "Низкий", "es": "Bajo", "fr": "Bas", "de": "Niedrig", "zh": "低", "ja": "低", "ko": "낮음", "pt": "Baixo", "ar": "منخفض"],
        "locEffortMedium": ["en": "Medium", "ru": "Средний", "es": "Medio", "fr": "Moyen", "de": "Mittel", "zh": "中", "ja": "中", "ko": "중간", "pt": "Médio", "ar": "متوسط"],
        "locEffortHigh": ["en": "High", "ru": "Высокий", "es": "Alto", "fr": "Haut", "de": "Hoch", "zh": "高", "ja": "高", "ko": "높음", "pt": "Alto", "ar": "عالٍ"],
        "locThinkingMode": ["en": "Thinking Mode", "ru": "Режим мышления", "es": "Modo de pensamiento", "fr": "Mode de réflexion", "de": "Denkmodus", "zh": "思考模式", "ja": "思考モード", "ko": "사고 모드", "pt": "Modo de pensamento", "ar": "وضع التفكير"],
        "locFeatureModes": ["en": "Feature Modes", "ru": "Режимы работы", "es": "Modos de función", "fr": "Modes de fonction", "de": "Funktionsmodi", "zh": "功能模式", "ja": "機能モード", "ko": "기능 모드", "pt": "Modos de recurso", "ar": "أوضاع الميزة"],
        "locWebNoModels": ["en": "No models found on page", "ru": "Модели не найдены на странице", "es": "No se encontraron modelos", "fr": "Aucun modèle trouvé", "de": "Keine Modelle gefunden", "zh": "页面中未找到模型", "ja": "ページにモデルが見つかりません", "ko": "페이지에서 모델을 찾을 수 없음", "pt": "Nenhum modelo encontrado", "ar": "لم يتم العثور على نماذج"],

        "locAuto": ["en": "Auto", "ru": "Авто", "es": "Auto", "fr": "Auto", "de": "Auto", "zh": "自动", "ja": "自動", "ko": "자동", "pt": "Auto", "ar": "تلقائي"],
        "locThink": ["en": "Think", "ru": "Думание", "es": "Pensar", "fr": "Réfléchir", "de": "Denken", "zh": "思考", "ja": "思考", "ko": "사고", "pt": "Pensar", "ar": "تفكير"],
        "locFast": ["en": "Fast", "ru": "Быстро", "es": "Rápido", "fr": "Rapide", "de": "Schnell", "zh": "快速", "ja": "高速", "ko": "빠름", "pt": "Rápido", "ar": "سريع"],
        "locDeepResearch": ["en": "Deep Research", "ru": "Глубокое исследование", "es": "Investigación profunda", "fr": "Recherche approfondie", "de": "TiefRecherche", "zh": "深度研究", "ja": "ディープリサーチ", "ko": "심층 연구", "pt": "Pesquisa profunda", "ar": "بحث عميق"],
        "locCreateImage": ["en": "Create Image", "ru": "Создать изображение", "es": "Crear imagen", "fr": "Créer une image", "de": "Bild erstellen", "zh": "创建图片", "ja": "画像を作成", "ko": "이미지 생성", "pt": "Criar imagem", "ar": "إنشاء صورة"],
        "locCreateVideo": ["en": "Create Video", "ru": "Создать видео", "es": "Crear video", "fr": "Créer une vidéo", "de": "Video erstellen", "zh": "创建视频", "ja": "動画を作成", "ko": "동영상 생성", "pt": "Criar vídeo", "ar": "إنشاء فيديو"],
        "locWebDev": ["en": "Web Dev", "ru": "Веб-разработка", "es": "Desarrollo web", "fr": "Dév web", "de": "Web-Entwicklung", "zh": "网页开发", "ja": "Web開発", "ko": "웹 개발", "pt": "Desenvolvimento web", "ar": "تطوير الويب"],
        "locTools": ["en": "Tools", "ru": "Инструменты", "es": "Herramientas", "fr": "Outils", "de": "Werkzeuge", "zh": "工具", "ja": "ツール", "ko": "도구", "pt": "Ferramentas", "ar": "أدوات"],
        "locMore": ["en": "More", "ru": "Ещё", "es": "Más", "fr": "Plus", "de": "Mehr", "zh": "更多", "ja": "もっと", "ko": "더", "pt": "Mais", "ar": "المزيد"],
        "locUpload": ["en": "Upload", "ru": "Загрузить", "es": "Subir", "fr": "Télécharger", "de": "Hochladen", "zh": "上传", "ja": "アップロード", "ko": "업로드", "pt": "Carregar", "ar": "تحميل"],
        "locSlides": ["en": "Slides", "ru": "Слайды", "es": "Diapositivas", "fr": "Diapositives", "de": "Folien", "zh": "幻灯片", "ja": "スライド", "ko": "슬라이드", "pt": "Slides", "ar": "شرائح"],
        "locSwarm": ["en": "Swarm", "ru": "Рой", "es": "Enjambre", "fr": "Essaim", "de": "Schwarm", "zh": "集群", "ja": "スウォーム", "ko": "스웜", "pt": "Enxame", "ar": "سرب"],
        "locInstant": ["en": "Instant", "ru": "Мгновенный", "es": "Instantáneo", "fr": "Instantané", "de": "Sofort", "zh": "即时", "ja": "インスタント", "ko": "즉시", "pt": "Imediato", "ar": "فوري"],
        "locK3": ["en": "K3", "ru": "K3", "es": "K3", "fr": "K3", "de": "K3", "zh": "K3", "ja": "K3", "ko": "K3", "pt": "K3", "ar": "K3"],
        "locK3Swarm": ["en": "K3 Swarm", "ru": "K3 Рой", "es": "K3 Enjambre", "fr": "K3 Essaim", "de": "K3 Schwarm", "zh": "K3 集群", "ja": "K3 スウォーム", "ko": "K3 스웜", "pt": "K3 Enxame", "ar": "K3 سرب"],
        "locThinkingEffort": ["en": "Thinking effort", "ru": "Интенсивность рассуждений", "es": "Esfuerzo de pensamiento", "fr": "Effort de réflexion", "de": "Denkaufwand", "zh": "思考强度", "ja": "思考労力", "ko": "사고 노력", "pt": "Esforço de pensamento", "ar": "جهد التفكير"],
        "locGenerationStopped": ["en": "Generation stopped", "ru": "Генерация остановлена", "es": "Generación detenida", "fr": "Génération arrêtée", "de": "Generierung gestoppt", "zh": "生成已停止", "ja": "生成が停止しました", "ko": "생성 중지됨", "pt": "Geração parada", "ar": "تم إيقاف التوليد"],
        "locTaskCompletedMessage": ["en": "Task completed", "ru": "Задача выполнена", "es": "Tarea completada", "fr": "Tâche terminée", "de": "Aufgabe abgeschlossen", "zh": "任务完成", "ja": "タスクが完了しました", "ko": "작업 완료", "pt": "Tarefa concluída", "ar": "اكتملت المهمة"],
        "locResult": ["en": "Result", "ru": "Результат", "es": "Resultado", "fr": "Résultat", "de": "Ergebnis", "zh": "结果", "ja": "結果", "ko": "결과", "pt": "Resultado", "ar": "النتيجة"],
        "locArguments": ["en": "Arguments", "ru": "Аргументы", "es": "Argumentos", "fr": "Arguments", "de": "Argumente", "zh": "参数", "ja": "引数", "ko": "인수", "pt": "Argumentos", "ar": "الوسائط"],
        "locCompleted": ["en": "Completed", "ru": "Завершено", "es": "Completado", "fr": "Terminé", "de": "Abgeschlossen", "zh": "已完成", "ja": "完了", "ko": "완료", "pt": "Concluído", "ar": "مكتمل"],
        "locRunning": ["en": "Running", "ru": "Выполняется", "es": "Ejecutando", "fr": "En cours", "de": "Läuft", "zh": "运行中", "ja": "実行中", "ko": "실행 중", "pt": "Executando", "ar": "قيد التشغيل"],
        "locResend": ["en": "Resend", "ru": "Отправить повторно", "es": "Reenviar", "fr": "Renvoyer", "de": "Erneut senden", "zh": "重新发送", "ja": "再送信", "ko": "다시 보내기", "pt": "Reenviar", "ar": "إعادة الإرسال"],
        "locCopied": ["en": "Copied", "ru": "Скопировано", "es": "Copiado", "fr": "Copié", "de": "Kopiert", "zh": "已复制", "ja": "コピーしました", "ko": "복사됨", "pt": "Copiado", "ar": "تم النسخ"],
        "locNewTaskSidebar": ["en": "New task", "ru": "Новая задача", "es": "Нueva tarea", "fr": "Nouvelle tâche", "de": "Новая Aufgabe", "zh": "Новая задача", "ja": "新しいタスク", "ko": "새 작업", "pt": "Новая tarefa", "ar": "مهمة جديدة"],
        "locMarkAllRead": ["en": "Mark All Read", "ru": "Отметить все как прочитанные", "es": "Marcar todo como leído", "fr": "Tout marquer comme lu", "de": "Alle als gelesen markieren", "zh": "全部标记为已读", "ja": "すべて既読にする", "ko": "모두 읽음으로 표시", "pt": "Marcar tudo como lido", "ar": "تحديد الكل كمقروء"],
        "locSelectFolder": ["en": "Select a folder to open as a project", "ru": "Выберите папку для открытия как проекта", "es": "Selecciona una carpeta para abrir como proyecto", "fr": "Sélectionnez un dossier à ouvrir comme projet", "de": "Ordner zum Öffnen als Projekt auswählen", "zh": "选择要作为项目打开的文件夹", "ja": "プロジェクトとして開くフォルダを選択", "ko": "프로젝트로 열 폴더 선택", "pt": "Seleccione una pasta para abrir como proyecto", "ar": "حدد مجلداً لفتحه كمشروع"],
        "locConfigured": ["en": "Configured", "ru": "Настроено", "es": "Configurado", "fr": "Configuré", "de": "Konfiguriert", "zh": "已配置", "ja": "設定済み", "ko": "구성됨", "pt": "Configurado", "ar": "تم التكوين"],
        "locLogin": ["en": "Log in", "ru": "Войти", "es": "Iniciar sesión", "fr": "Se connecter", "de": "Anmelden", "zh": "登录", "ja": "ログイン", "ko": "로그인", "pt": "Entrar", "ar": "تسجيل الدخول"],
        "locUseAsModelSelector": ["en": "Use as Model Selector", "ru": "Использовать как селектор моделей", "es": "Usar como selector de modelos", "fr": "Utiliser comme sélecteur de modèles", "de": "Als Modellauswahl verwenden", "zh": "用作模型选择器", "ja": "モデルセレクターとして使用", "ko": "모델 선택기로 사용", "pt": "Usar como seletor de modelos", "ar": "استخدم كمحدد للنماذج"],
        "locConnecting": ["en": "Connecting…", "ru": "Подключение…", "es": "Conectando…", "fr": "Connexion…", "de": "Verbindung wird hergestellt…", "zh": "连接中…", "ja": "接続中…", "ko": "연결 중…", "pt": "A ligar…", "ar": "جارٍ الاتصال…"],
        "locChooseFolder": ["en": "Choose folder", "ru": "Выберите папку", "es": "Elegir carpeta", "fr": "Choisir un dossier", "de": "Ordner wählen", "zh": "选择文件夹", "ja": "フォルダを選択", "ko": "폴더 선택", "pt": "Escolher pasta", "ar": "اختر مجلداً"],
        "locMyProject": ["en": "My Project", "ru": "Мой проект", "es": "Mi proyecto", "fr": "Mon projet", "de": "Mein Projekt", "zh": "我的项目", "ja": "マイプロジェクト", "ko": "내 프로젝트", "pt": "Meu projeto", "ar": "مشروعي"],
        "locShortSummary": ["en": "Short summary of the change", "ru": "Краткое описание изменения", "es": "Breve resumen del cambio", "fr": "Bref résumé du changement", "de": "Kurze Zusammenfassung der Änderung", "zh": "更改的简短摘要", "ja": "変更の簡単な説明", "ko": "변경 사항 요약", "pt": "Breve resumo da alteração", "ar": "ملخص موجز للتغيير"],
        "locWhatChanged": ["en": "What changed and why", "ru": "Что изменилось и почему", "es": "Qué cambió y por qué", "fr": "Ce qui a changé et pourquoi", "de": "Was geändert wurde und warum", "zh": "更改内容及原因", "ja": "変更内容と理由", "ko": "변경 사항 및 이유", "pt": "O que mudou e porquê", "ar": "ما الذي تغير ولماذا"],
        "locBranchName": ["en": "Branch name", "ru": "Имя ветки", "es": "Nombre de rama", "fr": "Nom de la branche", "de": "Branch-Name", "zh": "分支名称", "ja": "ブランチ名", "ko": "브랜치 이름", "pt": "Nome do ramo", "ar": "اسم الفرع"],
        "locCreateNewBranch": ["en": "Create New Branch", "ru": "Создать новую ветку", "es": "Crear nueva rama", "fr": "Créer une nouvelle branche", "de": "Neuen Branch erstellen", "zh": "创建新分支", "ja": "新しいブランチを作成", "ko": "새 브랜치 만들기", "pt": "Criar novo ramo", "ar": "إنشاء فرع جديد"],
        "locViewImage": ["en": "View image", "ru": "Просмотреть изображение", "es": "Ver imagen", "fr": "Voir l'image", "de": "Bild anzeigen", "zh": "查看图片", "ja": "画像을 表示", "ko": "이미지 보기", "pt": "Ver imagem", "ar": "عرض الصورة"],
        "locIgnore": ["en": "Ignore", "ru": "Игнорировать", "es": "Ignorar", "fr": "Ignorer", "de": "Ignorieren", "zh": "忽略", "ja": "无视", "ko": "무시", "pt": "Ignorar", "ar": "تجاهل"],
        "locRestoreFromBackup": ["en": "Restore from backup", "ru": "Восстановить из резервной копии", "es": "Restaurar desde copia de seguridad", "fr": "Restaurer depuis la sauvegarde", "de": "Aus Sicherung wiederherstellen", "zh": "从备份恢复", "ja": "백업에서 복원", "ko": "백업에서 복원", "pt": "Restaurar da cópia de segurança", "ar": "استعادة من النسخة الاحتياطية"],
        "locConnected": ["en": "Connected", "ru": "Подключено", "es": "Conectado", "fr": "Connecté", "de": "Verbunden", "zh": "已连接", "ja": "接続済み", "ko": "연결됨", "pt": "Ligado", "ar": "متصل"],
        "locDisconnected": ["en": "Disconnected", "ru": "Отключено", "es": "Desconectado", "fr": "Déconnecté", "de": "Getrennt", "zh": "已断开", "ja": "切断されました", "ko": "연결 끊김", "pt": "Desligado", "ar": "غير متصل"],
        "locUndoLastFileChange": ["en": "Undo Last File Change", "ru": "Отменить последнее изменение файла", "es": "Deshacer último cambio de archivo", "fr": "Annuler le dernier changement de fichier", "de": "Letzte Dateiänderung rückgängig machen", "zh": "撤销上次文件更改", "ja": "最後のファイル変更を元に戻す", "ko": "마지막 파일 변경 실행 취소", "pt": "Desfazer última alteração de ficheiro", "ar": "التراجع عن آخر تغيير في الملف"],
        "locGoal": ["en": "Goal", "ru": "Цель", "es": "Objetivo", "fr": "Objectif", "de": "Ziel", "zh": "目标", "ja": "目標", "ko": "목표", "pt": "Objetivo", "ar": "الهدف"],
        "locTerminal": ["en": "Terminal", "ru": "Терминал", "es": "Terminal", "fr": "Terminal", "de": "Terminal", "zh": "终端", "ja": "ターミナル", "ko": "터미널", "pt": "Terminal", "ar": "طرفية"],
        "locCopyChat": ["en": "Copy entire chat", "ru": "Копировать весь чат", "es": "Copiar chat completo", "fr": "Copier le chat entier", "de": "Gespräch kopieren", "zh": "复制整个对话", "ja": "チャット全体을 コピー", "ko": "전체 채팅 복사", "pt": "Copiar chat completo", "ar": "نسخ المحادثة بالكامل"],
        "locPickElement": ["en": "Pick an element on the page to use as model selector", "ru": "Выберите элемент на странице для использования как селектор моделей", "es": "Elige un elemento en la página para usar como selector de modelos", "fr": "Choisissez un élément sur la page à utiliser comme sélecteur de modèles", "de": "Element auf der Seite als Modellauswahl auswählen", "zh": "在页面上选择一个元素用作模型选择器", "ja": "ページ上の要素を選択してモデルセレクターとして使用", "ko": "모델 선택기로 사용할 페이지 요소 선택", "pt": "Escolha um elemento na página para usar como seletor de modelos", "ar": "اختر عنصراً في الصفحة لاستخدامه كمحدد للنماذج"],
        "locNotConfigured": ["en": "Not configured", "ru": "Не настроено", "es": "No configurado", "fr": "Non configuré", "de": "Nicht konfiguriert", "zh": "未配置", "ja": "未設定", "ko": "구성되지 않음", "pt": "Não configurado", "ar": "غير مُكوَّن"],
        "locConnectionFailed": ["en": "Failed to connect. Check URL and credentials.", "ru": "Не удалось подключиться. Проверьте URL и учетные данные.", "es": "Error al conectar. Compruebe URL y credenciales.", "fr": "Échec de la connexion. Vérifiez l'URL et les identifiants.", "de": "Verbindung fehlgeschlagen. URL und Anmeldedaten prüfen.", "zh": "连接失败。请检查 URL 和凭据。", "ja": "接続に失敗しました。URLと認証情報を確認してください。", "ko": "연결 실패. URL과 자격 증명을 확인하세요.", "pt": "Falha na ligação. Verifique o URL e as credenciais.", "ar": "فشل الاتصال. تحقق من عنوان URL وبيانات الاعتماد."],
        "locRequiresAPIKey": ["en": "Requires API Key", "ru": "Требуется API-ключ", "es": "Requiere clave API", "fr": "Nécessite une clé API", "de": "Erfordert API-Schlüssel", "zh": "需要 API 密钥", "ja": "APIキーが必要", "ko": "API 키 필요", "pt": "Requer chave API", "ar": "يتطلب مفتاح API"],
        "locEnableToolCalling": ["en": "Enable Tool Calling", "ru": "Включить вызов инструментов", "es": "Habilitar llamada a herramientas", "fr": "Activer l'appel d'outils", "de": "Tool-Aufruf aktivieren", "zh": "启用工具调用", "ja": "ツール呼び出しを有効化", "ko": "도구 호출 활성화", "pt": "Ativar chamada de ferramentas", "ar": "تفعيل استدعاء الأدوات"],
        "locEnableACP": ["en": "Enable ACP Protocol", "ru": "Включить протокол ACP", "es": "Habilitar protocolo ACP", "fr": "Activer le protocole ACP", "de": "ACP-Protokoll aktivieren", "zh": "启用 ACP 协议", "ja": "ACPプロトコルを有効化", "ko": "ACP 프로토콜 활성화", "pt": "Ativar protocolo ACP", "ar": "تفعيل بروتوكول ACP"],
        "locAlertRemoveSkill": ["en": "Remove skill?", "ru": "Удалить навык?", "es": "¿Eliminar habilidad?", "fr": "Supprimer la compétence ?", "de": "Skill entfernen?", "zh": "移除技能？", "ja": "スキルを削除しますか？", "ko": "스킬을 제거하시겠습니까?", "pt": "Remover habilidade?", "ar": "هل تريد إزالة المهارة؟"],
        "locAlertRemoveMCPServer": ["en": "Remove MCP server?", "ru": "Удалить MCP-сервер?", "es": "¿Eliminar servidor MCP?", "fr": "Supprimer le serveur MCP ?", "de": "MCP-Server entfernen?", "zh": "移除 MCP 服务器？", "ja": "MCPサーバーを削除しますか？", "ko": "MCP 서버를 제거하시겠습니까?", "pt": "Remover servidor MCP?", "ar": "هل تريد إزالة خادم MCP؟"],
        "locUpdate": ["en": "Update", "ru": "Обновить", "es": "Actualizar", "fr": "Mettre à jour", "de": "Aktualisieren", "zh": "更新", "ja": "更新", "ko": "업데이트", "pt": "Atualizar", "ar": "تحديث"],
        "locUpdateAvailable": ["en": "Update available", "ru": "Доступно обновление", "es": "Actualización disponible", "fr": "Mise à jour disponible", "de": "Update verfügbar", "zh": "有可用更新", "ja": "更新があります", "ko": "업데이트 사용 가능", "pt": "Atualização disponível", "ar": "يتوفر تحديث"],
        "locInstall": ["en": "Install", "ru": "Установить", "es": "Instalar", "fr": "Installer", "de": "Installieren", "zh": "安装", "ja": "インストール", "ko": "설치", "pt": "Instalar", "ar": "تثبيت"],
        "locUninstall": ["en": "Uninstall", "ru": "Удалить", "es": "Desinstalar", "fr": "Désinstaller", "de": "Deinstallieren", "zh": "卸载", "ja": "アンインストール", "ko": "제거", "pt": "Desinstalar", "ar": "إلغاء التثبيت"],
        "locRequires": ["en": "Requires", "ru": "Требуется", "es": "Requiere", "fr": "Requiert", "de": "Erfordert", "zh": "需要", "ja": "必要", "ko": "필요", "pt": "Requer", "ar": "يتطلب"],
        "locDependenciesSatisfied": ["en": "Dependencies satisfied", "ru": "Зависимости удовлетворены", "es": "Dependencias satisfechas", "fr": "Dépendances satisfaites", "de": "Abhängigkeiten erfüllt", "zh": "依赖已满足", "ja": "依存関係は満たされています", "ko": "종속성이 충족됨", "pt": "Dependências satisfeitas", "ar": "تم تلبية التبعيات"],
        "locDependenciesMissing": ["en": "Missing dependencies", "ru": "Отсутствуют зависимости", "es": "Faltan dependencias", "fr": "Dépendances manquantes", "de": "Fehlende Abhängigkeiten", "zh": "缺少依赖", "ja": "依存関係が不足しています", "ko": "누락된 종속성", "pt": "Dependências em falta", "ar": "تبعيات مفقودة"],
        "locNote": ["en": "Note", "ru": "Примечание", "es": "Nota", "fr": "Remarque", "de": "Hinweis", "zh": "注意", "ja": "メモ", "ko": "참고", "pt": "Nota", "ar": "ملاحظة"],
        "locAlertDeleteOldChats": ["en": "Delete old chats?", "ru": "Удалить старые чаты?", "es": "¿Eliminar chats antiguos?", "fr": "Supprimer les anciennes conversations ?", "de": "Alte Chats löschen?", "zh": "删除旧聊天？", "ja": "古いチャットを削除しますか？", "ko": "오래된 채팅을 삭제하시겠습니까?", "pt": "Eliminar conversas antigas?", "ar": "هل تريد حذف المحادثات القديمة؟"],
        "locAlertDeleteArchivedChats": ["en": "Delete archived chats?", "ru": "Удалить архивные чаты?", "es": "¿Eliminar chats archivados?", "fr": "Supprimer les conversations archivées ?", "de": "Archivierte Chats löschen?", "zh": "删除已归档的聊天？", "ja": "アーカイブ済みチャットを削除しますか？", "ko": "보관된 채팅을 삭제하시겠습니까?", "pt": "Eliminar conversas arquivadas?", "ar": "هل تريد حذف المحادثات المؤرشفة؟"],
        "locAlertDeleteProject": ["en": "Delete project permanently?", "ru": "Удалить проект навсегда?", "es": "¿Eliminar proyecto permanentemente?", "fr": "Supprimer le projet définitivement ?", "de": "Projekt dauerhaft löschen?", "zh": "永久删除项目？", "ja": "プロジェクトを完全に削除しますか？", "ko": "プロジェクト를 영구적으로 삭제하시겠습니까?", "pt": "Eliminar proyecto permanentemente?", "ar": "هل تريد حذف المشروع نهائيًا؟"],
        "locFindNewPath": ["en": "Find new path…", "ru": "Найти новый путь…", "es": "Encontrar nueva ruta…", "fr": "Trouver un nouveau chemin…", "de": "Neuen Pfad finden…", "zh": "查找新路径…", "ja": "新しいパスを検索…", "ko": "새 경로 찾기…", "pt": "Encontrar novo caminho…", "ar": "العثور على مسار جديد…"],
        "locDeleteRecord": ["en": "Delete record (requires typing its name)", "ru": "Удалить запись (нужно ввести её имя)", "es": "Eliminar registro (requiere escribir su nombre)", "fr": "Supprimer l'enregistrement (nécessite de taper son nom)", "de": "Datensatz löschen (erfordert die Eingabe seines Namens)", "zh": "删除记录（需要输入其名称）", "ja": "レコードを削除（名前の入力が必要）", "ko": "레코드 삭제(이름 입력 필요)", "pt": "Eliminar registo (requer escrever o seu nome)", "ar": "حذف السجل (يتطلب كتابة اسمه)"],
        "locDeleteProjectHelp": ["en": "Delete project (requires typing its name)", "ru": "Удалить проект (нужно ввести его имя)", "es": "Eliminar proyecto (requiere escribir su nombre)", "fr": "Supprimer le projet (nécessite de taper son nom)", "de": "Projekt löschen (erfordert die Eingabe seines Namens)", "zh": "删除项目（需要输入其名称）", "ja": "プロジェクトを削除（名前の入力が必要）", "ko": "프로젝트 삭제(이름 입력 필요)", "pt": "Eliminar projeto (requer escrever o seu nome)", "ar": "حذف المشروع (يتطلب كتابة اسمه)"],
        "locLast7Days": ["en": "Last 7 days", "ru": "Последние 7 дней", "es": "Últimos 7 días", "fr": "7 derniers jours", "de": "Letzte 7 Tage", "zh": "最近 7 天", "ja": "過去7日間", "ko": "최근 7일", "pt": "Últimos 7 dias", "ar": "آخر 7 أيام"],
        "locLast30Days": ["en": "Last 30 days", "ru": "Последние 30 дней", "es": "Últimos 30 días", "fr": "30 derniers jours", "de": "Letzte 30 Tage", "zh": "最近 30 天", "ja": "過去30日間", "ko": "최근 30일", "pt": "Últimos 30 dias", "ar": "آخر 30 يومًا"],
        "locGitHubLight": ["en": "GitHub Light", "ru": "GitHub Light", "es": "GitHub Light", "fr": "GitHub Light", "de": "GitHub Light", "zh": "GitHub Light", "ja": "GitHub Light", "ko": "GitHub Light", "pt": "GitHub Light", "ar": "GitHub Light"],
        "locGitHubDark": ["en": "GitHub Dark", "ru": "GitHub Dark", "es": "GitHub Dark", "fr": "GitHub Dark", "de": "GitHub Dark", "zh": "GitHub Dark", "ja": "GitHub Dark", "ko": "GitHub Dark", "pt": "GitHub Dark", "ar": "GitHub Dark"],
        "locOneLight": ["en": "One Light", "ru": "One Light", "es": "One Light", "fr": "One Light", "de": "One Light", "zh": "One Light", "ja": "One Light", "ko": "One Light", "pt": "One Light", "ar": "One Light"],
        "locOneDark": ["en": "One Dark", "ru": "One Dark", "es": "One Dark", "fr": "One Dark", "de": "One Dark", "zh": "One Dark", "ja": "One Dark", "ko": "One Dark", "pt": "One Dark", "ar": "One Dark"],
        "locSolarizedLight": ["en": "Solarized Light", "ru": "Solarized Light", "es": "Solarized Light", "fr": "Solarized Light", "de": "Solarized Light", "zh": "Solarized Light", "ja": "Solarized Light", "ko": "Solarized Light", "pt": "Solarized Light", "ar": "Solarized Light"],
        "locSolarizedDark": ["en": "Solarized Dark", "ru": "Solarized Dark", "es": "Solarized Dark", "fr": "Solarized Dark", "de": "Solarized Dark", "zh": "Solarized Dark", "ja": "Solarized Dark", "ko": "Solarized Dark", "pt": "Solarized Dark", "ar": "Solarized Dark"],
        "locDracula": ["en": "Dracula", "ru": "Dracula", "es": "Dracula", "fr": "Dracula", "de": "Dracula", "zh": "Dracula", "ja": "Dracula", "ko": "Dracula", "pt": "Dracula", "ar": "Dracula"],
        "locTypeToConfirm": ["en": "Type \"{0}\" to confirm", "ru": "Введите \"{0}\" для подтверждения", "es": "Escriba \"{0}\" para confirmar", "fr": "Tapez \"{0}\" pour confirmer", "de": "Geben Sie \"{0}\" ein zum Bestätigen", "zh": "输入 \"{0}\" 以确认", "ja": "確認するには\"{0}\"と入力", "ko": "확인하려면 \"{0}\" 입력", "pt": "Escreva \"{0}\" para confirmar", "ar": "اكتب \"{0}\" للتأكيد"],
        "locConfirmAndAdd1": ["en": "Confirm and Add", "ru": "Подтвердить и добавить", "es": "Confirmar y añadir", "fr": "Confirmer et ajouter", "de": "Bestätigen und hinzufügen", "zh": "确认并添加", "ja": "確認して追加", "ko": "확인 및 추가", "pt": "Confirmar e adicionar", "ar": "تأكيد وإضافة"],
        "locCancel": ["en": "Cancel", "ru": "Отмена", "es": "Cancelar", "fr": "Annuler", "de": "Abbrechen", "zh": "取消", "ja": "キャンセル", "ko": "취소", "pt": "Cancelar", "ar": "إلغاء"],
        "locDelete": ["en": "Delete", "ru": "Удалить", "es": "Eliminar", "fr": "Supprimer", "de": "Löschen", "zh": "删除", "ja": "削除", "ko": "삭제", "pt": "Eliminar", "ar": "حذف"],
        "locResetButton": ["en": "Reset", "ru": "Сбросить", "es": "Restablecer", "fr": "Réinitialiser", "de": "Zurücksetzen", "zh": "重置", "ja": "リセット", "ko": "재설정", "pt": "Repor", "ar": "إعادة تعيين"],
        "locAlertDeleteMCPMessage": ["en": "This removes \"{0}\" from {1} and the registry. This cannot be undone.", "ru": "Это удалит \"{0}\" из {1} и реестр. Это нельзя отменить.", "es": "Esto elimina \"{0}\" de {1} y el registro. Esta acción no se puede deshacer.", "fr": "Cela supprime \"{0}\" de {1} et du registre. Cette action est irréversible.", "de": "Dies entfernt \"{0}\" aus {1} und der Registrierung. Dies kann nicht rückgängig gemacht werden.", "zh": "这将从 {1} 和注册表中移除 \"{0}\"。此操作无法撤销。", "ja": "これは {1} とレジストリから \"{0}\" を削除します。この操作は元に戻せません。", "ko": "{1} 및 레지스트리에서 \"{0}\"을(를) 제거합니다. 이 작업은 되돌릴 수 없습니다.", "pt": "Isto remove \"{0}\" de {1} e do registo. Esta ação não pode ser anulada.", "ar": "يؤدي هذا إلى إزالة \"{0}\" من {1} والسجل. لا يمكن التراجع عن هذا الإجراء."],
        "locAlertDeleteSkillMessage": ["en": "This deletes \"{0}\" from {1}/ and its registry entry. This cannot be undone.", "ru": "Это удалит \"{0}\" из {1}/ и запись в реестре. Это нельзя отменить.", "es": "Esto elimina \"{0}\" de {1}/ y su entrada de registro. Esta acción no se puede deshacer.", "fr": "Cela supprime \"{0}\" de {1}/ et son entrée de registre. Cette action est irréversible.", "de": "Dies löscht \"{0}\" aus {1}/ und den Registrierungseintrag. Dies kann nicht rückgängig gemacht werden.", "zh": "这将从 {1}/ 及其注册表项中删除 \"{0}\"。此操作无法撤销。", "ja": "これは {1}/ とそのレジストリエントリから \"{0}\" を削除します。この操作は元に戻せません。", "ko": "{1}/ 및 해당 레코드에서 \"{0}\"을(를) 삭제합니다. 이 작업은 되돌릴 수 없습니다.", "pt": "Isto elimina \"{0}\" de {1}/ e a sua entrada de registo. Esta ação não pode ser anulada.", "ar": "يؤدي هذا إلى حذف \"{0}\" من {1}/ وسجله. لا يمكن التراجع عن هذا الإجراء."],
        "locDeleteChatsConfirmMessage": ["en": "This will permanently delete all chats older than %d days, including their messages. This action cannot be undone.", "ru": "Это навсегда удалит все чаты старше %d дней со всеми сообщениями. Действие нельзя отменить.", "es": "Esto eliminará permanentemente todos los chats anteriores a %d días, incluidos sus mensajes. Esta acción no se puede deshacer.", "fr": "Cela supprimera définitivement toutes les conversations de plus de %d jours, y compris leurs messages. Cette action est irréversible.", "de": "Dies löscht dauerhaft alle Chats, die älter als %d Tage sind, einschließlich ihrer Nachrichten. Diese Aktion kann nicht rückgängig gemacht werden.", "zh": "这将永久删除所有早于 %d 天的聊天及其消息。此操作无法撤销。", "ja": "%d日より古いすべてのチャット（メッセージ含む）が完全に削除されます。この操作は元に戻せません。", "ko": "%d일보다 오래된 모든 채팅(메시지 포함)이 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.", "pt": "Isto eliminará permanentemente todas as conversas com mais de %d dias, incluindo as suas mensagens. Esta ação não pode ser anulada.", "ar": "سيؤدي هذا إلى حذف جميع المحادثات الأقدم من %d يومًا بشكل دائم، بما في ذلك رسائلها. لا يمكن التراجع عن هذا الإجراء."],
        "locInstalledCount": ["en": "Installed {0}", "ru": "Установлено {0}", "es": "Instalados {0}", "fr": "Installés {0}", "de": "Installiert {0}", "zh": "已安装 {0}", "ja": "インストール済み {0}", "ko": "설치됨 {0}", "pt": "Instalados {0}", "ar": "مثبت {0}"],
        "locArchiveNow": ["en": "Archive now", "ru": "Архивировать сейчас", "es": "Archivar ahora", "fr": "Archiver maintenant", "de": "Jetzt archivieren", "zh": "立即归档", "ja": "今すぐアーカイブ", "ko": "지금 보관", "pt": "Arquivar agora", "ar": "أرشفة الآن"],
        "locArchiveInactiveDays": ["en": "Archive inactive > {0} days", "ru": "Архивировать неактивные > {0} дней", "es": "Archivar inactivos > {0} días", "fr": "Archiver les inactifs > {0} jours", "de": "Inaktive archivieren > {0} Tage", "zh": "归档不活跃 > {0} 天", "ja": "非アクティブをアーカイブ > {0}日", "ko": "비활성 보관 > {0}일", "pt": "Arquivar inativos > {0} dias", "ar": "أرشفة غير النشطة > {0} أيام"],
        "locArchiveInactive": ["en": "Archive inactive", "ru": "Архивировать неактивные", "es": "Archivar inactivos", "fr": "Archiver les inactifs", "de": "Inaktive archivieren", "zh": "归档不活跃", "ja": "非アクティブをアーカイブ", "ko": "비활성 보관", "pt": "Arquivar inativos", "ar": "أرشفة غير النشطة"],
        "locBulkArchiveHelp": ["en": "Bulk-archive projects not opened in the selected number of days", "ru": "Массовая архивация проектов, не открытых в течение выбранного числа дней", "es": "Archivar proyectos en masa no abiertos en el número de días seleccionado", "fr": "Archiver en masse les projets non ouverts dans le nombre de jours sélectionné", "de": "Massenarchivierung von Projekten, die nicht in der ausgewählten Anzahl von Tagen geöffnet wurden", "zh": "批量归档在选定天数内未打开的项目", "ja": "選択した日数以内に開かれていないプロジェクトを一括アーカイブ", "ko": "선택한 일수 동안 열리지 않은 프로젝트 일괄 보관", "pt": "Arquivar projetos em massa não abertos no número de dias selecionado", "ar": "أرشفة المشاريع التي لم يتم فتحها في العدد المحدد من الأيام"],
        "locClearAppCache": ["en": "Clear app cache?", "ru": "Очистить кеш приложения?", "es": "¿Borrar caché de la aplicación?", "fr": "Vider le cache de l'application ?", "de": "App-Cache leeren?", "zh": "清除应用缓存？", "ja": "アプリキャッシュをクリアしますか？", "ko": "앱 캐시를 지우시겠습니까?", "pt": "Limpar cache da aplicação?", "ar": "هل تريد مسح ذاكرة التخزين المؤقت للتطبيق؟"],
        "locQuotaWarning": ["en": "Total project databases use {0}, above the {1} threshold. Archiving inactive projects would free {2}.", "ru": "Базы данных проектов используют {0}, что выше порога {1}. Архивация неактивных проектов освободит {2}.", "es": "Las bases de datos de proyectos usan {0}, por encima del umbral de {1}. Archivar proyectos inactivos liberaría {2}.", "fr": "Les bases de données de projets utilisent {0}, au-dessus du seuil de {1}. Archiver les projets inactifs libérerait {2}.", "de": "Projektdatenbanken verwenden {0}, oberhalb des Schwellenwerts von {1}. Die Archivierung inaktiver Projekte würde {2} freigeben.", "zh": "项目数据库使用 {0}，超过 {1} 阈值。归档不活跃项目将释放 {2}。", "ja": "プロジェクトデータベースは{0}を使用し、{1}のしきい値を超えています。非アクティブなプロジェクトをアーカイブすると{2}が解放されます。", "ko": "프로젝트 데이터베이스가 {0}을(를) 사용하여 {1} 임계값을 초과합니다. 비활성 프로젝트를 보관하면 {2}이(가) 해제됩니다.", "pt": "As bases de dados de projetos usam {0}, acima do limite de {1}. Arquivar projetos inativos libertaria {2}.", "ar": "تستخدم قواعد بيانات المشاريع {0}، أعلى من الحد {1}. تؤدي أرشفة المشاريع غير النشطة إلى تحرير {2}."],
        "locFindNewPath2": ["en": "Find new path…", "ru": "Найти новый путь…", "es": "Encontrar nueva ruta…", "fr": "Trouver un nouveau chemin…", "de": "Neuen Pfad finden…", "zh": "查找新路径…", "ja": "新しいパスを検索…", "ko": "새 경로 찾기…", "pt": "Encontrar novo caminho…", "ar": "العثور على مسار جديد…"],
        "locRelink": ["en": "Relink", "ru": "Перепривязать", "es": "Revincular", "fr": "Relier", "de": "Neu verknüpfen", "zh": "重新链接", "ja": "再リンク", "ko": "다시 연결", "pt": "Vincular novamente", "ar": "إعادة ربط"],
        "locFindProjectFolder": ["en": "Find the project folder at its new location", "ru": "Найдите папку проекта в новом месте", "es": "Encuentre la carpeta del proyecto en su nueva ubicación", "fr": "Trouvez le dossier du projet à son nouvel emplacement", "de": "Finden Sie den Projektordner an seinem neuen Standort", "zh": "在新位置查找项目文件夹", "ja": "新しい場所でプロジェクトフォルダを探す", "ko": "새 위치에서 프로젝트 폴더 찾기", "pt": "Encontre a pasta do projeto no seu novo local", "ar": "العثور على مجلد المشروع في موقعه الجديد"],
        "locExportBackup": ["en": "Export backup", "ru": "Экспорт резервной копии", "es": "Exportar copia de seguridad", "fr": "Exporter la sauvegarde", "de": "Sicherung exportieren", "zh": "导出备份", "ja": "バックアップをエクスポート", "ko": "백업 내보내기", "pt": "Exportar cópia de segurança", "ar": "تصدير النسخة الاحتياطية"],
        "locRestoreBackup": ["en": "Restore backup", "ru": "Восстановить резервную копию", "es": "Restaurar copia de seguridad", "fr": "Restaurer la sauvegarde", "de": "Sicherung wiederherstellen", "zh": "恢复备份", "ja": "バックアップを復元", "ko": "백업 복원", "pt": "Restaurar cópia de segurança", "ar": "استعادة النسخة الاحتياطية"],
        "locExportBackupPrompt": ["en": "Export backup", "ru": "Экспорт резервной копии", "es": "Exportar copia de seguridad", "fr": "Exporter la sauvegarde", "de": "Sicherung exportieren", "zh": "导出备份", "ja": "バックアップをエクスポート", "ko": "백업 내보내기", "pt": "Exportar cópia de segurança", "ar": "تصدير النسخة الاحتياطية"],
        "locRestoreBackupPrompt": ["en": "Restore backup", "ru": "Восстановить резервную копию", "es": "Restaurar copia de seguridad", "fr": "Restaurer la sauvegarde", "de": "Sicherung wiederherstellen", "zh": "恢复备份", "ja": "バックアップを復元", "ko": "백업 복원", "pt": "Restaurar cópia de segurança", "ar": "استعادة النسخة الاحتياطية"],
        "locDeleteProjectHelp2": ["en": "Delete project (requires typing its name)", "ru": "Удалить проект (нужно ввести его имя)", "es": "Eliminar proyecto (requiere escribir su nombre)", "fr": "Supprimer le projet (nécessite de taper son nom)", "de": "Projekt löschen (erfordert die Eingabe seines Namens)", "zh": "删除项目（需要输入其名称）", "ja": "プロジェクトを削除（名前の入力が必要）", "ko": "프로젝트 삭제(이름 입력 필요)", "pt": "Eliminar projeto (requer escrever o seu nome)", "ar": "حذف المشروع (يتطلب كتابة اسمه)"],
        "locCompressProjectHelp": ["en": "Compress this project's database (VACUUM)", "ru": "Сжать базу данных этого проекта (VACUUM)", "es": "Comprimir la base de datos de este proyecto (VACUUM)", "fr": "Compresser la base de données de ce projet (VACUUM)", "de": "Datenbank dieses Projekts komprimieren (VACUUM)", "zh": "压缩此项目的数据库 (VACUUM)", "ja": "このプロジェクトのデータベースを圧縮 (VACUUM)", "ko": "이 프로젝트의 데이터베이스 압축(VACUUM)", "pt": "Comprimir a base de dados deste projeto (VACUUM)", "ar": "ضغط قاعدة بيانات هذا المشروع (VACUUM)"],
        "locExportBackupHelp": ["en": "Export this project's database + snapshots as a .zip backup", "ru": "Экспорт базы данных этого проекта + снимков как .zip резервную копию", "es": "Exportar base de datos de este proyecto + instantáneas como copia de seguridad .zip", "fr": "Exporter la base de données de ce projet + les instantanés en sauvegarde .zip", "de": "Datenbank dieses Projekts + Schnappschüsse als .zip-Sicherung exportieren", "zh": "导出此项目的数据库 + 快照为 .zip 备份", "ja": "このプロジェクトのデータベース+スナップショットを.zipバックアップとしてエクスポート", "ko": "이 프로젝트의 데이터베이스 + 스냅샷을 .zip 백업으로 내보내기", "pt": "Exportar base de dados deste projeto + snapshots como cópia de segurança .zip", "ar": "تصدير قاعدة بيانات هذا المشروع + اللقطات كنسخة احتياطية .zip"],
        "locRestoreBackupHelp": ["en": "Restore this project's database + snapshots from a .zip backup", "ru": "Восстановить базу данных этого проекта + снимки из .zip резервной копии", "es": "Restaurar base de datos de este proyecto + instantáneas desde copia de seguridad .zip", "fr": "Restaurer la base de données de ce projet + les instantanés depuis une sauvegarde .zip", "de": "Datenbank dieses Projekts + Schnappschüsse aus einer .zip-Sicherung wiederherstellen", "zh": "从 .zip 备份恢复此项目的数据库 + 快照", "ja": "このプロジェクトのデータベース+スナップショットを.zipバックアップから復元", "ko": "이 프로젝트의 데이터베이스 + 스냅샷을 .zip 백업에서 복원", "pt": "Restaurar base de dados deste projeto + snapshots de uma cópia de segurança .zip", "ar": "استعادة قاعدة بيانات هذا المشروع + اللقطات من نسخة احتياطية .zip"],
        "locNone": ["en": "None", "ru": "Нет", "es": "Ninguno", "fr": "Aucun", "de": "Keine", "zh": "无", "ja": "なし", "ko": "없음", "pt": "Nenhum", "ar": "لا شيء"],
        "locParamContext": ["en": "Context", "ru": "Контекст", "es": "Contexto", "fr": "Contexte", "de": "Kontext", "zh": "上下文", "ja": "コンテキスト", "ko": "컨텍스트", "pt": "Contexto", "ar": "السياق"],
        "locParamOutput": ["en": "Output", "ru": "Выход", "es": "Salida", "fr": "Sortie", "de": "Ausgabe", "zh": "输出", "ja": "出力", "ko": "출력", "pt": "Saída", "ar": "الإخراج"],
        "locParamReasoning": ["en": "Reasoning", "ru": "Рассуждение", "es": "Razonamiento", "fr": "Raisonnement", "de": "Argumentation", "zh": "推理", "ja": "推論", "ko": "추론", "pt": "Raciocínio", "ar": "الاستدلال"],
        "locParamTools": ["en": "Tools", "ru": "Инструменты", "es": "Herramientas", "fr": "Outils", "de": "Werkzeuge", "zh": "工具", "ja": "ツール", "ko": "도구", "pt": "Ferramentas", "ar": "الأدوات"],
        "locParamPlan": ["en": "Plan", "ru": "План", "es": "Plan", "fr": "Plan", "de": "Plan", "zh": "计划", "ja": "プラン", "ko": "계획", "pt": "Plano", "ar": "الخطة"],
        "locParamCost": ["en": "Cost", "ru": "Стоимость", "es": "Costo", "fr": "Coût", "de": "Kosten", "zh": "费用", "ja": "コスト", "ko": "비용", "pt": "Custo", "ar": "التكلفة"],
        "locParamVariants": ["en": "Variants", "ru": "Варианты", "es": "Variantes", "fr": "Variantes", "de": "Varianten", "zh": "变体", "ja": "バリアント", "ko": "변형", "pt": "Variantes", "ar": "المتغيرات"],
        "locParamProvider": ["en": "Provider", "ru": "Провайдер", "es": "Proveedor", "fr": "Fournisseur", "de": "Anbieter", "zh": "提供商", "ja": "プロバイダー", "ko": "공급자", "pt": "Provedor", "ar": "المزود"],
        "locParamContextLength": ["en": "Context Length", "ru": "Длина контекста", "es": "Longitud de contexto", "fr": "Longueur du contexte", "de": "Kontextlänge", "zh": "上下文长度", "ja": "コンテキスト長", "ko": "컨텍스트 길이", "pt": "Comprimento do contexto", "ar": "طول السياق"],
        "locParamPlanMode": ["en": "Plan Mode", "ru": "Режим плана", "es": "Modo plan", "fr": "Mode plan", "de": "Planmodus", "zh": "计划模式", "ja": "プラン模态", "ko": "계획 모드", "pt": "Modo plano", "ar": "وضع الخطة"],
        "locSelectProviderToBrowseModels": ["en": "Select a provider to browse its models.", "ru": "Выберите провайдера для просмотра его моделей.", "es": "Seleccione un proveedor para explorar sus modelos.", "fr": "Sélectionnez un fournisseur pour parcourir ses modèles.", "de": "Wählen Sie einen Anbieter, um seine Modelle zu durchsuchen.", "zh": "选择提供商以浏览其模型。", "ja": "プロバイダーを選択してモデルを閲覧してください。", "ko": "모델을 탐색할 공급자를 선택하세요.", "pt": "Selecione um provedor para explorar os seus modelos.", "ar": "اختر مزودًا لاستعراض نماذجه."],
        "locStartLocalAgentOrCheck": ["en": "Start the local agent or check the provider connection to load models.", "ru": "Запустите локального агента или проверьте подключение провайдера для загрузки моделей.", "es": "Inicie el agente local o compruebe la conexión del proveedor para cargar modelos.", "fr": "Démarrez l'agent local ou vérifiez la connexion du fournisseur pour charger les modèles.", "de": "Starten Sie den lokalen Agenten oder überprüfen Sie die Anbieterverbindung, um Modelle zu laden.", "zh": "启动本地代理或检查提供商连接以加载模型。", "ja": "ローカルエージェントを起動するか、プロバイダーの接続を確認してモデルを読み込みます。", "ko": "로컬 에이전트를 시작하거나 공급자 연결을 확인하여 모델을 로드하세요.", "pt": "Inicie o agente local ou verifique a ligação do provedor para carregar modelos.", "ar": "ابدأ الوكيل المحلي أو تحقق من اتصال المزود لتحميل النماذج."],
        "locArchive": ["en": "Archive", "ru": "Архивировать", "es": "Archivar", "fr": "Archiver", "de": "Archivieren", "zh": "归档", "ja": "アーカイブ", "ko": "보관", "pt": "Arquivar", "ar": "أرشفة"],
        "locRestore": ["en": "Restore", "ru": "Восстановить", "es": "Restaurar", "fr": "Restaurer", "de": "Wiederherstellen", "zh": "恢复", "ja": "復元", "ko": "복원", "pt": "Restaurar", "ar": "استعادة"],
        "locNoUserCommands": ["en": "No user commands", "ru": "Нет пользовательских команд", "es": "Sin comandos de usuario", "fr": "Aucune commande utilisateur", "de": "Keine Benutzerbefehle", "zh": "没有用户命令", "ja": "ユーザーコマンドはありません", "ko": "사용자 명령이 없습니다", "pt": "Sem comandos do utilizador", "ar": "لا توجد أوامر مستخدم"],
        "locNoPluginsInstalled": ["en": "No plugins installed", "ru": "Плагины не установлены", "es": "Sin plugins instalados", "fr": "Aucun plugin installé", "de": "Keine Plugins installiert", "zh": "未安装插件", "ja": "プラグインがインストールされていません", "ko": "설치된 플러그인이 없습니다", "pt": "Sem plugins instalados", "ar": "لا توجد إضافات مثبتة"],
        "locNoSkillsInstalledYet": ["en": "No skills installed yet", "ru": "Навыки пока не установлены", "es": "Aún no hay habilidades instaladas", "fr": "Aucune compétence installée pour l'instant", "de": "Noch keine Fähigkeiten installiert", "zh": "尚未安装技能", "ja": "スキルはまだインストールされていません", "ko": "아직 설치된 스킬이 없습니다", "pt": "Ainda não há competências instaladas", "ar": "لا توجد مهارات مثبتة بعد"],
        "locNoMCPServersConfigured": ["en": "No MCP servers configured", "ru": "Серверы MCP не настроены", "es": "Sin servidores MCP configurados", "fr": "Aucun serveur MCP configuré", "de": "Keine MCP-Server konfiguriert", "zh": "未配置 MCP 服务器", "ja": "MCPサーバーが設定されていません", "ko": "구성된 MCP 서버가 없습니다", "pt": "Sem servidores MCP configurados", "ar": "لا توجد خوادم MCP مكوّنة"],

        "locCaptchaSolveNote": ["en": "Solve the captcha below to continue, then the agent resumes automatically.", "ru": "Решите капчу ниже, чтобы продолжить, затем агент возобновит работу автоматически.", "es": "Resuelve el captcha a continuación para continuar, luego el agente se reanuda automáticamente.", "fr": "Résolvez le captcha ci-dessous pour continuer, puis l'agent reprend automatiquement.", "de": "Lösen Sie das Captcha unten, um fortzufahren, dann setzt der Agent automatisch fort.", "zh": "请完成下方验证码以继续，之后代理将自动恢复。", "ja": "下のキャプチャを解決して続行すると、エージェントが自動的に再開します。", "ko": "아래 캡차를 해결한 후 계속하면 에이전트가 자동으로 재개됩니다.", "pt": "Resolva o captcha abaixo para continuar, então o agente retoma automaticamente.", "ar": "حل كلمة التحقق أدناه للمتابعة، ثم يستأنف الوكيل تلقائيًا."],
        "locWebSessionExpired": ["en": "Session expired — log in again to continue.", "ru": "Сессия истекла — войдите снова, чтобы продолжить.", "es": "Sesión expirada — inicia sesión de nuevo para continuar.", "fr": "Session expirée — connectez-vous à nouveau pour continuer.", "de": "Sitzung abgelaufen — melden Sie sich erneut an, um fortzufahren.", "zh": "会话已过期 — 请重新登录以继续。", "ja": "セッションの期限が切れました — 続行するにはもう一度ログインしてください。", "ko": "세션이 만료되었습니다 — 계속하려면 다시 로그인하세요.", "pt": "Sessão expirada — inicie sessão novamente para continuar.", "ar": "انتهت صلاحية الجلسة — سجل الدخول مرة أخرى للمتابعة."],
        "locWebSessionTooLong": ["en": "Conversation too long — starting a fresh session and carrying over context…", "ru": "Разговор слишком длинный — начинаю новую сессию и переношу контекст…", "es": "Conversación demasiado larga — iniciando una sesión nueva y transfiriendo el contexto…", "fr": "Conversation trop longue — démarrage d'une nouvelle session et transfert du contexte…", "de": "Konversation zu lang — neue Sitzung wird gestartet und Kontext übertragen…", "zh": "对话过长 — 正在开始新会话并保留上下文…", "ja": "会話が長すぎます — 新しいセッションを開始し、コンテキストを引き継ぎます…", "ko": "대화가 너무 깁니다 — 새 세션을 시작하고 컨텍스트를 전달합니다…", "pt": "Conversa muito longa — iniciando uma nova sessão e transferindo o contexto…", "ar": "المحادثة طويلة جدًا — بدء جلسة جديدة ونقل السياق…"],
        "locWebNewSessionStarted": ["en": "New session started; continuing.", "ru": "Новая сессия начата; продолжаю.", "es": "Nueva sesión iniciada; continuando.", "fr": "Nouvelle session démarrée ; continuation.", "de": "Neue Sitzung gestartet ; fortfahren.", "zh": "新会话已开始；继续。", "ja": "新しいセッションが開始されました。続行します。", "ko": "새 세션이 시작되었습니다. 계속합니다.", "pt": "Nova sessão iniciada; continuando.", "ar": "بدأت جلسة جديدة؛ المتابعة."],
        "locWebModelNote": ["en": "Model note: {0}", "ru": "Примечание модели: {0}", "es": "Nota del modelo: {0}", "fr": "Note du modèle : {0}", "de": "Modellhinweis: {0}", "zh": "模型提示：{0}", "ja": "モデルメモ: {0}", "ko": "모델 참고: {0}", "pt": "Nota do modelo: {0}", "ar": "ملاحظة النموذج: {0}"],
        "locWebEffortNote": ["en": "Effort note: {0}", "ru": "Примечание усилий: {0}", "es": "Nota de esfuerzo: {0}", "fr": "Note d'effort : {0}", "de": "Aufwandsnotiz: {0}", "zh": "思考强度提示：{0}", "ja": "労力メモ: {0}", "ko": "노력 참고: {0}", "pt": "Nota de esforço: {0}", "ar": "ملاحظة الجهد: {0}"],
        "locWebPromptSplit": ["en": "Large prompt sent in {0} parts.", "ru": "Большой промпт отправлен в {0} частях.", "es": "Prompt grande enviado en {0} partes.", "fr": "Grand prompt envoyé en {0} parties.", "de": "Großer Prompt in {0} Teilen gesendet.", "zh": "大提示已分为 {0} 部分发送。", "ja": "大きなプロンプトが{0}パートで送信されました。", "ko": "큰 프롬프트가{0}부분으로 전송되었습니다.", "pt": "Prompt grande enviado em {0} partes.", "ar": "تم إرسال المطالبة الكبيرة في {0} أجزاء."],
        "locWebToolCall": ["en": "↪ {0}({1})", "ru": "↪ {0}({1})", "es": "↪ {0}({1})", "fr": "↪ {0}({1})", "de": "↪ {0}({1})", "zh": "↪ {0}({1})", "ja": "↪ {0}({1})", "ko": "↪ {0}({1})", "pt": "↪ {0}({1})", "ar": "↪ {0}({1})"],
        "locWebToolResult": ["en": "✓ {0}", "ru": "✓ {0}", "es": "✓ {0}", "fr": "✓ {0}", "de": "✓ {0}", "zh": "✓ {0}", "ja": "✓ {0}", "ko": "✓ {0}", "pt": "✓ {0}", "ar": "✓ {0}"],
        "locWebIterationLimit": ["en": "Reached the tool-iteration limit for this turn.", "ru": "Достигнут предел итераций инструментов для этого хода.", "es": "Se alcanzó el límite de iteraciones de herramientas para este turno.", "fr": "Limite d'itérations d'outils atteinte pour ce tour.", "de": "Tool-Iterationslimit für diesen Zug erreicht.", "zh": "已达到本回合的工具迭代上限。", "ja": "このターンのツール反復制限に達しました。", "ko": "이 턴에 대한 도구 반복 제한에 도달했습니다.", "pt": "Atingiu o limite de iterações de ferramentas para esta jogada.", "ar": "تم الوصول إلى حد تكرار الأدوات لهذا الدور."],
        "locWebEmptyResponse": ["en": "The model returned an empty response.", "ru": "Модель вернула пустой ответ.", "es": "El modelo devolvió una respuesta vacía.", "fr": "Le modèle a renvoyé une réponse vide.", "de": "Das Modell hat eine leere Antwort zurückgegeben.", "zh": "模型返回了空响应。", "ja": "モデルが空の応答を返しました。", "ko": "모델이 빈 응답을 반환했습니다.", "pt": "O modelo devolveu uma resposta vazia.", "ar": "أعاد النموذج استجابة فارغة."],
        "locWebProviderError": ["en": "Web provider error: {0}", "ru": "Ошибка веб-провайдера: {0}", "es": "Error del proveedor web: {0}", "fr": "Erreur du fournisseur web : {0}", "de": "Web-Anbieterfehler: {0}", "zh": "Web 提供商错误：{0}", "ja": "Webプロバイダーエラー: {0}", "ko": "웹 공급자 오류: {0}", "pt": "Erro do fornecedor web: {0}", "ar": "خطأ مزود الويب: {0}"],
        "locWebModelInjectionFailed": ["en": "Could not set model: {0}", "ru": "Не удалось установить модель: {0}", "es": "No se pudo establecer el modelo: {0}", "fr": "Impossible de définir le modèle : {0}", "de": "Modell konnte nicht festgelegt werden: {0}", "zh": "无法设置模型：{0}", "ja": "モデルを設定できませんでした: {0}", "ko": "모델을 설정할 수 없습니다: {0}", "pt": "Não foi possível definir o modelo: {0}", "ar": "تعذر تعيين النموذج: {0}"],
        "locWebEffortNotFound": ["en": "Effort level '{0}' not found", "ru": "Уровень усилий '{0}' не найден", "es": "Nivel de esfuerzo '{0}' no encontrado", "fr": "Niveau d'effort '{0}' non trouvé", "de": "Aufwandsstufe '{0}' nicht gefunden", "zh": "未找到思考强度级别「{0}」", "ja": "労力レベル'{0}'が見つかりません", "ko": "노력 수준 '{0}'을(를) 찾을 수 없습니다", "pt": "Nível de esforço '{0}' não encontrado", "ar": "مستوى الجهد '{0}' غير موجود"],
        "locWebModelNotFound": ["en": "Model '{0}' not found", "ru": "Модель '{0}' не найдена", "es": "Modelo '{0}' no encontrado", "fr": "Modèle '{0}' non trouvé", "de": "Modell '{0}' nicht gefunden", "zh": "未找到模型「{0}」", "ja": "モデル'{0}'が見つかりません", "ko": "모델 '{0}'을(를) 찾을 수 없습니다", "pt": "Modelo '{0}' não encontrado", "ar": "النموذج '{0}' غير موجود"],
        "locWebModeNotFound": ["en": "Mode '{0}' not found", "ru": "Режим '{0}' не найден", "es": "Modо '{0}' no encontrado", "fr": "Mode '{0}' non trouvé", "de": "Modus '{0}' nicht gefunden", "zh": "未找到模式「{0}」", "ja": "モード'{0}'が見つかりません", "ko": "모드 '{0}'을(를) 찾을 수 없습니다", "pt": "Modo '{0}' não encontrado", "ar": "الوضع '{0}' غير موجود"],
        "locWebInputNotFound": ["en": "Chat input not found — page may need manual login.", "ru": "Поле ввода чата не найдено — странице может потребоваться ручной вход.", "es": "Entrada de chat no encontrada — la página puede necesitar inicio de sesión manual.", "fr": "Entrée de chat non trouvée — la page peut nécessiter une connexion manuelle.", "de": "Chateingabe nicht gefunden — die Seite muss möglicherweise manuell angemeldet werden.", "zh": "未找到聊天输入 — 页面可能需要手动登录。", "ja": "チャット入力が見つかりません — ページが手動ログインを必要とする場合があります。", "ko": "채팅 입력을 찾을 수 없습니다 — 페이지에서 수동 로그인이 필요할 수 있습니다.", "pt": "Entrada de chat não encontrada — a página pode precisar de início de sessão manual.", "ar": "لم يتم العثور على إدخال الدردشة — قد تحتاج الصفحة إلى تسجيل دخول يدوي."],
        "locWebCannotOpen": ["en": "Could not open {0}: {1}. Check that the site is reachable and you are logged in.", "ru": "Не удалось открыть {0}: {1}. Проверьте, что сайт доступен и вы вошли в систему.", "es": "No se pudo abrir {0}: {1}. Compruebe que el sitio es accesible y que ha iniciado sesión.", "fr": "Impossible d'ouvrir {0} : {1}. Vérifiez que le site est accessible et que vous êtes connecté.", "de": "Konnte {0} nicht öffnen: {1}. Überprüfen Sie, ob die Seite erreichbar und Sie angemeldet sind.", "zh": "无法打开 {0}：{1}。请检查网站是否可达以及您是否已登录。", "ja": "{0}を開けませんでした: {1}。サイトにアクセス可能でログインしていることを確認してください。", "ko": "{0}을(를) 열 수 없습니다: {1}. 사이트에 접근할 수 있고 로그인했는지 확인하세요.", "pt": "Não foi possível abrir {0}: {1}. Verifique se o site está acessível e se tem sessão iniciada.", "ar": "تعذر فتح {0}: {1}. تحقق من إمكانية الوصول إلى الموقع وتسجيل الدخول."],
        "locWebRestoreSessionFailed": ["en": "Failed to restore the saved session: {0}", "ru": "Не удалось восстановить сохранённую сессию: {0}", "es": "No se pudo restaurar la sesión guardada: {0}", "fr": "Impossible de restaurer la session enregistrée : {0}", "de": "Gespeicherte Sitzung konnte nicht wiederhergestellt werden: {0}", "zh": "无法恢复已保存的会话：{0}", "ja": "保存されたセッションを復元できませんでした: {0}", "ko": "저장된 세션을 복원할 수 없습니다: {0}", "pt": "Não foi possível restaurar a sessão guardada: {0}", "ar": "فشل استعادة الجلسة المحفوظة: {0}"],
        "locWebCannotReadImage": ["en": "Cannot read \"{0}\" (this model does not support image input)", "ru": "Не удаётся прочитать «{0}» (эта модель не поддерживает ввод изображений)", "es": "No se puede leer «{0}» (este modelo no admite entrada de imágenes)", "fr": "Impossible de lire « {0} » (ce modèle ne prend pas en charge l'entrée d'images)", "de": "Kann „{0}“ nicht lesen (dieses Modell unterstützt keine Bildeingabe)", "zh": "无法读取「{0}」（此模型不支持图像输入）", "ja": "「{0}」を読み取れません（このモデルは画像入力をサポートしていません）", "ko": "\"{0}\"(을)를 읽을 수 없습니다(이 모델은 이미지 입력을 지원하지 않음)", "pt": "Não é possível ler «{0}» (este modelo não suporta entrada de imagens)", "ar": "لا يمكن قراءة \"{0}\" (لا يدعم هذا النموذج إدخال الصور)"],
         "locEmptyInput": ["en": "Type a message or attach a file to send.", "ru": "Введите сообщение или прикрепите файл, чтобы отправить.", "es": "Escribe un mensaje o adjunta un archivo para enviar.", "fr": "Tapez un message ou joignез un fichier pour envoyer.", "de": "Geben Sie eine Nachricht ein oder hängen Sie eine Datei an, um zu senden.", "zh": "输入消息或附加文件以发送。", "ja": "メッセージを入力するか、ファイルを添付して送信してください。", "ko": "メシζを入力するか、ファイルを添付して送信してください。", "pt": "Escreva uma mensagem ou anexe um ficheiro para enviar.", "ar": "اكتب رسالةً أو أرفق ملفًا للإرسال."],
        "locModeSwitched": ["en": "Mode switched", "ru": "Режим изменён", "es": "Modo cambiado", "fr": "Mode changé", "de": "Modus geändert", "zh": "模式已切换", "ja": "モードが変更されました", "ko": "모드 변경됨", "pt": "Modo alterado", "ar": "تم تغيير الوضع"],
        "locPlanNotSupported": ["en": "Plan mode not supported by this model, switched to Build", "ru": "Режим плана не поддерживается, переключено на Кодинг", "es": "Modo plan no compatible, cambiado a Construir", "fr": "Mode plan non pris en charge, passé en Build", "de": "Plan-Modus nicht unterstützt, auf Build umgeschaltet", "zh": "此模型不支持计划模式，已切换到构建", "ja": "このモデルはプラン モードをサポートしていません、ビルドに切り替えました", "ko": "이 모델은 플랜 모드를 지원하지 않아 빌드로 전환했습니다", "pt": "Modo plano não suportado, alterado para Construir", "ar": "وضع الخطة غير مدعوم بواسطة هذا النموذج، تم التبديل إلى البناء"],
        "locSearchLanguage": ["en": "Search language", "ru": "Поиск языка", "es": "Buscar idioma", "fr": "Rechercher une langue", "de": "Sprache suchen", "zh": "搜索语言", "ja": "言語を検索", "ko": "언어 검색", "pt": "Pesquisar idioma", "ar": "البحث عن لغة"],
        "locOtherAnswer": ["en": "Other answer", "ru": "Другой ответ", "es": "Otra respuesta", "fr": "Autre réponse", "de": "Andere Antwort", "zh": "其他答案", "ja": "その他の回答", "ko": "기타 답변", "pt": "Outra resposta", "ar": "إجابة أخرى"],
        "locCaptchaVerification": ["en": "Captcha verification", "ru": "Проверка captcha", "es": "Verificación de captcha", "fr": "Vérification captcha", "de": "Captcha-Prüfung", "zh": "验证码验证", "ja": "Captcha 検証", "ko": "Captcha 확인", "pt": "Verificação de captcha", "ar": "التحقق من CAPTCHA"],
        "locCaptchaInstruction": ["en": "Complete the challenge in this live browser page. The agent will resume automatically after the page becomes ready.", "ru": "Пройдите проверку на этой странице браузера. Агент автоматически продолжит работу, когда страница будет готова.", "es": "Completa el desafío en esta página del navegador. El agente continuará automáticamente cuando la página esté lista.", "fr": "Terminez le défi sur cette page du navigateur. L’agent reprendra automatiquement lorsque la page sera prête.", "de": "Schließen Sie die Prüfung auf dieser Browserseite ab. Der Agent setzt automatisch fort, sobald die Seite bereit ist.", "zh": "请在此浏览器页面完成验证。页面准备就绪后，代理将自动继续。", "ja": "このブラウザページでチャレンジを完了してください。ページの準備ができるとエージェントが自動的に再開します。", "ko": "이 브라우저 페이지에서 인증을 완료하세요. 페이지가 준비되면 에이전트가 자동으로 계속합니다.", "pt": "Conclua o desafio nesta página do navegador. O agente continuará automaticamente quando a página estiver pronta.", "ar": "أكمل التحدي في صفحة المتصفح المباشرة. سيستأنف الوكيل تلقائيًا بعد جاهزية الصفحة."],
        "locChooseSavedWebLogin": ["en": "Choose saved web login", "ru": "Выбрать сохранённый веб-вход", "es": "Elegir inicio de sesión web guardado", "fr": "Choisir une connexion web enregistrée", "de": "Gespeicherten Web-Login wählen", "zh": "选择已保存的网页登录", "ja": "保存済みウェブログインを選択", "ko": "저장된 웹 로그인 선택", "pt": "Escolher início de sessão web guardado", "ar": "اختيار تسجيل الدخول المحفوظ للويب"],
        "locChangeLoginSession": ["en": "Change login / capture another web session", "ru": "Изменить вход / сохранить другую веб-сессию", "es": "Cambiar inicio de sesión / capturar otra sesión web", "fr": "Changer de connexion / capturer une autre session web", "de": "Login ändern / weitere Websitzung erfassen", "zh": "更改登录/捕获另一个网页会话", "ja": "ログインを変更 / 別のウェブセッションを取得", "ko": "로그인 변경 / 다른 웹 세션 캡처", "pt": "Alterar início de sessão / capturar outra sessão web", "ar": "تغيير تسجيل الدخول / التقاط جلسة ويب أخرى"],
        "locDetectedCount": ["en": "%d detected", "ru": "Обнаружено: %d", "es": "%d detectados", "fr": "%d détectés", "de": "%d erkannt", "zh": "已检测 %d 个", "ja": "%d 件検出", "ko": "%d개 감지됨", "pt": "%d detetados", "ar": "تم اكتشاف %d"],
        "locDetectionFailed": ["en": "Detection failed", "ru": "Не удалось определить", "es": "La detección falló", "fr": "Échec de la détection", "de": "Erkennung fehlgeschlagen", "zh": "检测失败", "ja": "検出に失敗しました", "ko": "감지 실패", "pt": "Falha na deteção", "ar": "فشل الاكتشاف"],
        "locDetectModels": ["en": "Detect models", "ru": "Определить модели", "es": "Detectar modelos", "fr": "Détecter les modèles", "de": "Modelle erkennen", "zh": "检测模型", "ja": "モデルを検出", "ko": "모델 감지", "pt": "Detetar modelos", "ar": "اكتشاف النماذج"],
        "locDetectModelsHelp": ["en": "Detect models from web UI", "ru": "Определить модели из веб-интерфейса", "es": "Detectar modelos desde la interfaz web", "fr": "Détecter les modèles depuis l’interface web", "de": "Modelle aus der Weboberfläche erkennen", "zh": "从网页界面检测模型", "ja": "ウェブUIからモデルを検出", "ko": "웹 UI에서 모델 감지", "pt": "Detetar modelos na interface web", "ar": "اكتشاف النماذج من واجهة الويب"],
        "locRefreshEffortHelp": ["en": "Refresh per-model effort and parameter profiles from web UI", "ru": "Обновить усилие и параметры каждой модели из веб-интерфейса", "es": "Actualizar el esfuerzo y los parámetros de cada modelo desde la interfaz web", "fr": "Actualiser l’effort et les paramètres de chaque modèle depuis l’interface web", "de": "Aufwand und Parameterprofile je Modell aus der Weboberfläche aktualisieren", "zh": "从网页界面刷新每个模型的推理强度和参数", "ja": "ウェブUIからモデルごとの推論レベルとパラメータを更新", "ko": "웹 UI에서 모델별 추론 수준과 매개변수 프로필 새로 고침", "pt": "Atualizar o esforço e os parâmetros de cada modelo na interface web", "ar": "تحديث جهد ومعلمات كل نموذج من واجهة الويب"],
        "locRemoveWebProvider": ["en": "Remove this web provider and its saved session", "ru": "Удалить этого веб-провайдера и сохранённую сессию", "es": "Eliminar este proveedor web y su sesión guardada", "fr": "Supprimer ce fournisseur web et sa session enregistrée", "de": "Diesen Webanbieter und seine gespeicherte Sitzung entfernen", "zh": "删除此网页提供商及其保存的会话", "ja": "このウェブプロバイダーと保存済みセッションを削除", "ko": "이 웹 공급자와 저장된 세션 제거", "pt": "Remover este fornecedor web e a sessão guardada", "ar": "إزالة موفر الويب هذا وجلسته المحفوظة"],
        "locRemoveWebProviderConfirm": ["en": "Remove %@?", "ru": "Удалить %@?", "es": "¿Eliminar %@?", "fr": "Supprimer %@ ?", "de": "%@ entfernen?", "zh": "要删除 %@ 吗？", "ja": "%@を削除しますか？", "ko": "%@을(를) 제거하시겠습니까?", "pt": "Remover %@?", "ar": "هل تريد إزالة %@؟"],
        "locSavedSessionDeleted": ["en": "The saved browser session and provider settings will be deleted.", "ru": "Сохранённая сессия браузера и настройки провайдера будут удалены.", "es": "Se eliminarán la sesión del navegador guardada y los ajustes del proveedor.", "fr": "La session de navigateur enregistrée et les réglages du fournisseur seront supprimés.", "de": "Die gespeicherte Browsersitzung und Anbietereinstellungen werden gelöscht.", "zh": "已保存的浏览器会话和提供商设置将被删除。", "ja": "保存されたブラウザセッションとプロバイダー設定が削除されます。", "ko": "저장된 브라우저 세션과 공급자 설정이 삭제됩니다.", "pt": "A sessão do navegador guardada e as definições do fornecedor serão eliminadas.", "ar": "سيتم حذف جلسة المتصفح المحفوظة وإعدادات الموفر."],
        "locDetectedModelsCount": ["en": "Detected models · %d", "ru": "Обнаруженные модели · %d", "es": "Modelos detectados · %d", "fr": "Modèles détectés · %d", "de": "Erkannte Modelle · %d", "zh": "检测到的模型 · %d", "ja": "検出モデル · %d", "ko": "감지된 모델 · %d", "pt": "Modelos detetados · %d", "ar": "النماذج المكتشفة · %d"],
        "locDetectedModels": ["en": "Detected models", "ru": "Обнаруженные модели", "es": "Modelos detectados", "fr": "Modèles détectés", "de": "Erkannte Modelle", "zh": "检测到的模型", "ja": "検出モデル", "ko": "감지된 모델", "pt": "Modelos detetados", "ar": "النماذج المكتشفة"],
        "locHideDetectedModels": ["en": "Hide all detected models", "ru": "Скрыть все обнаруженные модели", "es": "Ocultar todos los modelos detectados", "fr": "Masquer tous les modèles détectés", "de": "Alle erkannten Modelle ausblenden", "zh": "隐藏所有检测到的模型", "ja": "検出したモデルをすべて隠す", "ko": "감지된 모든 모델 숨기기", "pt": "Ocultar todos os modelos detetados", "ar": "إخفاء جميع النماذج المكتشفة"],
        "locShowDetectedModels": ["en": "Show all detected models", "ru": "Показать все обнаруженные модели", "es": "Mostrar todos los modelos detectados", "fr": "Afficher tous les modèles détectés", "de": "Alle erkannten Modelle anzeigen", "zh": "显示所有检测到的模型", "ja": "検出したモデルをすべて表示", "ko": "감지된 모든 모델 표시", "pt": "Mostrar todos os modelos detetados", "ar": "إظهار جميع النماذج المكتشفة"],
        "locRemoveUnavailableDetection": ["en": "Remove this unavailable detection result", "ru": "Удалить этот недоступный результат определения", "es": "Eliminar este resultado de detección no disponible", "fr": "Supprimer ce résultat de détection indisponible", "de": "Dieses nicht verfügbare Erkennungsergebnis entfernen", "zh": "删除此不可用的检测结果", "ja": "利用できない検出結果を削除", "ko": "사용할 수 없는 감지 결과 제거", "pt": "Remover este resultado de deteção indisponível", "ar": "إزالة نتيجة الاكتشاف غير المتاحة"],
        "locEffort": ["en": "Effort", "ru": "Усилие", "es": "Esfuerzo", "fr": "Effort", "de": "Aufwand", "zh": "推理强度", "ja": "推論レベル", "ko": "추론 수준", "pt": "Esforço", "ar": "الجهد"],
        "locNoEffort": ["en": "No effort", "ru": "Без усилия", "es": "Sin esfuerzo", "fr": "Sans effort", "de": "Kein Aufwand", "zh": "无推推理强度", "ja": "推論レベルなし", "ko": "추론 수준 없음", "pt": "Sem esforço", "ar": "بدون جهد"],
        "locParams": ["en": "Params", "ru": "Параметры", "es": "Parámetros", "fr": "Paramètres", "de": "Parameter", "zh": "参数", "ja": "パラメータ", "ko": "매개변수", "pt": "Parâmetros", "ar": "المعلمات"],
        "locEffortNotDetected": ["en": "Effort: not detected", "ru": "Усилие: не определено", "es": "Esfuerzo: no detectado", "fr": "Effort : non détecté", "de": "Aufwand: nicht erkannt", "zh": "推理强度：未检测", "ja": "推論レベル：未検出", "ko": "추론 수준: 감지되지 않음", "pt": "Esforço: não detetado", "ar": "الجهد: لم يُكتشف"],
        "locSelectorAvailable": ["en": "· selector available", "ru": "· селектор доступен", "es": "· selector disponible", "fr": "· sélecteur disponible", "de": "· Selektor verfügbar", "zh": "· 选择器可用", "ja": "· セレクター利用可能", "ko": "· 선택기 사용 가능", "pt": "· seletor disponível", "ar": "· المحدد متاح"],
        "locInAppBrowser": ["en": "In-app browser", "ru": "Встроенный браузер", "es": "Navegador integrado", "fr": "Navigateur intégré", "de": "In-App-Browser", "zh": "内置浏览器", "ja": "アプリ内ブラウザ", "ko": "앱 내 브라우저", "pt": "Navegador integrado", "ar": "المتصفح المدمج"],
        "locBuiltInBrowserDetection": ["en": "Built-in browser detection", "ru": "Определение во встроенном браузере", "es": "Detección en el navegador integrado", "fr": "Détection dans le navigateur intégré", "de": "Erkennung im integrierten Browser", "zh": "内置浏览器检测", "ja": "内蔵ブラウザ検出", "ko": "내장 브라우저 감지", "pt": "Deteção no navegador integrado", "ar": "الاكتشاف في المتصفح المدمج"],
        "locBrowserDetectionHelp": ["en": "Choose how myCoder reads model names from the authenticated web page", "ru": "Выберите, как myCoder считывает названия моделей с авторизованной веб-страницы", "es": "Elige cómo myCoder lee los nombres de modelos de la página web autenticada", "fr": "Choisissez comment myCoder lit les noms de modèles sur la page web authentifiée", "de": "Wählen Sie, wie myCoder Modellnamen von der authentifizierten Webseite liest", "zh": "选择 myCoder 如何从已登录网页读取模型名称", "ja": "認証済みウェブページからMyCoderがモデル名を読む方法を選択", "ko": "MyCoder가 인증된 웹 페이지에서 모델 이름을 읽는 방법 선택", "pt": "Escolha como o myCoder lê os nomes dos modelos na página autenticada", "ar": "اختر كيفية قراءة myCoder لأسماء النماذج من صفحة الويب الموثقة"],
        "locFastDOMDetectionHelp": ["en": "Fast built-in DOM scraping; no AI request", "ru": "Быстрое чтение DOM; запрос к ИИ не выполняется", "es": "Lectura rápida del DOM; no se realiza ninguna solicitud de IA", "fr": "Lecture DOM rapide ; aucune requête IA", "de": "Schnelles DOM-Auslesen; keine KI-Anfrage", "zh": "快速读取 DOM；不会发送 AI 请求", "ja": "高速DOM読み取り。AIリクエストなし", "ko": "빠른 DOM 스크래핑, AI 요청 없음", "pt": "Leitura rápida do DOM; sem pedido de IA", "ar": "استخراج سريع من DOM؛ لا يوجد طلب ذكاء اصطناعي"],
        "locAskMyCoderAutoFree": ["en": "Ask OpenCode Zen", "ru": "Спросить OpenCode Zen", "es": "Preguntar a OpenCode Zen", "fr": "Interroger OpenCode Zen", "de": "OpenCode Zen fragen", "zh": "询问 OpenCode Zen", "ja": "OpenCode Zen に質問", "ko": "OpenCode Zen에 질문", "pt": "Perguntar ao OpenCode Zen", "ar": "اسأل OpenCode Zen"],
        "locAskMyCoderAutoFreeHelp": ["en": "Ask OpenCode Zen to read the visible page text and list model names", "ru": "Попросить OpenCode Zen прочитать видимый текст страницы и перечислить модели", "es": "Pide a OpenCode Zen que lea el texto visible y enumere los modelos", "fr": "Demander à OpenCode Zen de lire le texte visible et de lister les modèles", "de": "OpenCode Zen soll den sichtbaren Seitentext lesen und Modellnamen auflisten", "zh": "让 OpenCode Zen 读取可见页面文本并列出模型名称", "ja": "OpenCode Zenに表示中のページテキストを読み取りモデル名を列挙させる", "ko": "OpenCode Zen가 보이는 페이지 텍스트를 읽고 모델 이름을 나열하도록 요청", "pt": "Peça ao OpenCode Zen para ler o texto visível e listar os modelos", "ar": "اطلب من OpenCode Zen قراءة النص الظاهر وسرد أسماء النماذج"],
        "locSaveSessionModels": ["en": "Save session & models", "ru": "Сохранить сессию и модели", "es": "Guardar sesión y modelos", "fr": "Enregistrer la session et les modèles", "de": "Sitzung und Modelle speichern", "zh": "保存会话和模型", "ja": "セッションとモデルを保存", "ko": "세션 및 모델 저장", "pt": "Guardar sessão e modelos", "ar": "حفظ الجلسة والنماذج"],
        "locDetectModelsFirst": ["en": "Detect models first", "ru": "Сначала определите модели", "es": "Detecta primero los modelos", "fr": "Détectez d’abord les modèles", "de": "Erkennen Sie zuerst Modelle", "zh": "请先检测模型", "ja": "先にモデルを検出してください", "ko": "먼저 모델을 감지하세요", "pt": "Detete primeiro os modelos", "ar": "اكتشف النماذج أولاً"],
        "locNoSelectorFound": ["en": "No selector found for this vendor.", "ru": "Для этого провайдера селектор не найден.", "es": "No se encontró ningún selector para este proveedor.", "fr": "Aucun sélecteur trouvé pour ce fournisseur.", "de": "Für diesen Anbieter wurde kein Selektor gefunden.", "zh": "未找到此提供商的选择器。", "ja": "このベンダーのセレクターが見つかりません。", "ko": "이 공급자의 선택기를 찾을 수 없습니다.", "pt": "Não foi encontrado um seletor para este fornecedor.", "ar": "لم يتم العثور على محدد لهذا الموفر."],
        "locNoModelsFound": ["en": "No models found in the live model menu.", "ru": "В живом меню моделей ничего не найдено.", "es": "No se encontraron modelos en el menú activo.", "fr": "Aucun modèle trouvé dans le menu actif.", "de": "Im Live-Modellmenü wurden keine Modelle gefunden.", "zh": "实时模型菜单中未找到模型。", "ja": "ライブモデルメニューにモデルが見つかりません。", "ko": "실시간 모델 메뉴에서 모델을 찾을 수 없습니다.", "pt": "Não foram encontrados modelos no menu ativo.", "ar": "لم يتم العثور على نماذج في قائمة النماذج المباشرة."],
        "locNoReadablePageText": ["en": "The authenticated page has no readable text.", "ru": "На авторизованной странице нет доступного для чтения текста.", "es": "La página autenticada no contiene texto legible.", "fr": "La page authentifiée ne contient aucun texte lisible.", "de": "Die authentifizierte Seite enthält keinen lesbaren Text.", "zh": "已登录页面没有可读取的文本。", "ja": "認証済みページに読み取れるテキストがありません。", "ko": "인증된 페이지에 읽을 수 있는 텍스트가 없습니다.", "pt": "A página autenticada não tem texto legível.", "ar": "لا تحتوي الصفحة الموثقة على نص قابل للقراءة."],
        "locAIDetectionFailed": ["en": "AI detection failed: %@", "ru": "Определение ИИ не удалось: %@", "es": "La detección por IA falló: %@", "fr": "La détection IA a échoué : %@", "de": "KI-Erkennung fehlgeschlagen: %@", "zh": "AI 检测失败：%@", "ja": "AI検出に失敗しました: %@", "ko": "AI 감지 실패: %@", "pt": "Falha na deteção por IA: %@", "ar": "فشل اكتشاف الذكاء الاصطناعي: %@"],
        "locNoModelNamesReturned": ["en": "No model names were returned by the free AI.", "ru": "Бесплатная модель ИИ не вернула названия моделей.", "es": "La IA gratuita no devolvió nombres de modelos.", "fr": "L’IA gratuite n’a renvoyé aucun nom de modèle.", "de": "Die kostenlose KI gab keine Modellnamen zurück.", "zh": "免费 AI 未返回模型名称。", "ja": "無料AIからモデル名が返されませんでした。", "ko": "무료 AI가 모델 이름을 반환하지 않았습니다.", "pt": "A IA gratuita não devolveu nomes de modelos.", "ar": "لم يُرجع الذكاء الاصطناعي المجاني أسماء نماذج."],
        "locAICandidateVerification": ["en": "AI-assisted candidate; verify with built-in DOM detection before use.", "ru": "Кандидат найден ИИ; проверьте его встроенным определением DOM перед использованием.", "es": "Candidato asistido por IA; verifícalo con la detección DOM integrada antes de usarlo.", "fr": "Candidat assisté par IA ; vérifiez-le avec la détection DOM intégrée avant utilisation.", "de": "KI-gestützter Kandidat; vor Verwendung mit der integrierten DOM-Erkennung prüfen.", "zh": "AI 辅助候选项；使用前请通过内置 DOM 检测验证。", "ja": "AI支援候補。使用前に内蔵DOM検出で確認してください。", "ko": "AI 지원 후보입니다. 사용 전에 내장 DOM 감지로 확인하세요.", "pt": "Candidato assistido por IA; verifique com a deteção DOM integrada antes de usar.", "ar": "مرشح بمساعدة الذكاء الاصطناعي؛ تحقق منه عبر اكتشاف DOM المدمج قبل الاستخدام."],
        "locProviderMetadata": ["en": "Provider metadata", "ru": "Метаданные провайдера", "es": "Metadatos del proveedor", "fr": "Métadonnées du fournisseur", "de": "Anbietermetadaten", "zh": "提供商元数据", "ja": "プロバイダーメタデータ", "ko": "공급자 메타데이터", "pt": "Metadados do fornecedor", "ar": "بيانات الموفر الوصفية"],
        "locNoModelMetadata": ["en": "This provider did not return model metadata. You can still set request overrides below.", "ru": "Этот провайдер не вернул метаданные модели. Ниже всё равно можно задать параметры запроса.", "es": "Este proveedor no devolvió metadatos del modelo. Aun así puedes establecer ajustes de solicitud abajo.", "fr": "Ce fournisseur n’a pas renvoyé de métadonnées du modèle. Vous pouvez quand même définir les paramètres ci-dessous.", "de": "Dieser Anbieter gab keine Modellmetadaten zurück. Sie können unten dennoch Anfrageüberschreibungen festlegen.", "zh": "此提供商未返回模型元数据。您仍可在下方设置请求覆盖参数。", "ja": "このプロバイダーはモデルメタデータを返しませんでした。以下でリクエストの上書きを設定できます。", "ko": "이 공급자는 모델 메타데이터를 반환하지 않았습니다. 아래에서 요청 재정의를 설정할 수 있습니다.", "pt": "Este fornecedor não devolveu metadados do modelo. Ainda pode definir substituições do pedido abaixo.", "ar": "لم يُرجع هذا الموفر بيانات وصفية للنموذج. يمكنك مع ذلك ضبط تجاوزات الطلب أدناه."],
        "locVisionInput": ["en": "Vision (image input)", "ru": "Зрение (ввод изображений)", "es": "Visión (entrada de imágenes)", "fr": "Vision (entrée d’images)", "de": "Vision (Bildeingabe)", "zh": "视觉（图像输入）", "ja": "ビジョン（画像入力）", "ko": "비전(이미지 입력)", "pt": "Visão (entrada de imagens)", "ar": "الرؤية (إدخال الصور)"],
        "locImageGeneration": ["en": "Image generation", "ru": "Генерация изображений", "es": "Generación de imágenes", "fr": "Génération d’images", "de": "Bildgenerierung", "zh": "图像生成", "ja": "画像生成", "ko": "이미지 생성", "pt": "Geração de imagens", "ar": "إنشاء الصور"],
        "locEffortLevels": ["en": "Reasoning effort levels", "ru": "Уровни рассуждения", "es": "Niveles de razonamiento", "fr": "Niveaux de raisonnement", "de": "Argumentationsstufen", "zh": "推理强度级别", "ja": "推論レベル", "ko": "추론 수준", "pt": "Níveis de raciocínio", "ar": "مستويات الاستدلال"],
        "locManualMetadata": ["en": "Manual model metadata", "ru": "Ручные метаданные модели", "es": "Metadatos manuales del modelo", "fr": "Métadonnées manuelles du modèle", "de": "Manuelle Modellmetadaten", "zh": "手动模型元数据", "ja": "手動モデルメタデータ", "ko": "수동 모델 메타데이터", "pt": "Metadados manuais do modelo", "ar": "بيانات وصفية يدوية للنموذج"],
        "locResetMetadata": ["en": "Reset manual metadata", "ru": "Сбросить ручные метаданные", "es": "Restablecer metadatos manuales", "fr": "Réinitialiser les métadonnées manuelles", "de": "Manuelle Metadaten zurücksetzen", "zh": "重置手动元数据", "ja": "手動メタデータをリセット", "ko": "수동 메타데이터 재설정", "pt": "Repor metadados manuais", "ar": "إعادة تعيين البيانات الوصفية اليدوية"],
        "locLiveWebProfile": ["en": "Live web profile", "ru": "Актуальный веб-профиль", "es": "Perfil web en directo", "fr": "Profil web en direct", "de": "Live-Webprofil", "zh": "实时网页配置", "ja": "ライブウェブプロファイル", "ko": "실시간 웹 프로필", "pt": "Perfil web em direto", "ar": "ملف الويب المباشر"],
        "locNoParameterControls": ["en": "No parameter controls detected", "ru": "Элементы управления параметрами не найдены", "es": "No se detectaron controles de parámetros", "fr": "Aucun contrôle de paramètre détecté", "de": "Keine Parametersteuerungen erkannt", "zh": "未检测到参数控件", "ja": "パラメータ操作を検出できません", "ko": "매개변수 컨트롤이 감지되지 않음", "pt": "Não foram detetados controlos de parâmetros", "ar": "لم يتم اكتشاف عناصر تحكم للمعلمات"],
        "locDetectedDefaults": ["en": "Detected defaults: %@", "ru": "Определённые значения по умолчанию: %@", "es": "Valores predeterminados detectados: %@", "fr": "Valeurs par défaut détectées : %@", "de": "Erkannte Standardwerte: %@", "zh": "检测到的默认值：%@", "ja": "検出されたデフォルト: %@", "ko": "감지된 기본값: %@", "pt": "Predefinições detetadas: %@", "ar": "الإعدادات الافتراضية المكتشفة: %@"],
        "locDetectedLabels": ["en": "Detected labels: %@", "ru": "Определённые подписи: %@", "es": "Etiquetas detectadas: %@", "fr": "Libellés détectés : %@", "de": "Erkannte Bezeichnungen: %@", "zh": "检测到的标签：%@", "ja": "検出されたラベル: %@", "ko": "감지된 레이블: %@", "pt": "Rótulos detetados: %@", "ar": "التسميات المكتشفة: %@"],
        "locTemperature": ["en": "Temperature", "ru": "Температура", "es": "Temperatura", "fr": "Température", "de": "Temperatur", "zh": "温度", "ja": "温度", "ko": "온도", "pt": "Temperatura", "ar": "درجة الحرارة"],
        "locMaxTokens": ["en": "Max tokens", "ru": "Макс. токены", "es": "Tokens máximos", "fr": "Tokens max.", "de": "Max. Token", "zh": "最大令牌数", "ja": "最大トークン数", "ko": "최대 토큰", "pt": "Máx. tokens", "ar": "الحد الأقصى للرموز"],
        "locTopP": ["en": "Top P", "ru": "Top P", "es": "Top P", "fr": "Top P", "de": "Top P", "zh": "Top P", "ja": "Top P", "ko": "Top P", "pt": "Top P", "ar": "Top P"],
        "locSystemPromptOverride": ["en": "System prompt override", "ru": "Переопределение системного промпта", "es": "Sobrescritura del prompt del sistema", "fr": "Remplacement du prompt système", "de": "Überschreibung des System-Prompts", "zh": "系统提示覆盖", "ja": "システムプロンプトの上書き", "ko": "시스템 프롬프트 재정의", "pt": "Substituição do prompt do sistema", "ar": "تجاوز موجه النظام"],
        "locBlankValuesProviderDefaults": ["en": "Blank values use provider defaults.", "ru": "Пустые значения используют настройки провайдера.", "es": "Los valores vacíos usan los valores predeterminados del proveedor.", "fr": "Les valeurs vides utilisent les valeurs par défaut du fournisseur.", "de": "Leere Werte verwenden die Anbieterstandards.", "zh": "空值使用提供商默认值。", "ja": "空欄はプロバイダーのデフォルトを使用します。", "ko": "빈 값은 공급자 기본값을 사용합니다.", "pt": "Os valores vazios usam as predefinições do fornecedor.", "ar": "تستخدم القيم الفارغة إعدادات الموفر الافتراضية."],
        "locResetParameters": ["en": "Reset", "ru": "Сбросить", "es": "Restablecer", "fr": "Réinitialiser", "de": "Zurücksetzen", "zh": "重置", "ja": "リセット", "ko": "재설정", "pt": "Repor", "ar": "إعادة ضبط"],
        "locSaveParameters": ["en": "Save parameters", "ru": "Сохранить параметры", "es": "Guardar parámetros", "fr": "Enregistrer les paramètres", "de": "Parameter speichern", "zh": "保存参数", "ja": "パラメータを保存", "ko": "매개변수 저장", "pt": "Guardar parâmetros", "ar": "حفظ المعلمات"],
        "locUseNumericParameters": ["en": "Use numeric values for temperature, max tokens and top P.", "ru": "Введите числовые значения для температуры, макс. токенов и Top P.", "es": "Usa valores numéricos para temperatura, tokens máximos y Top P.", "fr": "Utilisez des valeurs numériques pour la température, les tokens max. et Top P.", "de": "Verwenden Sie numerische Werte für Temperatur, Max. Token und Top P.", "zh": "温度、最大令牌数和 Top P 必须使用数字。", "ja": "温度、最大トークン数、Top Pには数値を使用してください。", "ko": "온도, 최대 토큰 및 Top P에는 숫자 값을 사용하세요.", "pt": "Use valores numéricos para temperatura, máx. tokens e Top P.", "ar": "استخدم قيماً رقمية لدرجة الحرارة والحد الأقصى للرموز وTop P."],
        "locTemperatureRange": ["en": "Temperature must be between 0 and 2.", "ru": "Температура должна быть от 0 до 2.", "es": "La temperatura debe estar entre 0 y 2.", "fr": "La température doit être comprise entre 0 et 2.", "de": "Die Temperatur muss zwischen 0 und 2 liegen.", "zh": "温度必须在 0 到 2 之间。", "ja": "温度は0から2の間で指定してください。", "ko": "온도는 0에서 2 사이여야 합니다.", "pt": "A temperatura deve estar entre 0 e 2.", "ar": "يجب أن تكون درجة الحرارة بين 0 و2."],
        "locMaxTokensRange": ["en": "Max tokens must be greater than 0.", "ru": "Макс. токены должны быть больше 0.", "es": "Los tokens máximos deben ser mayores que 0.", "fr": "Les tokens max. doivent être supérieurs à 0.", "de": "Max. Token müssen größer als 0 sein.", "zh": "最大令牌数必须大于 0。", "ja": "最大トークン数は0より大きくしてください。", "ko": "최대 토큰은 0보다 커야 합니다.", "pt": "Os máx. tokens devem ser superiores a 0.", "ar": "يجب أن يكون الحد الأقصى للرموز أكبر من 0."],
        "locTopPRange": ["en": "Top P must be between 0 and 1.", "ru": "Top P должен быть от 0 до 1.", "es": "Top P debe estar entre 0 y 1.", "fr": "Top P doit être compris entre 0 et 1.", "de": "Top P muss zwischen 0 und 1 liegen.", "zh": "Top P 必须在 0 到 1 之间。", "ja": "Top Pは0から1の間で指定してください。", "ko": "Top P는 0에서 1 사이여야 합니다.", "pt": "Top P deve estar entre 0 e 1.", "ar": "يجب أن تكون Top P بين 0 و1."],
        "locSortModels": ["en": "Sort: %@", "ru": "Сортировка: %@", "es": "Ordenar: %@", "fr": "Trier : %@", "de": "Sortieren: %@", "zh": "排序：%@", "ja": "並べ替え: %@", "ko": "정렬: %@", "pt": "Ordenar: %@", "ar": "الفرز: %@"],
        "locFilterModels": ["en": "Filter models", "ru": "Фильтр моделей", "es": "Filtrar modelos", "fr": "Filtrer les modèles", "de": "Modelle filtern", "zh": "筛选模型", "ja": "モデルを絞り込む", "ko": "모델 필터", "pt": "Filtrar modelos", "ar": "تصفية النماذج"],
        "locNoModelsMatchFilter": ["en": "No models match this filter.", "ru": "Модели не соответствуют фильтру.", "es": "Ningún modelo coincide con este filtro.", "fr": "Aucun modèle ne correspond à ce filtre.", "de": "Keine Modelle entsprechen diesem Filter.", "zh": "没有模型符合此筛选条件。", "ja": "このフィルターに一致するモデルはありません。", "ko": "이 필터와 일치하는 모델이 없습니다.", "pt": "Nenhum modelo corresponde a este filtro.", "ar": "لا توجد نماذج تطابق هذا المرشح."],
        "locModelsCountOf": ["en": "%d of %d models", "ru": "%d из %d моделей", "es": "%d de %d modelos", "fr": "%d sur %d modèles", "de": "%d von %d Modellen", "zh": "%d/%d 个模型", "ja": "%d/%d モデル", "ko": "%d/%d개 모델", "pt": "%d de %d modelos", "ar": "%d من أصل %d نموذج"],
        "locAllModels": ["en": "All models", "ru": "Все модели", "es": "Todos los modelos", "fr": "Tous les modèles", "de": "Alle Modelle", "zh": "所有模型", "ja": "すべてのモデル", "ko": "모든 모델", "pt": "Todos os modelos", "ar": "جميع النماذج"],
        "locModelCount": ["en": "%d model", "ru": "%d модель", "es": "%d modelo", "fr": "%d modèle", "de": "%d Modell", "zh": "%d 个模型", "ja": "%d モデル", "ko": "%d개 모델", "pt": "%d modelo", "ar": "%d نموذج"],
        "locAvailableCount": ["en": "%d available", "ru": "Доступно: %d", "es": "%d disponibles", "fr": "%d disponibles", "de": "%d verfügbar", "zh": "可用 %d 个", "ja": "%d 件利用可能", "ko": "%d개 사용 가능", "pt": "%d disponíveis", "ar": "%d متاح"],
        "locProviderParameters": ["en": "Provider parameters", "ru": "Параметры провайдера", "es": "Parámetros del proveedor", "fr": "Paramètres du fournisseur", "de": "Anbieterparameter", "zh": "提供商参数", "ja": "プロバイダーパラメータ", "ko": "공급자 매개변수", "pt": "Parâmetros do fornecedor", "ar": "معلمات الموفر"],
        "locChooseFromList": ["en": "Choose from list", "ru": "Выберите из списка", "es": "Elegir de la lista", "fr": "Choisir dans la liste", "de": "Aus Liste wählen", "zh": "从列表选择", "ja": "リストから選択", "ko": "목록에서 선택", "pt": "Escolher da lista", "ar": "الاختيار من القائمة"],
        "locFreeModelsPrivacy": ["en": "Free models are temporary OpenCode routes. Availability, rate limits, model metadata and data-use terms can change. Do not send secrets.", "ru": "Бесплатные модели — временные маршруты OpenCode. Доступность, лимиты, метаданные и условия обработки данных могут измениться. Не отправляйте секреты.", "es": "Los modelos gratuitos son rutas temporales de OpenCode. La disponibilidad, los límites y las condiciones de datos pueden cambiar. No envíes secretos.", "fr": "Les modèles gratuits sont des routes OpenCode temporaires. Disponibilité, limites, métadonnées et conditions d’utilisation peuvent changer. N’envoyez pas de secrets.", "de": "Kostenlose Modelle sind temporäre OpenCode-Routen. Verfügbarkeit, Limits, Metadaten und Datennutzungsbedingungen können sich ändern. Senden Sie keine Geheimnisse.", "zh": "免费模型是临时的 OpenCode 路由。可用性、速率限制、模型元数据和数据使用条款可能变化。请勿发送机密信息。", "ja": "無料モデルは一時的なOpenCodeルートです。利用状況、レート制限、メタデータ、データ利用条件は変わる可能性があります。秘密情報を送らないでください。", "ko": "무료 모델은 임시 OpenCode 경로입니다. 가용성, 속도 제한, 메타데이터 및 데이터 사용 약관은 변경될 수 있습니다. 비밀을 보내지 마세요.", "pt": "Os modelos gratuitos são rotas temporárias do OpenCode. Disponibilidade, limites, metadados e termos de dados podem mudar. Não envie segredos.", "ar": "النماذج المجانية مسارات مؤقتة من OpenCode. قد تتغير التوافرية وحدود المعدل والبيانات الوصفية وشروط استخدام البيانات. لا ترسل أسراراً."],
        "locLiveFreeModels": ["en": "Live free models", "ru": "Актуальные бесплатные модели", "es": "Modelos gratuitos activos", "fr": "Modèles gratuits actifs", "de": "Aktive kostenlose Modelle", "zh": "实时免费模型", "ja": "ライブ無料モデル", "ko": "실시간 무료 모델", "pt": "Modelos gratuitos ativos", "ar": "النماذج المجانية المباشرة"],
        "locNoEligibleFreeModels": ["en": "No eligible free models are currently returned by OpenCode. Refresh the catalog or choose another provider.", "ru": "OpenCode сейчас не вернул подходящих бесплатных моделей. Обновите каталог или выберите другого провайдера.", "es": "OpenCode no devuelve modelos gratuitos elegibles. Actualiza el catálogo o elige otro proveedor.", "fr": "OpenCode ne renvoie actuellement aucun modèle gratuit éligible. Actualisez le catalogue ou choisissez un autre fournisseur.", "de": "OpenCode gibt derzeit keine passenden kostenlosen Modelle zurück. Aktualisieren Sie den Katalog oder wählen Sie einen anderen Anbieter.", "zh": "OpenCode 当前未返回符合条件的免费模型。请刷新目录或选择其他提供商。", "ja": "OpenCodeから現在利用可能な無料モデルが返されません。カタログを更新するか別のプロバイダーを選択してください。", "ko": "OpenCode에서 현재 적합한 무료 모델을 반환하지 않습니다. 카탈로그를 새로 고치거나 다른 공급자를 선택하세요.", "pt": "O OpenCode não devolve atualmente modelos gratuitos elegíveis. Atualize o catálogo ou escolha outro fornecedor.", "ar": "لا يعيد OpenCode حالياً نماذج مجانية مؤهلة. حدّث الكتالوج أو اختر موفراً آخر."],
        "locSwitchFreeModel": ["en": "Switch free model", "ru": "Переключить бесплатную модель", "es": "Cambiar modelo gratuito", "fr": "Changer de modèle gratuit", "de": "Kostenloses Modell wechseln", "zh": "切换免费模型", "ja": "無料モデルを切り替え", "ko": "무료 모델 전환", "pt": "Mudar modelo gratuito", "ar": "تبديل النموذج المجاني"],
        "locUnlockSelectedModel": ["en": "Unlock selected model", "ru": "Разблокировать выбранную модель", "es": "Desbloquear el modelo seleccionado", "fr": "Déverrouiller le modèle sélectionné", "de": "Ausgewähltes Modell entsperren", "zh": "解锁所选模型", "ja": "選択したモデルのロックを解除", "ko": "선택한 모델 잠금 해제", "pt": "Desbloquear o modelo selecionado", "ar": "إلغاء قفل النموذج المحدد"],
        "locLockSelectedModel": ["en": "Lock selected model", "ru": "Заблокировать выбранную модель", "es": "Bloquear el modelo seleccionado", "fr": "Verrouiller le modèle sélectionné", "de": "Ausgewähltes Modell sperren", "zh": "锁定所选模型", "ja": "選択したモデルをロック", "ko": "선택한 모델 잠금", "pt": "Bloquear o modelo selecionado", "ar": "قفل النموذج المحدد"],
        "locModelLocked": ["en": "Model locked", "ru": "Модель заблокирована", "es": "Modelo bloqueado", "fr": "Modèle verrouillé", "de": "Modell gesperrt", "zh": "模型已锁定", "ja": "モデルをロックしました", "ko": "모델 잠김", "pt": "Modelo bloqueado", "ar": "النموذج مقفل"],
        "locAutomaticFallbackEnabled": ["en": "Automatic fallback enabled", "ru": "Автоматическое переключение включено", "es": "Cambio automático activado", "fr": "Basculement automatique activé", "de": "Automatischer Fallback aktiviert", "zh": "已启用自动回退", "ja": "自動フォールバック有効", "ko": "자동 대체 활성화", "pt": "Fallback automático ativado", "ar": "تمكين التبديل التلقائي"],
        "locModelLockedDescription": ["en": "The selected model will not be changed automatically. Unlock it to allow failover.", "ru": "Выбранная модель не будет меняться автоматически. Разблокируйте её для переключения при сбое.", "es": "El modelo seleccionado no cambiará automáticamente. Desbloquéalo para permitir el cambio por fallo.", "fr": "Le modèle sélectionné ne changera pas automatiquement. Déverrouillez-le pour autoriser le basculement.", "de": "Das ausgewählte Modell wird nicht automatisch geändert. Entsperren Sie es für Failover.", "zh": "所选模型不会自动更改。解锁后才能在故障时切换。", "ja": "選択したモデルは自動変更されません。ロックを解除するとフェイルオーバーできます。", "ko": "선택한 모델은 자동으로 변경되지 않습니다. 잠금을 해제하면 장애 조치가 허용됩니다.", "pt": "O modelo selecionado não será alterado automaticamente. Desbloqueie-o para permitir o failover.", "ar": "لن يتم تغيير النموذج المحدد تلقائياً. ألغِ قفله للسماح بالتبديل عند الفشل."],
        "locAutomaticFallbackDescription": ["en": "Rate limits and repeated failures can move the request to another live free model.", "ru": "Лимиты и повторные ошибки могут переключить запрос на другую доступную бесплатную модель.", "es": "Los límites y fallos repetidos pueden mover la solicitud a otro modelo gratuito activo.", "fr": "Les limites et échecs répétés peuvent déplacer la requête vers un autre modèle gratuit actif.", "de": "Ratenlimits und wiederholte Fehler können die Anfrage auf ein anderes kostenloses Modell verschieben.", "zh": "速率限制和重复失败可能将请求切换到其他实时免费模型。", "ja": "レート制限や繰り返しの失敗により、別の無料モデルへ切り替わることがあります。", "ko": "속도 제한과 반복되는 실패로 요청이 다른 실시간 무료 모델로 이동할 수 있습니다.", "pt": "Limites e falhas repetidas podem mover o pedido para outro modelo gratuito ativo.", "ar": "قد تنقل حدود المعدل والإخفاقات المتكررة الطلب إلى نموذج مجاني مباشر آخر."],
        "locSystemPromptSentBeforeRequest": ["en": "Sent before every free-model request.", "ru": "Отправляется перед каждым запросом к бесплатной модели.", "es": "Se envía antes de cada solicitud al modelo gratuito.", "fr": "Envoyé avant chaque requête au modèle gratuit.", "de": "Wird vor jeder Anfrage an ein kostenloses Modell gesendet.", "zh": "在每次免费模型请求前发送。", "ja": "無料モデルへの各リクエストの前に送信されます。", "ko": "각 무료 모델 요청 전에 전송됩니다.", "pt": "Enviado antes de cada pedido ao modelo gratuito.", "ar": "يُرسل قبل كل طلب إلى النموذج المجاني."],
        "locSavePrompt": ["en": "Save prompt", "ru": "Сохранить промпт", "es": "Guardar prompt", "fr": "Enregistrer le prompt", "de": "Prompt speichern", "zh": "保存提示", "ja": "プロンプトを保存", "ko": "프롬프트 저장", "pt": "Guardar prompt", "ar": "حفظ الموجه"],
        "locRefreshCatalog": ["en": "Refresh catalog", "ru": "Обновить каталог", "es": "Actualizar catálogo", "fr": "Actualiser le catalogue", "de": "Katalog aktualisieren", "zh": "刷新目录", "ja": "カタログを更新", "ko": "카탈로그 새로 고침", "pt": "Atualizar catálogo", "ar": "تحديث الكتالوج"],
        "locRefreshing": ["en": "Refreshing…", "ru": "Обновление…", "es": "Actualizando…", "fr": "Actualisation…", "de": "Wird aktualisiert…", "zh": "正在刷新…", "ja": "更新中…", "ko": "새로 고치는 중…", "pt": "A atualizar…", "ar": "جارٍ التحديث…"],
        "locUpdated": ["en": "Updated %@", "ru": "Обновлено %@", "es": "Actualizado %@", "fr": "Mis à jour %@", "de": "Aktualisiert %@", "zh": "已更新 %@", "ja": "更新済み %@", "ko": "업데이트됨 %@", "pt": "Atualizado %@", "ar": "تم التحديث %@"],
        "locEndpoint": ["en": "Endpoint", "ru": "Конечная точка", "es": "Punto final", "fr": "Point de terminaison", "de": "Endpunkt", "zh": "端点", "ja": "エンドポイント", "ko": "엔드포인트", "pt": "Endpoint", "ar": "نقطة النهاية"],
        "locProtocol": ["en": "Protocol", "ru": "Протокол", "es": "Protocolo", "fr": "Protocole", "de": "Protokoll", "zh": "协议", "ja": "プロトコル", "ko": "프로토콜", "pt": "Protocolo", "ar": "البروتوكول"],
        "locAccess": ["en": "Access", "ru": "Доступ", "es": "Acceso", "fr": "Accès", "de": "Zugriff", "zh": "访问", "ja": "アクセス", "ko": "액세스", "pt": "Acesso", "ar": "الوصول"],
        "locFallback": ["en": "Fallback", "ru": "Переключение", "es": "Alternativa", "fr": "Basculement", "de": "Fallback", "zh": "回退", "ja": "フォールバック", "ko": "대체", "pt": "Fallback", "ar": "التبديل"],
        "locAnonymousNoKey": ["en": "Anonymous · no key", "ru": "Анонимный · без ключа", "es": "Anónimo · sin clave", "fr": "Anonyme · sans clé", "de": "Anonym · kein Schlüssel", "zh": "匿名 · 无密钥", "ja": "匿名 · キーなし", "ko": "익명 · 키 없음", "pt": "Anónimo · sem chave", "ar": "مجهول · بدون مفتاح"],
        "locRateLimitOrFailures": ["en": "Rate limit or 5 failures", "ru": "Лимит или 5 ошибок", "es": "Límite o 5 fallos", "fr": "Limite ou 5 échecs", "de": "Ratenlimit oder 5 Fehler", "zh": "速率限制或 5 次失败", "ja": "レート制限または5回の失敗", "ko": "속도 제한 또는 5회 실패", "pt": "Limite ou 5 falhas", "ar": "حد المعدل أو 5 إخفاقات"],
        "locOpenCodeZenDescription": ["en": "OpenCode Zen · live anonymous free-model workspace", "ru": "OpenCode Zen · рабочее пространство бесплатных анонимных моделей", "es": "OpenCode Zen · espacio de modelos gratuitos anónimos activos", "fr": "OpenCode Zen · espace de modèles gratuits anonymes actifs", "de": "OpenCode Zen · aktiver Arbeitsbereich für anonyme kostenlose Modelle", "zh": "OpenCode Zen · 实时匿名免费模型工作区", "ja": "OpenCode Zen · ライブ匿名無料モデルワークスペース", "ko": "OpenCode Zen · 실시간 익명 무료 모델 작업 공간", "pt": "OpenCode Zen · espaço de modelos gratuitos anónimos ativos", "ar": "OpenCode Zen · مساحة عمل للنماذج المجانية المجهولة المباشرة"],
        "locOnlineFreeModels": ["en": "ONLINE · %d free models", "ru": "ОНЛАЙН · бесплатных моделей: %d", "es": "EN LÍNEA · %d modelos gratuitos", "fr": "EN LIGNE · %d modèles gratuits", "de": "ONLINE · %d kostenlose Modelle", "zh": "在线 · %d 个免费模型", "ja": "オンライン · 無料モデル %d 件", "ko": "온라인 · 무료 모델 %d개", "pt": "ONLINE · %d modelos gratuitos", "ar": "متصل · %d نماذج مجانية"],
        "locOfflineCatalogUnavailable": ["en": "OFFLINE · free catalog unavailable", "ru": "ОФЛАЙН · бесплатный каталог недоступен", "es": "SIN CONEXIÓN · catálogo gratuito no disponible", "fr": "HORS LIGNE · catalogue gratuit indisponible", "de": "OFFLINE · kostenloser Katalog nicht verfügbar", "zh": "离线 · 免费目录不可用", "ja": "オフライン · 無料カタログ unavailable", "ko": "오프라인 · 무료 카탈로그 사용 불가", "pt": "OFFLINE · catálogo gratuito indisponível", "ar": "غير متصل · الكتالوج المجاني غير متاح"],
        "locLoadingLiveCatalog": ["en": "Loading live OpenCode catalog…", "ru": "Загрузка актуального каталога OpenCode…", "es": "Cargando catálogo activo de OpenCode…", "fr": "Chargement du catalogue OpenCode en direct…", "de": "Live-OpenCode-Katalog wird geladen…", "zh": "正在加载实时 OpenCode 目录…", "ja": "ライブOpenCodeカタログを読み込み中…", "ko": "실시간 OpenCode 카탈로그 로드 중…", "pt": "A carregar o catálogo OpenCode em direto…", "ar": "جارٍ تحميل كتالوج OpenCode المباشر…"],
        "locFreeBadge": ["en": "FREE", "ru": "БЕСПЛАТНО", "es": "GRATIS", "fr": "GRATUIT", "de": "KOSTENLOS", "zh": "免费", "ja": "無料", "ko": "무료", "pt": "GRÁTIS", "ar": "مجاني"],
        "locStorageImportReplace": ["en": "Import and replace", "ru": "Импортировать и заменить", "es": "Importar y reemplazar", "fr": "Importer et remplacer", "de": "Importieren und ersetzen", "zh": "导入并替换", "ja": "インポートして置換", "ko": "가져와서 교체", "pt": "Importar e substituir", "ar": "استيراد واستبدال"],
        "locStorageImportWarning": ["en": "Importing will replace the current project registry and app settings. This action cannot be undone.", "ru": "Импорт заменит текущий реестр проектов и настройки приложения. Это действие нельзя отменить.", "es": "La importación reemplazará el registro de proyectos y los ajustes actuales. Esta acción no se puede deshacer.", "fr": "L’importation remplacera le registre de projets et les réglages actuels. Cette action est irréversible.", "de": "Der Import ersetzt die aktuelle Projektregistrierung und App-Einstellungen. Diese Aktion kann nicht rückgängig gemacht werden.", "zh": "导入将替换当前项目注册表和应用设置。此操作无法撤销。", "ja": "インポートすると現在のプロジェクトレジストリとアプリ設定が置き換えられます。この操作は取り消せません。", "ko": "가져오기는 현재 프로젝트 레지스트리와 앱 설정을 교체합니다. 이 작업은 취소할 수 없습니다.", "pt": "A importação substituirá o registo de projetos e as definições atuais. Esta ação não pode ser anulada.", "ar": "سيؤدي الاستيراد إلى استبدال سجل المشاريع وإعدادات التطبيق الحالية. لا يمكن التراجع عن هذا الإجراء."],
        "locStorageExportConfiguration": ["en": "Export app configuration", "ru": "Экспортировать конфигурацию приложения", "es": "Exportar configuración de la aplicación", "fr": "Exporter la configuration de l’application", "de": "App-Konfiguration exportieren", "zh": "导出应用配置", "ja": "アプリ設定をエクスポート", "ko": "앱 구성 내보내기", "pt": "Exportar configuração da aplicação", "ar": "تصدير إعدادات التطبيق"],
        "locStorageImportConfiguration": ["en": "Import app configuration", "ru": "Импортировать конфигурацию приложения", "es": "Importar configuración de la aplicación", "fr": "Importer la configuration de l’application", "de": "App-Konfiguration importieren", "zh": "导入应用配置", "ja": "アプリ設定をインポート", "ko": "앱 구성 가져오기", "pt": "Importar configuração da aplicação", "ar": "استيراد إعدادات التطبيق"],
        "locCancelDeletion": ["en": "Cancel deletion", "ru": "Отменить удаление", "es": "Cancelar eliminación", "fr": "Annuler la suppression", "de": "Löschen abbrechen", "zh": "取消删除", "ja": "削除をキャンセル", "ko": "삭제 취소", "pt": "Cancelar eliminação", "ar": "إلغاء الحذف"],
        "locProjectRegistryDeletionWarning": ["en": "The project stays in the registry until deletion completes successfully.", "ru": "Проект останется в реестре, пока удаление не завершится успешно.", "es": "El proyecto permanecerá en el registro hasta que la eliminación finalice correctamente.", "fr": "Le projet reste dans le registre jusqu’à la réussite de la suppression.", "de": "Das Projekt bleibt im Register, bis es erfolgreich gelöscht wurde.", "zh": "删除成功完成前，项目仍保留在注册表中。", "ja": "削除が正常に完了するまで、プロジェクトはレジストリに残ります。", "ko": "삭제가 성공적으로 완료될 때까지 프로젝트는 레지스트리에 남습니다.", "pt": "O projeto permanece no registo até a eliminação ser concluída com sucesso.", "ar": "يبقى المشروع في السجل حتى يكتمل الحذف بنجاح."],
        "locOK": ["en": "OK", "ru": "ОК", "es": "Aceptar", "fr": "OK", "de": "OK", "zh": "确定", "ja": "OK", "ko": "확인", "pt": "OK", "ar": "موافق"],
        "locAllWorkspaces": ["en": "All workspaces", "ru": "Все рабочие области", "es": "Todas las áreas de trabajo", "fr": "Tous les espaces de travail", "de": "Alle Arbeitsbereiche", "zh": "所有工作区", "ja": "すべてのワークスペース", "ko": "모든 작업 공간", "pt": "Todas as áreas de trabalho", "ar": "جميع مساحات العمل"],
        "locProjectFiles": ["en": "Project files", "ru": "Файлы проекта", "es": "Archivos del proyecto", "fr": "Fichiers du projet", "de": "Projektdateien", "zh": "项目文件", "ja": "プロジェクトファイル", "ko": "프로젝트 파일", "pt": "Ficheiros do projeto", "ar": "ملفات المشروع"],
        "locSearchTasks": ["en": "Search tasks…", "ru": "Поиск задач…", "es": "Buscar tareas…", "fr": "Rechercher des tâches…", "de": "Aufgaben suchen…", "zh": "搜索任务…", "ja": "タスクを検索…", "ko": "작업 검색…", "pt": "Pesquisar tarefas…", "ar": "بحث في المهام…"],
        "locCollapseWorkspaces": ["en": "Collapse workspaces", "ru": "Свернуть рабочие области", "es": "Contraer áreas de trabajo", "fr": "Réduire les espaces de travail", "de": "Arbeitsbereiche einklappen", "zh": "折叠工作区", "ja": "ワークスペースを折りたたむ", "ko": "작업 공간 접기", "pt": "Recolher áreas de trabalho", "ar": "طي مساحات العمل"],
        "locExpandWorkspaces": ["en": "Expand workspaces", "ru": "Развернуть рабочие области", "es": "Expandir áreas de trabajo", "fr": "Développer les espaces de travail", "de": "Arbeitsbereiche ausklappen", "zh": "展开工作区", "ja": "ワークスペースを展開", "ko": "작업 공간 펼치기", "pt": "Expandir áreas de trabalho", "ar": "توسيع مساحات العمل"],
        "locWorkspaceActions": ["en": "Workspace actions", "ru": "Действия рабочей области", "es": "Acciones del área de trabajo", "fr": "Actions de l’espace de travail", "de": "Arbeitsbereich-Aktionen", "zh": "工作区操作", "ja": "ワークスペースの操作", "ko": "작업 공간 작업", "pt": "Ações da área de trabalho", "ar": "إجراءات مساحة العمل"],
        "locSortWorkspaces": ["en": "Sort workspaces", "ru": "Сортировать рабочие области", "es": "Ordenar áreas de trabajo", "fr": "Trier les espaces de travail", "de": "Arbeitsbereiche sortieren", "zh": "排序工作区", "ja": "ワークスペースを並べ替え", "ko": "작업 공간 정렬", "pt": "Ordenar áreas de trabalho", "ar": "فرز مساحات العمل"],
        "locHideWorkspaceSearch": ["en": "Hide workspace search", "ru": "Скрыть поиск рабочих областей", "es": "Ocultar búsqueda de áreas de trabajo", "fr": "Masquer la recherche d’espaces de travail", "de": "Arbeitsbereichsuche ausblenden", "zh": "隐藏工作区搜索", "ja": "ワークスペース検索を隠す", "ko": "작업 공간 검색 숨기기", "pt": "Ocultar pesquisa de áreas de trabalho", "ar": "إخفاء بحث مساحات العمل"],
        "locShowWorkspaceSearch": ["en": "Search workspaces", "ru": "Поиск рабочих областей", "es": "Buscar áreas de trabajo", "fr": "Rechercher des espaces de travail", "de": "Arbeitsbereiche suchen", "zh": "搜索工作区", "ja": "ワークスペースを検索", "ko": "작업 공간 검색", "pt": "Pesquisar áreas de trabalho", "ar": "بحث في مساحات العمل"],
        "locShowGrid": ["en": "Show grid", "ru": "Показать сетку", "es": "Mostrar cuadrícula", "fr": "Afficher la grille", "de": "Raster anzeigen", "zh": "显示网格", "ja": "グリッドを表示", "ko": "그리드 표시", "pt": "Mostrar grelha", "ar": "إظهار الشبكة"],
        "locShowList": ["en": "Show list", "ru": "Показать список", "es": "Mostrar lista", "fr": "Afficher la liste", "de": "Liste anzeigen", "zh": "显示列表", "ja": "リストを表示", "ko": "목록 표시", "pt": "Mostrar lista", "ar": "إظهار القائمة"],
        "locCopy": ["en": "Copy", "ru": "Копировать", "es": "Copiar", "fr": "Copier", "de": "Kopieren", "zh": "复制", "ja": "コピー", "ko": "복사", "pt": "Copiar", "ar": "نسخ"],
        "locCut": ["en": "Cut", "ru": "Вырезать", "es": "Cortar", "fr": "Ausschneiden", "de": "قص", "zh": "剪切", "ja": "カット", "ko": "잘라내기", "pt": "Cortar", "ar": "قص"],
        "locPaste": ["en": "Paste", "ru": "Вставить", "es": "Pegar", "fr": "Coller", "de": "Einfügen", "zh": "粘贴", "ja": "ペースト", "ko": "붙여넣기", "pt": "Colar", "ar": "لصق"],
        "locSelectAll": ["en": "Select All", "ru": "Выбрать всё", "es": "Seleccionar todo", "fr": "Tout sélectionner", "de": "Alles auswählen", "zh": "全选", "ja": "すべてを選択", "ko": "모두 선택", "pt": "Selecionar tudo", "ar": "تحديد الكل"],
        "locTemplates": ["en": "Templates", "ru": "Шаблоны", "es": "Plantillas", "fr": "Modèles", "de": "Vorlagen", "zh": "模板", "ja": "テンプレート", "ko": "템플릿", "pt": "Modelos", "ar": "القوالب"],
        "locEffortValue": ["en": "Effort: %@", "ru": "Усилие: %@", "es": "Esfuerzo: %@", "fr": "Effort : %@", "de": "Aufwand: %@", "zh": "推理强度：%@", "ja": "推論レベル: %@", "ko": "추론 수준: %@", "pt": "Esforço: %@", "ar": "الجهد: %@"],
        "locCloseModelParameters": ["en": "Close model parameters", "ru": "Закрыть параметры модели", "es": "Cerrar parámetros del modelo", "fr": "Fermer les paramètres du modèle", "de": "Modellparameter schließen", "zh": "关闭模型参数", "ja": "モデルパラメータを閉じる", "ko": "모델 매개변수 닫기", "pt": "Fechar parâmetros do modelo", "ar": "إغلاق معلمات النموذج"],
        "locSortName": ["en": "Name", "ru": "Имя", "es": "Nombre", "fr": "Nom", "de": "Name", "zh": "名称", "ja": "名前", "ko": "이름", "pt": "Nome", "ar": "الاسم"],
        "locSortContext": ["en": "Context", "ru": "Контекст", "es": "Contexto", "fr": "ConTexto", "de": "Kontext", "zh": "上下文", "ja": "コンテキスト", "ko": "컨텍스트", "pt": "Contexto", "ar": "السياق"],
        "locSortReasoning": ["en": "Reasoning", "ru": "Рассуждение", "es": "Razonamiento", "fr": "Raisonnement", "de": "Denken", "zh": "推理", "ja": "推論", "ko": "추론", "pt": "Raciocínio", "ar": "الاستدلال"],
        "locSortTools": ["en": "Tools", "ru": "Инструменты", "es": "Herramientas", "fr": "Outils", "de": "Werkzeuge", "zh": "工具", "ja": "ツール", "ko": "도구", "pt": "Ferramentas", "ar": "الأدوات"],
        "locProviderNameExample": ["en": "e.g., My OpenRouter", "ru": "например, Мой OpenRouter", "es": "p. ej., Mi OpenRouter", "fr": "ex. : Mon OpenRouter", "de": "z. B. Mein OpenRouter", "zh": "例如：我的 OpenRouter", "ja": "例：マイOpenRouter", "ko": "예: 내 OpenRouter", "pt": "ex.: O meu OpenRouter", "ar": "مثال: OpenRouter الخاص بي"],
        "locProviderNameOptional": ["en": "Optional — defaults to the provider type name", "ru": "Необязательно — по умолчанию имя типа провайдера", "es": "Opcional — por defecto, el nombre del tipo de proveedor", "fr": "Facultatif — par défaut, le nom du type de fournisseur", "de": "Optional — standardmäßig der Name des Anbietertyps", "zh": "可选 — 默认使用提供商类型名称", "ja": "任意 — 既定ではプロバイダータイプ名", "ko": "선택 사항 — 기본값은 공급자 유형 이름", "pt": "Opcional — por defeito, o nome do tipo de fornecedor", "ar": "اختياري — الاسم الافتراضي هو نوع المزود"],
        "locEndpointExample": ["en": "https://api.example.com/v1", "ru": "https://api.example.com/v1", "es": "https://api.example.com/v1", "fr": "https://api.example.com/v1", "de": "https://api.example.com/v1", "zh": "https://api.example.com/v1", "ja": "https://api.example.com/v1", "ko": "https://api.example.com/v1", "pt": "https://api.example.com/v1", "ar": "https://api.example.com/v1"],
        "locContextValue": ["en": "Context: %@", "ru": "Контекст: %@", "es": "Contexto: %@", "fr": "Contexte : %@", "de": "Kontext: %@", "zh": "上下文：%@", "ja": "コンテキスト: %@", "ko": "컨텍스트: %@", "pt": "Contexto: %@", "ar": "السياق: %@"],
        "locLock": ["en": "Lock", "ru": "Заблокировать", "es": "Bloquear", "fr": "Verrouiller", "de": "Sperren", "zh": "锁定", "ja": "ロック", "ko": "잠금", "pt": "Bloquear", "ar": "قفل"],
        "locUnlock": ["en": "Unlock", "ru": "Разблокировать", "es": "Desbloquear", "fr": "Déverrouiller", "de": "Entsperren", "zh": "解锁", "ja": "ロック解除", "ko": "잠금 해제", "pt": "Desbloquear", "ar": "إلغاء القفل"],
        "locReplaceAppConfiguration": ["en": "Replace app configuration?", "ru": "Заменить конфигурацию приложения?", "es": "¿Reemplazar la configuración de la aplicación?", "fr": "Remplacer la configuration de l’application ?", "de": "App-Konfiguration ersetzen?", "zh": "替换应用配置？", "ja": "アプリ設定を置き換えますか？", "ko": "앱 구성을 교체하시겠습니까?", "pt": "Substituir a configuração da aplicação?", "ar": "هل تريد استبدال إعدادات التطبيق؟"],
        "locDeletingProjectData": ["en": "Deleting project data…", "ru": "Удаление данных проекта…", "es": "Eliminando datos del proyecto…", "fr": "Suppression des données du projet…", "de": "Projektdaten werden gelöscht…", "zh": "正在删除项目数据…", "ja": "プロジェクトデータを削除中…", "ko": "프로젝트 데이터 삭제 중…", "pt": "A eliminar dados do projeto…", "ar": "جارٍ حذف بيانات المشروع…"],
        "locProjectDatabaseCorrupted": ["en": "Project database may be corrupted", "ru": "База данных проекта может быть повреждена", "es": "La base de datos del proyecto puede estar dañada", "fr": "La base de données du projet est peut-être corrompue", "de": "Die Projektdatenbank ist möglicherweise beschädigt", "zh": "项目数据库可能已损坏", "ja": "プロジェクトデータベースが破損している可能性があります", "ko": "프로젝트 데이터베이스가 손상되었을 수 있습니다", "pt": "A base de dados do projeto pode estar danificada", "ar": "قد تكون قاعدة بيانات المشروع تالفة"],
        "locNoBackupFound": ["en": "No backup found for this project — the database was not restored.", "ru": "Резервная копия проекта не найдена — база данных не восстановлена.", "es": "No se encontró ninguna copia de seguridad — la base de datos no se restauró.", "fr": "Aucune sauvegarde trouvée — la base de données n’a pas été restaurée.", "de": "Keine Sicherung für dieses Projekt gefunden — die Datenbank wurde nicht wiederhergestellt.", "zh": "未找到此项目的备份 — 数据库未恢复。", "ja": "このプロジェクトのバックアップが見つからないため、データベースは復元されませんでした。", "ko": "이 프로젝트의 백업을 찾지 못해 데이터베이스를 복원하지 않았습니다.", "pt": "Não foi encontrada uma cópia de segurança — a base de dados não foi restaurada.", "ar": "لم يتم العثور على نسخة احتياطية لهذا المشروع — لم تتم استعادة قاعدة البيانات."],
        "locDatabaseRestored": ["en": "Database restored from the latest backup.", "ru": "База данных восстановлена из последней резервной копии.", "es": "Base de datos restaurada desde la última copia de seguridad.", "fr": "Base de données restaurée depuis la dernière sauvegarde.", "de": "Datenbank aus der neuesten Sicherung wiederhergestellt.", "zh": "已从最新备份恢复数据库。", "ja": "最新のバックアップからデータベースを復元しました。", "ko": "최신 백업에서 데이터베이스를 복원했습니다.", "pt": "Base de dados restaurada a partir da cópia de segurança mais recente.", "ar": "تمت استعادة قاعدة البيانات من أحدث نسخة احتياطية."],
        "locRestoreFailed": ["en": "Restore failed: %@", "ru": "Восстановление не удалось: %@", "es": "La restauración falló: %@", "fr": "Échec de la restauration : %@", "de": "Wiederherstellung fehlgeschlagen: %@", "zh": "恢复失败：%@", "ja": "復元に失敗しました: %@", "ko": "복원 실패: %@", "pt": "Falha na restauração: %@", "ar": "فشلت الاستعادة: %@"],
        "locIntegrityCheckFailed": ["en": "%@\n\nOpening this project failed its database integrity check. The latest auto-backup can be restored.", "ru": "%@\n\nПри открытии проекта проверка целостности базы данных не пройдена. Можно восстановить последнюю резервную копию.", "es": "%@\n\nNo se superó la comprobación de integridad al abrir el proyecto. Se puede restaurar la última copia automática.", "fr": "%@\n\nL’ouverture du projet a échoué à la vérification d’intégrité. La dernière sauvegarde automatique peut être restaurée.", "de": "%@\n\nBeim Öffnen des Projekts ist die Integritätsprüfung fehlgeschlagen. Die neueste automatische Sicherung kann wiederhergestellt werden.", "zh": "%@\n\n打开项目时数据库完整性检查失败。可以恢复最新的自动备份。", "ja": "%@\n\nプロジェクトを開く際のデータベース整合性チェックに失敗しました。最新の自動バックアップを復元できます。", "ko": "%@\n\n프로젝트를 열 때 데이터베이스 무결성 검사를 통과하지 못했습니다. 최신 자동 백업을 복원할 수 있습니다.", "pt": "%@\n\nA verificação de integridade da base de dados falhou ao abrir o projeto. É possível restaurar a cópia automática mais recente.", "ar": "%@\n\nفشل فحص سلامة قاعدة البيانات عند فتح المشروع. يمكن استعادة أحدث نسخة احتياطية تلقائية."],
        "locProjectPathPlaceholder": ["en": "/Path/to/project", "ru": "/Путь/к/проекту", "es": "/Ruta/al/proyecto", "fr": "/Chemin/vers/projet", "de": "/Pfad/zum/Projekt", "zh": "/项目/路径", "ja": "/プロジェクト/への/パス", "ko": "/프로젝트/경로", "pt": "/Caminho/para/projeto", "ar": "/مسار/إلى/المشروع"],
        "locChooseProjectFolder": ["en": "Choose project folder", "ru": "Выбрать папку проекта", "es": "Elegir carpeta del proyecto", "fr": "Choisir le dossier du projet", "de": "Projektordner wählen", "zh": "选择项目文件夹", "ja": "プロジェクトフォルダを選択", "ko": "프로젝트 폴더 선택", "pt": "Escolher pasta do projeto", "ar": "اختيار مجلد المشروع"],
        "locActions": ["en": "Actions", "ru": "Действия", "es": "Acciones", "fr": "Actions", "de": "Aktionen", "zh": "操作", "ja": "アクション", "ko": "동작", "pt": "Ações", "ar": "الإجراءات"],
        "locFreeModelRateLimitMessage": ["en": "%@ reached its rate limit. myCoder switched to %@.", "ru": "Для %@ достигнут лимит. myCoder переключился на %@.", "es": "%@ alcanzó su límite. myCoder cambió a %@.", "fr": "%@ a atteint sa limite. myCoder est passé à %@.", "de": "%@ hat sein Ratenlimit erreicht. myCoder wechselte zu %@.", "zh": "%@ 达到速率限制。myCoder 已切换到 %@。", "ja": "%@がレート制限に達しました。MyCoderは%@に切り替えました。", "ko": "%@이(가) 속도 제한에 도달했습니다. MyCoder가 %@로 전환했습니다.", "pt": "%@ atingiu o limite de taxa. O myCoder mudou para %@.", "ar": "بلغ %@ حد المعدل. بدّل myCoder إلى %@."],
        "locFreeModelSwitchedMessage": ["en": "%@ was unavailable (%@). myCoder switched to %@.", "ru": "%@ недоступна (%@). myCoder переключился на %@.", "es": "%@ no estaba disponible (%@). myCoder cambió a %@.", "fr": "%@ était indisponible (%@). myCoder est passé à %@.", "de": "%@ war nicht verfügbar (%@). myCoder wechselte zu %@.", "zh": "%@ 不可用（%@）。myCoder 已切换到 %@。", "ja": "%@は利用できません（%@）。MyCoderは%@に切り替えました。", "ko": "%@을(를) 사용할 수 없습니다(%@). MyCoder가 %@로 전환했습니다.", "pt": "%@ estava indisponível (%@). O myCoder mudou para %@.", "ar": "%@ غير متاح (%@). بدّل myCoder إلى %@."],
        "locTaskCompleteMessage": ["en": "\"%@\" has finished processing.", "ru": "Задача «%@» завершила обработку.", "es": "«%@» ha terminado de procesarse.", "fr": "« %@ » a terminé son traitement.", "de": "„%@“ wurde fertig verarbeitet.", "zh": "“%@” 已完成处理。", "ja": "「%@」の処理が完了しました。", "ko": "“%@” 처리가 완료되었습니다.", "pt": "«%@» terminou o processamento.", "ar": "اكتملت معالجة «%@»."],
        "locGitOperation": ["en": "Git %@", "ru": "Git %@", "es": "Git %@", "fr": "Git %@", "de": "Git %@", "zh": "Git %@", "ja": "Git %@", "ko": "Git %@", "pt": "Git %@", "ar": "Git %@"],
        "locPreviousModel": ["en": "previous model", "ru": "предыдущая модель", "es": "modelo anterior", "fr": "modèle précédent", "de": "vorheriges Modell", "zh": "上一个模型", "ja": "前のモデル", "ko": "이전 모델", "pt": "modelo anterior", "ar": "النموذج السابق"],
        "locAnotherFreeModel": ["en": "another free model", "ru": "другая бесплатная модель", "es": "otro modelo gratuito", "fr": "un autre modèle gratuit", "de": "ein anderes kostenloses Modell", "zh": "另一个免费模型", "ja": "別の無料モデル", "ko": "다른 무료 모델", "pt": "outro modelo gratuito", "ar": "نموذج مجاني آخر"],
        "locProviderError": ["en": "provider error", "ru": "ошибка провайдера", "es": "error del proveedor", "fr": "erreur du fournisseur", "de": "Anbieterfehler", "zh": "提供商错误", "ja": "プロバイダーエラー", "ko": "공급자 오류", "pt": "erro do fornecedor", "ar": "خطأ في الموفر"],
        "locFreeModelRateLimited": ["en": "Free model rate limited", "ru": "Для бесплатной модели сработал лимит", "es": "Límite de velocidad del modelo gratuito", "fr": "Limite de débit du modèle gratuit", "de": "Ratenlimit des kostenlosen Modells erreicht", "zh": "免费模型触发速率限制", "ja": "無料モデルのレート制限", "ko": "무료 모델 속도 제한", "pt": "Limite de taxa do modelo gratuito", "ar": "تم بلوغ حد معدل النموذج المجاني"],
        "locServerDisconnected": ["en": "Server Disconnected", "ru": "Сервер отключён", "es": "Servidor desconectado", "fr": "Serveur déconnecté", "de": "Server getrennt", "zh": "服务器已断开", "ja": "サーバー切断", "ko": "서버 연결 끊김", "pt": "Servidor desligado", "ar": "تم قطع اتصال الخادم"],
        "locServerConnected": ["en": "Server Connected", "ru": "Сервер подключён", "es": "Servidor conectado", "fr": "Serveur connecté", "de": "Server verbunden", "zh": "服务器已连接", "ja": "サーバー接続済み", "ko": "서버接続済み", "pt": "Servidor ligado", "ar": "تم اتصال الخادم"],
        "locSessionBusy": ["en": "Session Busy", "ru": "Сессия занята", "es": "Sesión ocupada", "fr": "Session occupée", "de": "Sitzung beschäftigt", "zh": "会话繁忙", "ja": "セッション使用中", "ko": "세션 사용 중", "pt": "Sessão ocupada", "ar": "الجلسة مشغولة"],
        "locNewBranchName": ["en": "Enter a name for the new branch. Current branch: %@", "ru": "Введите имя новой ветки. Текущая ветка: %@", "es": "Introduce un nombre para la nueva rama. Rama actual: %@", "fr": "Saisissez le nom de la nouvelle branche. Branche actuelle : %@", "de": "Geben Sie einen Namen für den neuen Branch ein. Aktueller Branch: %@", "zh": "输入新分支名称。当前分支：%@", "ja": "新しいブランチ名を入力してください。現在のブランチ: %@", "ko": "새 브랜치 이름을 입력하세요. 현재 브랜치: %@", "pt": "Introduza um nome para o novo ramo. Ramo atual: %@", "ar": "أدخل اسم الفرع الجديد. الفرع الحالي: %@"],
        "locFileAttached": ["en": "%d file", "ru": "%d файл", "es": "%d archivo", "fr": "%d fichier", "de": "%d Datei", "zh": "%d 个文件", "ja": "%dファイル", "ko": "%d개 파일", "pt": "%d ficheiro", "ar": "%d ملف"],
        "locFilesAttached": ["en": "%d files", "ru": "%d файла", "es": "%d archivos", "fr": "%d fichiers", "de": "%d Dateien", "zh": "%d 个文件", "ja": "%dファイル", "ko": "%d개 파일", "pt": "%d ficheiros", "ar": "%d ملفات"],
        "locPhotoAttached": ["en": "%d photo", "ru": "%d фото", "es": "%d foto", "fr": "%d photo", "de": "%d Foto", "zh": "%d 张照片", "ja": "%d枚の写真", "ko": "%d개 사진", "pt": "%d fotografia", "ar": "%d صورة"],
        "locPhotosAttached": ["en": "%d photos", "ru": "%d фото", "es": "%d fotos", "fr": "%d photos", "de": "%d Fotos", "zh": "%d 张照片", "ja": "%d枚の写真", "ko": "%d개 사진", "pt": "%d fotografias", "ar": "%d صور"],
        "locCookiesCount": ["en": "%d cookies", "ru": "%d cookies", "es": "%d cookies", "fr": "%d cookies", "de": "%d Cookies", "zh": "%d 个 Cookie", "ja": "%d個のCookie", "ko": "%d개 쿠키", "pt": "%d cookies", "ar": "%d ملفات تعريف ارتباط"],
        "locWebModelsFoundCount": ["en": "%d models found", "ru": "Найдено моделей: %d", "es": "%d modelos encontrados", "fr": "%d modèles trouvés", "de": "%d Modelle gefunden", "zh": "找到 %d 个模型", "ja": "%dモデルが見つかりました", "ko": "%d개 모델 발견", "pt": "%d modelos encontrados", "ar": "تم العثور على %d نموذج"],
        "locApiEndpointURL": ["en": "API endpoint URL", "ru": "URL эндпоинта API", "es": "URL del endpoint de API", "fr": "URL du point de terminaison API", "de": "API-Endpunkt-URL", "zh": "API 端点 URL", "ja": "APIエンドポイントURL", "ko": "API 엔드포인트 URL", "pt": "URL do endpoint da API", "ar": "عنوان URL لنقطة API"],
        "locInvalidEndpoint": ["en": "Enter a valid http:// or https:// endpoint without a query string.", "ru": "Введите корректный эндпоинт http:// или https:// без строки запроса.", "es": "Introduce un endpoint http:// o https:// válido sin cadena de consulta.", "fr": "Saisissez un endpoint http:// ou https:// valide sans chaîne de requête.", "de": "Geben Sie einen gültigen http://- oder https://-Endpunkt ohne Abfragezeichenfolge ein.", "zh": "请输入不带查询字符串的有效 http:// 或 https:// 端点。", "ja": "クエリ文字列なしの有効なhttp://またはhttps://エンドポイントを入力してください。", "ko": "쿼리 문자열이 없는 유효한 http:// 또는 https:// 엔드포인트를 입력하세요.", "pt": "Introduza um endpoint http:// ou https:// válido sem cadeia de consulta.", "ar": "أدخل نقطة نهاية http:// أو https:// صالحة بدون سلسلة استعلام."],
        "locNoZenKeyDescription": ["en": "No key: temporary free chat models only. A Zen key enables the curated paid chat-compatible catalog.", "ru": "Без ключа: только временные бесплатные модели чата. Ключ Zen открывает отобранный платный каталог совместимых чат-моделей.", "es": "Sin clave: solo modelos de chat gratuitos temporales. Una clave Zen activa el catálogo seleccionado de modelos de chat de pago.", "fr": "Sans clé : uniquement des modèles de chat gratuits temporaires. Une clé Zen active le catalogue payant sélectionné compatible avec le chat.", "de": "Ohne Schlüssel: nur temporäre kostenlose Chat-Modelle. Ein Zen-Schlüssel aktiviert den kuratierten kostenpflichtigen Chat-Katalog.", "zh": "无密钥：仅提供临时免费聊天模型。Zen 密钥可启用精选的付费聊天兼容模型目录。", "ja": "キーなし: 一時的な無料チャットモデルのみ。Zenキーで厳選された有料チャット対応カタログを有効にできます。", "ko": "키 없음: 임시 무료 채팅 모델만 사용합니다. Zen 키를 사용하면 엄선된 유료 채팅 호환 카탈로그가 활성화됩니다.", "pt": "Sem chave: apenas modelos de chat gratuitos temporários. Uma chave Zen ativa o catálogo selecionado de modelos de chat pagos compatíveis.", "ar": "بدون مفتاح: نماذج دردشة مجانية مؤقتة فقط. يتيح مفتاح Zen كتالوج النماذج المدفوعة المتوافقة مع الدردشة."],
        "locOpenCodeZen": ["en": "OpenCode Zen", "ru": "OpenCode Zen", "es": "OpenCode Zen", "fr": "OpenCode Zen", "de": "OpenCode Zen", "zh": "OpenCode Zen", "ja": "OpenCode Zen", "ko": "OpenCode Zen", "pt": "OpenCode Zen", "ar": "OpenCode Zen"],
        "locMessagesCount": ["en": "%d msg", "ru": "%d сообщ.", "es": "%d msj.", "fr": "%d msg", "de": "%d Nachr.", "zh": "%d 条消息", "ja": "%d件", "ko": "%d개 메시지", "pt": "%d msg", "ar": "%d رسالة"],
        "locCustomProviders": ["en": "Custom providers", "ru": "Пользовательские провайдеры", "es": "Proveedores personalizados", "fr": "Fournisseurs personnalisés", "de": "Benutzerdefinierte Anbieter", "zh": "自定义提供商", "ja": "カスタムプロバイダー", "ko": "사용자 정의 공급자", "pt": "Provedores personalizados", "ar": "مزودون مخصصون"],
        "locBuiltInProviders": ["en": "Built-in providers", "ru": "Встроенные провайдеры", "es": "Proveedores integrados", "fr": "Fournisseurs intégrés", "de": "Integrierte Anbieter", "zh": "内置提供商", "ja": "組み込みプロバイダー", "ko": "내장 공급자", "pt": "Provedores integrados", "ar": "المزودون المدمجون"],
        "locAddOrSelectOpenCodeZen": ["en": "Add or select OpenCode Zen", "ru": "Добавить или выбрать OpenCode Zen", "es": "Añadir o seleccionar OpenCode Zen", "fr": "Ajouter ou sélectionner OpenCode Zen", "de": "OpenCode Zen hinzufügen oder auswählen", "zh": "添加或选择 OpenCode Zen", "ja": "OpenCode Zenを追加または選択", "ko": "OpenCode Zen 추가 또는 선택", "pt": "Adicionar ou selecionar OpenCode Zen", "ar": "إضافة أو اختيار OpenCode Zen"],
        "locOpenCodeZenApiKeyOptional": ["en": "OpenCode Zen API key (optional)", "ru": "API-ключ OpenCode Zen (необязательно)", "es": "Clave API de OpenCode Zen (opcional)", "fr": "Clé API OpenCode Zen (facultative)", "de": "OpenCode-Zen-API-Schlüssel (optional)", "zh": "OpenCode Zen API 密钥（可选）", "ja": "OpenCode Zen APIキー（任意）", "ko": "OpenCode Zen API 키(선택 사항)", "pt": "Chave API OpenCode Zen (opcional)", "ar": "مفتاح OpenCode Zen API (اختياري)"],
        "locSecretKeyPlaceholder": ["en": "Secret key", "ru": "Секретный ключ", "es": "Clave secreta", "fr": "Clé secrète", "de": "Geheimer Schlüssel", "zh": "密钥", "ja": "シークレットキー", "ko": "비밀 키", "pt": "Chave secreta", "ar": "المفتاح السري"],
        "locConnectedLocalAgent": ["en": "Connected to the local agent successfully.", "ru": "Успешное подключение к локальному агенту.", "es": "Conectado correctamente al agente local.", "fr": "Connexion réussie à l’agent local.", "de": "Erfolgreich mit dem lokalen Agenten verbunden.", "zh": "已成功连接到本地代理。", "ja": "ローカルエージェントに正常に接続しました。", "ko": "로컬 에이전트에 성공적으로 연결되었습니다.", "pt": "Ligação ao agente local efetuada com sucesso.", "ar": "تم الاتصال بالوكيل المحلي بنجاح."],
        "locLocalAgentConnectionLost": ["en": "Connection to the local agent was lost.", "ru": "Соединение с локальным агентом потеряно.", "es": "Se perdió la conexión con el agente local.", "fr": "La connexion à l’agent local a été perdue.", "de": "Die Verbindung zum lokalen Agenten wurde unterbrochen.", "zh": "与本地代理的连接已丢失。", "ja": "ローカルエージェントとの接続が失われました。", "ko": "로컬 에이전트 연결이 끊겼습니다.", "pt": "A ligação ao agente local foi perdida.", "ar": "فُقد الاتصال بالوكيل المحلي."],
        "locResponseStopped": ["en": "The AI response was stopped by the user.", "ru": "Пользователь остановил ответ ИИ.", "es": "El usuario detuvo la respuesta de IA.", "fr": "La réponse de l’IA a été arrêtée par l’utilisateur.", "de": "Die KI-Antwort wurde vom Benutzer gestoppt.", "zh": "用户已停止 AI 响应。", "ja": "ユーザーがAI応答を停止しました。", "ko": "사용자가 AI 응답을 중지했습니다.", "pt": "A resposta da IA foi parada pelo utilizador.", "ar": "أوقف المستخدم استجابة الذكاء الاصطناعي."],
        "locSessionBusyMessage": ["en": "The session is processing another request. Please wait or stop current generation.", "ru": "Сессия обрабатывает другой запрос. Подождите или остановите текущую генерацию.", "es": "La sesión está procesando otra solicitud. Espera o detén la generación actual.", "fr": "La session traite une autre requête. Attendez ou arrêtez la génération actuelle.", "de": "Die Sitzung verarbeitet eine andere Anfrage. Warten Sie oder stoppen Sie die aktuelle Generierung.", "zh": "会话正在处理另一个请求。请等待或停止当前生成。", "ja": "セッションは別のリクエストを処理中です。待つか現在の生成を停止してください。", "ko": "세션이 다른 요청을 처리 중입니다. 기다리거나 현재 생성을 중지하세요.", "pt": "A sessão está a processar outro pedido. Aguarde ou pare a geração atual.", "ar": "تعالج الجلسة طلباً آخر. انتظر أو أوقف التوليد الحالي."],
        "locTaskComplete": ["en": "Task Complete", "ru": "Задача завершена", "es": "Tarea completada", "fr": "Tâche terminée", "de": "Aufgabe abgeschlossen", "zh": "任务完成", "ja": "タスク完了", "ko": "작업 완료", "pt": "Tarefa concluída", "ar": "اكتملت المهمة"],
        "locFreeModelSwitched": ["en": "Free model switched", "ru": "Бесплатная модель переключена", "es": "Modelo gratuito cambiado", "fr": "Modèle gratuit changé", "de": "Kostenloses Modell gewechselt", "zh": "已切换免费模型", "ja": "無料モデルを切り替えました", "ko": "무료 모델 전환됨", "pt": "Modelo gratuito alterado", "ar": "تم تبديل النموذج المجاني"],
        "locFind": ["en": "Find", "ru": "Найти", "es": "Buscar", "fr": "Rechercher", "de": "Finden", "zh": "查找", "ja": "検索", "ko": "찾기", "pt": "Encontrar", "ar": "بحث"],
        "locActive": ["en": "Active", "ru": "Активна", "es": "Activo", "fr": "Actif", "de": "Aktiv", "zh": "活跃", "ja": "アクティブ", "ko": "활성", "pt": "Ativo", "ar": "نشط"],
        "locClear": ["en": "Clear", "ru": "Очистить", "es": "Borrar", "fr": "Effacer", "de": "Löschen", "zh": "清除", "ja": "クリア", "ko": "지우기", "pt": "Limpar", "ar": "مسح"],
        "locHide": ["en": "Hide", "ru": "Скрыть", "es": "Ocultar", "fr": "Masquer", "de": "Ausblenden", "zh": "隐藏", "ja": "非表示", "ko": "숨기기", "pt": "Ocultar", "ar": "إخفاء"],
        "locShow": ["en": "Show", "ru": "Показать", "es": "Mostrar", "fr": "Afficher", "de": "Anzeigen", "zh": "显示", "ja": "表示", "ko": "표시", "pt": "Mostrar", "ar": "إظهار"],
    ]
}
