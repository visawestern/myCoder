import Foundation

enum GitHubCLIStatus: Equatable {
    case notInstalled
    case notAuthenticated
    case ready
}

enum GitPublishStep: Equatable {
    case installCLI
    case signIn
    case publishForm
}

enum GitPublishFlowLogic {
    static let defaultGHSearchPaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    static let defaultBrewSearchPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    static let loginArguments = [
        "auth", "login",
        "--hostname", "github.com",
        "--git-protocol", "https",
        "--web",
    ]
    static let installCommand = "brew install gh"
    static let manualInstallURL = URL(string: "https://cli.github.com")!

    static func brewExecutablePath(
        searchPaths: [String] = defaultBrewSearchPaths,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        searchPaths.first(where: fileExists)
    }

    static func ghExecutablePath(
        searchPaths: [String] = defaultGHSearchPaths,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        searchPaths.first(where: fileExists)
    }

    static func status(ghInstalled: Bool, authStatusExitCode: Int32?) -> GitHubCLIStatus {
        guard ghInstalled else { return .notInstalled }
        guard authStatusExitCode == 0 else { return .notAuthenticated }
        return .ready
    }

    static func step(for status: GitHubCLIStatus) -> GitPublishStep {
        switch status {
        case .notInstalled: return .installCLI
        case .notAuthenticated: return .signIn
        case .ready: return .publishForm
        }
    }

    static func suggestedRepoName(from workspaceName: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_."))
        var scalars = String.UnicodeScalarView()
        for scalar in workspaceName.unicodeScalars {
            if allowed.contains(scalar) {
                scalars.append(scalar)
            } else {
                scalars.append("-")
            }
        }
        var name = String(scalars)
        while name.contains("--") {
            name = name.replacingOccurrences(of: "--", with: "-")
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return name.isEmpty ? "new-project" : name
    }

    static func isValidRepoName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Extracts the one-time device code (e.g. "1B2C-D3E4") from
    /// `gh auth login --web` output so it can be shown to the user.
    static func oneTimeCode(from output: String) -> String? {
        guard let range = output.range(
            of: #"[A-Z0-9]{4}-[A-Z0-9]{4}"#,
            options: .regularExpression
        ) else { return nil }
        return String(output[range])
    }

    static func createRepoArguments(repoName: String, isPublic: Bool) -> [String] {
        [
            "repo", "create", repoName,
            isPublic ? "--public" : "--private",
            "--source=.", "--remote=origin", "--push",
        ]
    }
}
