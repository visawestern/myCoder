import XCTest
@testable import myCoder

/// В режимах «План» и «Compose» запросы на безопасность/одобрения НЕ
/// показываются (директива 2026-10-30 + 2026-11-05): мутирующие тулы и
/// пишущие шелл-команды отклоняются без вопроса, а Read-only тулы
/// (включая читающие баш-команды) выполняются как обычно. Build-режим
/// не ограничен.
final class PlanModeToolPolicyTests: XCTestCase {

    private let readOnlyModes: [AgentMode] = [.plan, .compose]

    private func call(_ name: String, args: [String: String] = [:]) -> WebToolCall {
        WebToolCall(name: name, arguments: args)
    }

    // MARK: - Мутирующие тулы запрещены в plan/compose
    // (планировочные — только в plan, см. testPlanModeAllowsPlanTools)

    func testMutationsAreDeniedInPlanAndComposeWithoutPrompt() {
        let names = [
            "write_file", "edit_file", "patch", "write", "edit", "rename_file",
            "git_commit", "git_push", "git_pull", "git_checkout", "git_branch",
            "todo_write", "task_create", "task_update", "task",
        ]
        for name in names {
            let decision = PlanModeToolPolicy.decision(for: call(name), mode: .compose)
            guard case .deny(let reason) = decision else {
                return XCTFail("\(name) должен отклоняться в compose")
            }
            XCTAssertTrue(reason.contains("read-only"), "отказ должен объяснять read-only режим")
            XCTAssertTrue(reason.contains("build mode"), "отказ должен указывать на build режим")
        }
        // В plan-режиме мутации ФАЙЛОВ/ГИТА запрещены, но ведение плана
        // (task_*/todo_write) разрешено — проверяется отдельным тестом.
        let fileAndGitMutations = [
            "write_file", "edit_file", "patch", "write", "edit", "rename_file",
            "git_commit", "git_push", "git_pull", "git_checkout", "git_branch",
            "task",
        ]
        for name in fileAndGitMutations {
            let decision = PlanModeToolPolicy.decision(for: call(name), mode: .plan)
            guard case .deny(let reason) = decision else {
                return XCTFail("\(name) должен отклоняться в plan")
            }
            XCTAssertTrue(reason.contains("read-only"), "отказ должен объяснять read-only режим")
            XCTAssertTrue(reason.contains("build mode"), "отказ должен указывать на build режим")
        }
    }

    /// Директива 2026-11-08: в режиме «План» модель ведёт план — создание и
    /// обновление шагов плана (task_create/task_update/todo_write) разрешено.
    /// Запрещено только то, что изменяет состояние проекта: файлы, гит,
    /// шелл, сабагенты.
    func testPlanModeAllowsPlanTools() {
        let planTools = ["task_create", "task_update", "todo_write"]
        for name in planTools {
            XCTAssertEqual(
                PlanModeToolPolicy.decision(for: call(name), mode: .plan),
                .execute,
                "\(name) должен выполняться в plan (ведение плана)"
            )
            // В compose по-прежнему строгий read-only.
            XCTAssertEqual(
                PlanModeToolPolicy.decision(for: call(name), mode: .compose),
                .deny(reason: PlanModeToolPolicy.deniedReason),
                "\(name) должен отклоняться в compose"
            )
        }
    }

    // MARK: - run_command: пишущие запрещены, читающие разрешены

    func testMutatingRunCommandDeniedInPlanAndCompose() {
        let mutating = [
            "npm install", "touch file.txt", "rm -rf build", "git add .",
            "git commit -m x", "mkdir newdir", "echo hi > out.txt",
            "brew install python", "kill 123",
        ]
        for mode in readOnlyModes {
            for cmd in mutating {
                let decision = PlanModeToolPolicy.decision(
                    for: call("run_command", args: ["command": cmd]), mode: mode
                )
                XCTAssertEqual(decision, .deny(reason: PlanModeToolPolicy.deniedReason),
                               "\(cmd) должен отклоняться в \(mode.rawValue)")
            }
        }
    }

    func testReadOnlyRunCommandAllowedInPlanAndCompose() {
        let readOnly = [
            "pwd", "whoami", "uname -a", "echo hello", "printf 'x'",
            "ls -la", "cat Package.swift", "head -5 main.swift",
            "wc -l file.swift", "grep -r 'foo' src", "rg pattern",
            "git status", "git diff --stat", "git log --oneline -3",
            "git branch", "git stash list", "git remote -v",
            "git show --stat", "sed -n '1,5p' file.txt", "date",
            "df -h", "du -sh .", "which swift",
        ]
        for mode in readOnlyModes {
            for cmd in readOnly {
                let decision = PlanModeToolPolicy.decision(
                    for: call("run_command", args: ["command": cmd]), mode: mode
                )
                XCTAssertEqual(decision, .execute, "\(cmd) должен выполняться в \(mode.rawValue)")
            }
        }
    }

    // MARK: - Read-only тулы выполняются

    func testReadOnlyToolsExecuteInPlanAndCompose() {
        let names = [
            "read_file", "list_dir", "grep", "glob", "git_status", "git_log",
            "git_diff", "todo_read", "code_search", "read_symbol", "web_fetch",
            "browser_fetch", "skill", "task_list",
        ]
        for mode in readOnlyModes {
            for name in names {
                XCTAssertEqual(
                    PlanModeToolPolicy.decision(for: call(name), mode: mode),
                    .execute,
                    "\(name) должен выполняться в \(mode.rawValue)"
                )
            }
        }
    }

    // MARK: - Build ничего не запрещает

    func testBuildModeAlwaysExecutes() {
        for name in ["write_file", "edit_file", "read_file", "run_command", "git_commit"] {
            XCTAssertEqual(
                PlanModeToolPolicy.decision(for: call(name), mode: .build),
                .execute,
                "\(name) должен выполняться в build-режиме"
            )
        }
    }

    // MARK: - Неизвестные тулы fail closed в plan/compose

    func testUnknownToolFailsClosedInPlanAndCompose() {
        for mode in readOnlyModes {
            XCTAssertEqual(
                PlanModeToolPolicy.decision(for: call("unknown_tool"), mode: mode),
                .deny(reason: PlanModeToolPolicy.deniedReason)
            )
        }
    }
}
