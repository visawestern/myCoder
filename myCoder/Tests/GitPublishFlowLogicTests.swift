import Testing
@testable import myCoder

@Suite("Git Publish Flow Logic")
struct GitPublishFlowLogicTests {

    // MARK: - gh detection

    @Test("Finds gh at first existing search path")
    func findsGHAtFirstExistingPath() {
        let path = GitPublishFlowLogic.ghExecutablePath(
            searchPaths: ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"],
            fileExists: { $0 == "/usr/local/bin/gh" }
        )
        #expect(path == "/usr/local/bin/gh")
    }

    @Test("Returns nil when gh is not installed anywhere")
    func returnsNilWhenGHMissing() {
        let path = GitPublishFlowLogic.ghExecutablePath(
            searchPaths: ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"],
            fileExists: { _ in false }
        )
        #expect(path == nil)
    }

    @Test("Default search paths cover Homebrew ARM, Intel and system")
    func defaultSearchPathsCoverCommonLocations() {
        let paths = GitPublishFlowLogic.defaultGHSearchPaths
        #expect(paths.contains("/opt/homebrew/bin/gh"))
        #expect(paths.contains("/usr/local/bin/gh"))
    }

    // MARK: - status resolution

    @Test("Status is notInstalled when gh binary missing")
    func statusNotInstalled() {
        #expect(GitPublishFlowLogic.status(ghInstalled: false, authStatusExitCode: nil) == .notInstalled)
    }

    @Test("Status is notAuthenticated when auth status exits non-zero")
    func statusNotAuthenticated() {
        #expect(GitPublishFlowLogic.status(ghInstalled: true, authStatusExitCode: 1) == .notAuthenticated)
    }

    @Test("Status is ready when auth status exits zero")
    func statusReady() {
        #expect(GitPublishFlowLogic.status(ghInstalled: true, authStatusExitCode: 0) == .ready)
    }

    // MARK: - wizard step routing

    @Test("Wizard shows install step when CLI missing")
    func stepInstall() {
        #expect(GitPublishFlowLogic.step(for: .notInstalled) == .installCLI)
    }

    @Test("Wizard shows sign-in step when not authenticated")
    func stepSignIn() {
        #expect(GitPublishFlowLogic.step(for: .notAuthenticated) == .signIn)
    }

    @Test("Wizard shows publish form when ready")
    func stepPublishForm() {
        #expect(GitPublishFlowLogic.step(for: .ready) == .publishForm)
    }

    // MARK: - repo name

    @Test("Repo name suggestion sanitizes spaces and invalid characters")
    func sanitizesRepoName() {
        #expect(GitPublishFlowLogic.suggestedRepoName(from: "My Cool App!") == "My-Cool-App")
        #expect(GitPublishFlowLogic.suggestedRepoName(from: "mimo macos") == "mimo-macos")
        #expect(GitPublishFlowLogic.suggestedRepoName(from: "проект") == "проект")
    }

    @Test("Repo name suggestion collapses repeated separators")
    func collapsesRepeatedSeparators() {
        #expect(GitPublishFlowLogic.suggestedRepoName(from: "a  --  b") == "a-b")
    }

    @Test("Repo name suggestion falls back for empty input")
    func fallsBackForEmptyName() {
        #expect(GitPublishFlowLogic.suggestedRepoName(from: "!!!") == "new-project")
        #expect(GitPublishFlowLogic.suggestedRepoName(from: "") == "new-project")
    }

    @Test("Repo name validation rejects empty and accepts sane names")
    func validatesRepoName() {
        #expect(!GitPublishFlowLogic.isValidRepoName(""))
        #expect(!GitPublishFlowLogic.isValidRepoName("   "))
        #expect(GitPublishFlowLogic.isValidRepoName("mimo-macos"))
    }

    // MARK: - commands

    @Test("Create repo arguments include visibility, source and push")
    func createRepoArguments() {
        let publicArgs = GitPublishFlowLogic.createRepoArguments(repoName: "demo", isPublic: true)
        #expect(publicArgs == ["repo", "create", "demo", "--public", "--source=.", "--remote=origin", "--push"])

        let privateArgs = GitPublishFlowLogic.createRepoArguments(repoName: "demo", isPublic: false)
        #expect(privateArgs.contains("--private"))
    }

    @Test("Login arguments use non-interactive web flow with explicit host and protocol")
    func loginArguments() {
        #expect(GitPublishFlowLogic.loginArguments == [
            "auth", "login",
            "--hostname", "github.com",
            "--git-protocol", "https",
            "--web",
        ])
    }

    @Test("Install command uses Homebrew")
    func installCommand() {
        #expect(GitPublishFlowLogic.installCommand == "brew install gh")
    }

    @Test("Finds brew at first existing search path")
    func findsBrew() {
        let path = GitPublishFlowLogic.brewExecutablePath(
            searchPaths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
            fileExists: { $0 == "/opt/homebrew/bin/brew" }
        )
        #expect(path == "/opt/homebrew/bin/brew")
    }

    @Test("Returns nil when brew missing")
    func brewMissing() {
        let path = GitPublishFlowLogic.brewExecutablePath(
            searchPaths: ["/opt/homebrew/bin/brew"],
            fileExists: { _ in false }
        )
        #expect(path == nil)
    }

    @Test("Manual install docs URL points to GitHub CLI site")
    func manualInstallDocsURL() {
        #expect(GitPublishFlowLogic.manualInstallURL.absoluteString == "https://cli.github.com")
    }

    // MARK: - one-time code

    @Test("Extracts one-time code from gh auth login output")
    func extractsOneTimeCode() {
        let output = """
        ! First copy your one-time code: 1B2C-D3E4
        Press Enter to open github.com in your browser...
        """
        #expect(GitPublishFlowLogic.oneTimeCode(from: output) == "1B2C-D3E4")
    }

    @Test("One-time code is nil when output has none")
    func oneTimeCodeNilWhenMissing() {
        #expect(GitPublishFlowLogic.oneTimeCode(from: "Logging in...") == nil)
        #expect(GitPublishFlowLogic.oneTimeCode(from: "") == nil)
    }
}
