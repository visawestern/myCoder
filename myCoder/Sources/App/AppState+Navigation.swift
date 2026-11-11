import Foundation
import SwiftUI
import AppKit

/// История переходов по рабочим областям.
extension AppState {
    /// Reset navigation to a safe state (used when the workspace is cleared,
    /// e.g. during a storage reset) so the UI can't observe an out-of-bounds
    /// index into navigationHistory. Internal so extensions (AppState+Database)
    /// can call it.
    func clearNavigationHistory() {
        navigationLock.lock()
        navigationHistory = []
        navigationIndex = -1
        navigationLock.unlock()
    }

    func navigateBack() {
        navigationLock.lock()
        guard navigationIndex > 0 else {
            navigationLock.unlock()
            return
        }
        navigationIndex -= 1
        let ws = navigationHistory[navigationIndex]
        isNavigatingHistory = true
        navigationLock.unlock()
        selectWorkspace(ws)
        navigationLock.lock()
        isNavigatingHistory = false
        navigationLock.unlock()
    }

    func navigateForward() {
        navigationLock.lock()
        guard navigationIndex < navigationHistory.count - 1 else {
            navigationLock.unlock()
            return
        }
        navigationIndex += 1
        let ws = navigationHistory[navigationIndex]
        isNavigatingHistory = true
        navigationLock.unlock()
        selectWorkspace(ws)
        navigationLock.lock()
        isNavigatingHistory = false
        navigationLock.unlock()
    }

    var canNavigateBack: Bool {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        return navigationIndex > 0 && navigationIndex < navigationHistory.count
    }

    var canNavigateForward: Bool {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        return navigationIndex < navigationHistory.count - 1 && navigationIndex >= 0 && navigationHistory.count > 0
    }
}
