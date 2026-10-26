#!/bin/bash
# Quick re-sync of the Foundation-only test package and run tests.
# Usage: scripts/test-logic.sh [swift test args]
#
# NOTE (Round 7): this legacy script hard-codes a whitelist of files and can
# drift from the tree. Prefer scripts/logic-harness.sh, which AUTO-DISCOVERS
# every Foundation-only source/test file and writes ground-truth counts to
# EVAL.md. This script is kept only for a fast local subset run.
set -e
export PATH=/opt/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH
REPO=~/.cache/openresearch/repos/visawestern/myCoder
PKG=/tmp/opencode/mimo-logic-test

# Recreate the ephemeral package skeleton if /tmp was cleared.
mkdir -p "$PKG/Sources/MiMoLogic" "$PKG/Tests/MiMoLogicTests"
[ -d "$PKG/Sources/MiMoLogic/Resources" ] || cp -r "$REPO/myCoder/Sources/Resources" "$PKG/Sources/MiMoLogic/Resources"
if [ ! -f "$PKG/Package.swift" ]; then
cat > "$PKG/Package.swift" <<'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "myCoder",
    platforms: [.macOS(.v13)],
    products: [.library(name: "myCoder", targets: ["MyCoder"])],
    targets: [
        .target(name: "myCoder", path: "Sources/MiMoLogic", resources: [.process("Resources")]),
        .testTarget(name: "myCoderTests", dependencies: ["myCoder"], path: "Tests/MiMoLogicTests")
    ]
)
PKGEOF
fi
# Test-only stub for PlusMenuItem (real one has UI deps).
cat > "$PKG/Sources/MiMoLogic/PlusMenuItemStub.swift" <<'STUBEOF'
import Foundation
enum PlusMenuItem: String, CaseIterable, Equatable {
    case addAttachment, addPhoto, insertMention, insertCommand, insertSession
}
STUBEOF

# Foundation-only source files (Services that import only Foundation)
SOURCES=(
  SidebarResizeLogic SlashCommandRegistry InputCommandTriggerLogic
  ProviderAutoDetector AgentResourceCatalog AgentResourceInstaller
  AgentResourcesLoader AgentResourceRegistryManager StorageResetLogic
  ACPMessageBuilder ACPMessageTypes
  WebProviderConfig WebToolProtocolEmulator WebSessionLogic WebPromptChunker WebProviderConnectivity WebModelListParser WebChatEventPresenter SendRouteResolver DirectChatClient ProjectWebToolExecutor ChatHistoryBuilder ProjectFilesCacheLogic
  BrowserAutomationBridge WebChatDriver WebSessionManager
  LocalProviderConfig ProviderOption SlashCommandExecutor ModelCallParameters DropdownKeyboardLogic LegacyDataMigrator InputDropdownDataSource SidebarGroupingLogic ProjectFileIndexLogic ProjectFileScanner UsageStatisticsAggregator ProjectRegistryLogic AppLocalization LanguagePickerLogic
)
# Files located under Models/ instead of Services/
MODEL_SOURCES=( SettingsTab Settings )
for f in "${SOURCES[@]}"; do
  ln -sf "$REPO/myCoder/Sources/Services/$f.swift" "$PKG/Sources/MiMoLogic/$f.swift"
done
for f in "${MODEL_SOURCES[@]}"; do
  ln -sf "$REPO/myCoder/Sources/Models/$f.swift" "$PKG/Sources/MiMoLogic/$f.swift"
done

# Foundation-only test files
TESTS=(
  SidebarResizeLogicTests SlashCommandRegistryTests InputCommandTriggerTests
  ProviderAutoDetectorTests AgentResourceInstallerTests
  AgentResourceRegistryManagerTests StorageResetLogicTests ACPMessageBuilderTests
  WebProviderTests WebChatDriverTests WebPromptChunkerTests WebProviderConnectivityTests WebModelListParserTests WebChatEventPresenterTests SendRoutingTests ProjectWebToolExecutorTests ChatHistoryBuilderTests ProjectFilesCacheLogicTests LocalProviderConfigTests SlashCommandExecutorTests ModelCallParametersTests DropdownKeyboardLogicTests LegacyDataMigratorTests InputDropdownDataSourceTests SidebarGroupingLogicTests ProjectFileIndexLogicTests ProjectFileScannerTests UsageStatisticsAggregatorTests ProjectRegistryLogicTests LanguagePickerLogicTests RepoRoot RepoRootTests
)
for f in "${TESTS[@]}"; do
  ln -sf "$REPO/myCoder/Tests/$f.swift" "$PKG/Tests/MiMoLogicTests/$f.swift"
done

cd "$PKG"
swift test --no-parallel "$@"
