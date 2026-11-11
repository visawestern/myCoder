import SwiftUI
import Foundation
import AppKit
import Darwin

/// Global reference for local API server access. Set during app startup.
var __myCoderAppState: AppState?

/// One-shot coder prompt waiting for its chat history to finish loading.
/// AppState owns it so the wizard can start a task from any view.
struct PendingSpecNodePrompt: Equatable {
    let id: String
    let sessionID: String
    let text: String
}

@main
struct MyCoderApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(MyCoderAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    __myCoderAppState = appState
                    StuckCursorFix.install()
                    MyCoderAPIServer.shared.start()
                    // Движок AntiBrowser НЕ стартует при запуске приложения:
                    // он поднимается только по реальной надобности — вход в
                    // веб-провайдер, веб-чат или спецпоиск (browser_fetch).
                }
                .frame(minWidth: 900, idealWidth: 1200, maxWidth: .infinity,
                       minHeight: 600, idealHeight: 750, maxHeight: .infinity)
                .background(Color.mimo.background)
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button(L.t(AppLocalizationKey.locCut)) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button(L.t(AppLocalizationKey.locCopy)) {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button(L.t(AppLocalizationKey.locPaste)) {
                    _ = ChatPasteCoordinator.shared.performPaste()
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                // Replacing .pasteboard removes the standard Select All item;
                // re-add it or Cmd+A is dead in every text field.
                Button(L.t(AppLocalizationKey.locSelectAll)) {
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button(L.t(AppLocalizationKey.locNewTask)) {
                    appState.startNewTask(in: appState.selectedWorkspace)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu(L.t(AppLocalizationKey.locFind)) {
                Button(L.t(AppLocalizationKey.locSearchTasks)) {
                    appState.showSearch = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu(L.t(AppLocalizationKey.locActions)) {
                Button(L.t(AppLocalizationKey.locUndoLastFileChange)) {
                    appState.undoLastAction()
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(appState.selectedSession == nil)
            }
            CommandMenu("Скриншоты") {
                Button("Сохранить скриншот") {
                    Task { @MainActor in
                        do {
                            let info = try ScreenshotsStore.captureAndSave()
                            MyCoderAPIServer.appendLog("📸 screenshot saved: \(info.path)")
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: info.path)])
                        } catch {
                            MyCoderAPIServer.appendLog("📸 screenshot failed: \(error.localizedDescription)")
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Divider()
                Button("Открыть папку скриншотов") {
                    ScreenshotsStore.reveal()
                }
            }
        }
    }
}

enum ProjectCreationMode: String, CaseIterable {
    case empty
    case wizard
}
