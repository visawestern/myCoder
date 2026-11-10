import SwiftUI

extension SpecWizardContent {
    // MARK: Persistence

    func scheduleSave() {
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            saveState = session.saveDraft() ? .saved : .failed
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveState = session.saveDraft() ? .saved : .failed
    }

    func forceFinish() {
        guard session.finishWizard(forced: true) else { return }
        appState.finishSpecWizard(for: session.projectPath)
    }
}
