import Foundation

enum NewProjectValidationIssue: Equatable {
    case emptyName
    case emptyPath
    case invalidPath
    case directoryNotFound
    case notDirectory

    var message: String {
        switch self {
        case .emptyName:
            return "Enter a project name."
        case .emptyPath:
            return "Choose a project folder."
        case .invalidPath:
            return "Project path must be an absolute path."
        case .directoryNotFound:
            return "The selected project folder does not exist. Choose an existing folder or create it first."
        case .notDirectory:
            return "The selected project path is a file, not a folder."
        }
    }
}

enum NewProjectValidationResult: Equatable {
    case valid(name: String, path: String)
    case invalid(NewProjectValidationIssue)
}

enum NewProjectValidationLogic {
    static func validate(
        name: String,
        path: String,
        fileExists: (String) -> Bool,
        isDirectory: (String) -> Bool
    ) -> NewProjectValidationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .invalid(.emptyName) }
        guard !trimmedPath.isEmpty else { return .invalid(.emptyPath) }
        guard trimmedPath.hasPrefix("/") else { return .invalid(.invalidPath) }
        guard fileExists(trimmedPath) else { return .invalid(.directoryNotFound) }
        guard isDirectory(trimmedPath) else { return .invalid(.notDirectory) }
        let normalizedPath = (trimmedPath as NSString).standardizingPath
        return .valid(name: trimmedName, path: (normalizedPath as NSString).resolvingSymlinksInPath)
    }
}
