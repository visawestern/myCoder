import Testing
import Foundation
@testable import myCoder

/// Планирование сброса хранилища: состав путей для каждого сценария,
/// дедупликация, сводка и нормализация идентификаторов проекта.
@Suite("План сброса хранилища (StorageResetLogic)")
struct StorageResetLogicPlanTests {

    private let home = URL(fileURLWithPath: "/tmp/fake-home")

    @Test("appCacheOnly удаляет только глобальную БД")
    func appCacheOnlyDeletesGlobalDB() {
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: home)
        #expect(plan.scope == .appCacheOnly)
        #expect(plan.deletesPaths.contains(MyCoderPaths.globalDatabaseURL(homeDirectory: home).path))
        #expect(plan.deletesPaths.count == 1)
    }

    @Test("fullDatabase добавляет реестр, проектные БД и папку projects")
    func fullDatabaseDeletesEverything() {
        let projectPaths = ["/tmp/proj-a", "/tmp/proj-b"]
        let plan = StorageResetLogic.plan(for: .fullDatabase, homeDirectory: home, projectPaths: projectPaths)
        #expect(plan.deletesPaths.contains(MyCoderPaths.globalDatabaseURL(homeDirectory: home).path))
        #expect(plan.deletesPaths.contains(MyCoderPaths.registryURL(homeDirectory: home).path))
        for project in projectPaths {
            #expect(plan.deletesPaths.contains(
                MyCoderPaths.projectDataDir(projectPath: project)
                    .appendingPathComponent("project.db").path
            ))
        }
        #expect(plan.deletesPaths.contains(
            MyCoderPaths.appDir(homeDirectory: home)
                .appendingPathComponent("projects", isDirectory: true).path
        ))
    }

    @Test("fullDatabase дедуплицирует совпадающие пути")
    func fullDatabaseDeduplicates() {
        let plan = StorageResetLogic.plan(
            for: .fullDatabase,
            homeDirectory: home,
            projectPaths: ["/tmp/proj-a", "/tmp/proj-a"]
        )
        #expect(plan.deletesPaths.count == Set(plan.deletesPaths).count)
    }

    @Test("Сводка перечисляет все пути")
    func summaryListsPaths() {
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: home)
        let summary = StorageResetLogic.summary(for: plan)
        #expect(summary.contains("  - \(plan.deletesPaths[0])"))
    }

    @Test("Идентификатор проекта канонизирует путь")
    func projectIDCanonicalization() {
        #expect(IdentifierNormalization.projectID(for: "/tmp/a/") == "/tmp/a")
        #expect(IdentifierNormalization.projectID(for: "/tmp/a") == "/tmp/a")
        #expect(IdentifierNormalization.sameProject("/tmp/a/", "/tmp/a"))
        #expect(!IdentifierNormalization.sameProject("/tmp/a", "/tmp/b"))
    }
}
