import SwiftUI
import AppKit

struct NewProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var projectName = ""
    @State private var projectPath = ""
    @State private var showFolderPicker = false
    @State private var validationError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.projectCreationMode == .wizard
                         ? L.t("Project setup")
                         : L.t(AppLocalizationKey.locNewProject))
                        .interfaceFont(size: 18, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    if appState.projectCreationMode == .wizard {
                        Text(L.t("Next: choose models, describe the project and answer questions. Chat opens when setup is finished."))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            
            // Project name
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(AppLocalizationKey.locProjectName))
                    .interfaceFont(size: 12, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                TextField(L.t(AppLocalizationKey.locMyProject), text: $projectName)
                    .zcodeTextFieldStyle()
                    .interfaceFont(size: 13)
            }
            
            // Folder picker
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(AppLocalizationKey.locFolder))
                    .interfaceFont(size: 12, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                
                HStack(spacing: 8) {
                    TextField(L.t(AppLocalizationKey.locProjectPathPlaceholder), text: $projectPath)
                        .zcodeTextFieldStyle()
                        .interfaceFont(size: 13)
                    
                    Button(action: selectFolder) {
                        Image(systemName: "folder")
                            .interfaceFont(size: 14)
                            .foregroundColor(Color.mimo.textSecondary)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t(AppLocalizationKey.locChooseFolder))
                }
                if let validationError {
                    Text(validationError)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button(L.t(AppLocalizationKey.locCancel)) {
                    dismiss()
                }
                .interfaceFont(size: 13)
                .foregroundColor(Color.mimo.textSecondary)
                
                Spacer()
                
                Button(action: createProject) {
                    Text(L.t(AppLocalizationKey.locCreateProject))
                        .interfaceFont(size: 13, weight: .medium)
                }
                .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty || projectPath.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(Color.mimo.brand)
            }
        }
        .padding(24)
        .frame(width: 460, height: appState.projectCreationMode == .wizard ? 320 : 270)
        .background(Color.mimo.background)
        .onSubmit {
            createProject()
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = L.t(AppLocalizationKey.locChooseProjectFolder)
        panel.prompt = L.t(AppLocalizationKey.locSelect)
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectPath = url.path
        validationError = nil
        
        if projectName.isEmpty {
            projectName = url.lastPathComponent
        }
    }
    
    private func createProject() {
        let result = NewProjectValidationLogic.validate(
            name: projectName,
            path: projectPath,
            fileExists: { path in
                FileManager.default.fileExists(atPath: path)
            },
            isDirectory: { path in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                    return false
                }
                return isDirectory.boolValue
            }
        )
        switch result {
        case .valid(let name, let path):
            validationError = nil
            appState.createNewProject(name: name, path: path)
            if appState.projectCreationMode == .wizard {
                appState.openSpecWizard(for: path)
            }
            dismiss()
        case .invalid(let issue):
            validationError = issue.message
        }
    }
}
