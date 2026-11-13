import Testing
import Foundation
@testable import myCoder

/// User requirement: a chat without a project must not silently write into the
/// home folder. Before the first file change the app asks to create a project
/// in a separate folder; the current turn stops with an honest refusal.
@MainActor
@Suite("Запись из чата без проекта — спросить и создать проект")
struct ProjectlessWriteLogicTests {

    private func tempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Файловые мутации требуют проект, чтение — нет")
    func onlyMutatingToolsRequireProject() {
        #expect(ProjectlessWriteLogic.requiresProject(toolName: "write_file"))
        #expect(ProjectlessWriteLogic.requiresProject(toolName: "edit_file"))
        #expect(!ProjectlessWriteLogic.requiresProject(toolName: "read_file"))
        #expect(!ProjectlessWriteLogic.requiresProject(toolName: "list_dir"))
        #expect(!ProjectlessWriteLogic.requiresProject(toolName: "run_command"))
    }

    @Test("Имя папки проекта выводится из имени файла")
    func suggestsFolderNameFromFile() {
        #expect(ProjectlessWriteLogic.suggestedProjectName(for: "aquarium_3d.html") == "aquarium_3d")
        #expect(ProjectlessWriteLogic.suggestedProjectName(for: "/Users/apple/aquarium_3d.html") == "aquarium_3d")
        #expect(ProjectlessWriteLogic.suggestedProjectName(for: "index.html") == "index")
        #expect(ProjectlessWriteLogic.suggestedProjectName(for: "") == "myCoder-project")
    }

    @Test("Standalone-чат считается чатом без проекта")
    func standaloneSessionIsProjectless() {
        #expect(ProjectlessWorkspaceLogic.isProjectless(sessionDirectory: ChatSession.standaloneProjectKey))
        #expect(ProjectlessWorkspaceLogic.isProjectless(sessionDirectory: nil))
        #expect(ProjectlessWorkspaceLogic.isProjectless(sessionDirectory: "   "))
        #expect(!ProjectlessWorkspaceLogic.isProjectless(sessionDirectory: "/Users/apple/projects/myCoder"))
    }

    @Test("Без ответа пользователя запись не выполняется и возвращается отказ")
    func writeIsRefusedWithoutPrompt() async throws {
        let home = try tempDir("home")
        defer { try? FileManager.default.removeItem(at: home) }
        let executor = ProjectWebToolExecutor(
            projectRoot: home.path,
            accessLevel: .fullAccess,
            isProjectless: true
        )
        let result = await executor.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "aquarium_3d.html", "content": "<html></html>"]
        ))
        #expect(result.contains("project_required"),
                "фактически: \(result) — ожидался отказ project_required")
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("aquarium_3d.html").path),
                "файл не должен появляться в домашней папке без проекта")
    }

    @Test("После создания проекта текущий ход продолжается в привязанном проекте")
    func createdProjectBindsAndContinues() async throws {
        let home = try tempDir("home")
        let project = try tempDir("project")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: project)
        }
        let executor = ProjectWebToolExecutor(
            projectRoot: home.path,
            accessLevel: .fullAccess,
            isProjectless: true,
            projectlessWritePrompt: { _ in project.path }
        )
        let result = await executor.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "aquarium_3d.html", "content": "<html></html>"]
        ))
        // Чат привязан к проекту: ответ содержит путь и указание продолжать
        // (никакого «открой новый чат»).
        #expect(result.contains(project.path),
                "фактически: \(result) — ожидался путь привязанного проекта")
        #expect(result.contains("bound"),
                "фактически: \(result) — ожидался статус привязки")
        #expect(result.contains("Continue"),
                "фактически: \(result) — модель должна продолжить работу")
        #expect(!result.contains("new chat opened"))
        // Сам ход не пишет молча ни в домашнюю папку, ни в новый проект:
        // модель узнаёт о привязке и повторяет вызов сама.
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("aquarium_3d.html").path))
        #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent("aquarium_3d.html").path))
    }

    @Test("В проекте запись работает как раньше")
    func projectWriteStillWorks() async throws {
        let project = try tempDir("project")
        defer { try? FileManager.default.removeItem(at: project) }
        let executor = ProjectWebToolExecutor(
            projectRoot: project.path,
            accessLevel: .fullAccess,
            isProjectless: false
        )
        let result = await executor.execute(WebToolCall(
            name: "write_file",
            arguments: ["path": "aquarium_3d.html", "content": "<html></html>"]
        ))
        #expect(result.hasPrefix("ok: wrote"), "фактически: \(result)")
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("aquarium_3d.html").path))
    }
}
