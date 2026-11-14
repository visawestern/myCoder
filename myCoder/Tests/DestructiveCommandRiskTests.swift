import Foundation
import Testing
@testable import myCoder

/// Инцидент 2026-11-14: `rsync --delete` по `api/` удалил прод-базу, а
/// `migrate --force` создал пустую — всё это на Full access, без единого
/// вопроса. Эти тесты фиксируют классификацию, которая заставляет показать
/// КРАСНУЮ карточку подтверждения даже при полном доступе.
@MainActor
@Suite("Destructive command risk (incident 2026-11-14)")
struct DestructiveCommandRiskTests {

    private func expectDestructive(_ command: String, reasonContains: String? = nil) {
        let risk = DestructiveCommandGuard.risk(for: command)
        #expect(risk.isDestructive, "должна быть деструктивной: \(command)")
        if let reasonContains {
            #expect(risk.reason?.lowercased().contains(reasonContains.lowercased()) == true,
                    "причина должна упоминать \(reasonContains): \(risk.reason ?? "nil")")
        }
    }

    private func expectSafe(_ command: String) {
        #expect(!DestructiveCommandGuard.risk(for: command).isDestructive,
                "не должна считаться деструктивной: \(command)")
    }

    // MARK: - Инцидент и его прямые родственники

    @Test("rsync --delete удаляет файлы на приёмнике")
    func rsyncDeleteIsDestructive() {
        expectDestructive("rsync -av --delete api/ prod:/srv/api/", reasonContains: "rsync")
        expectDestructive("rsync -a --delete-after build/ server:/var/www/", reasonContains: "rsync")
        expectDestructive("rsync -a --delete-before ./ user@host:/data/", reasonContains: "rsync")
        expectDestructive("rsync -a --remove-source-files ./ host:/data/", reasonContains: "rsync")
        expectSafe("rsync -av api/ prod:/srv/api/")
    }

    @Test("Миграции со сбросом базы деструктивны")
    func databaseMigrationsAreDestructive() {
        expectDestructive("php artisan migrate --force", reasonContains: "migrat")
        expectDestructive("php artisan migrate:fresh --seed", reasonContains: "migrat")
        expectDestructive("php artisan migrate:reset", reasonContains: "migrat")
        expectDestructive("php artisan db:wipe", reasonContains: "database")
        expectDestructive("migrate --force", reasonContains: "migrat")
        expectDestructive("npx prisma migrate reset --force", reasonContains: "migrat")
        expectDestructive("prisma db push --force-reset", reasonContains: "database")
        expectDestructive("supabase db reset", reasonContains: "database")
        expectDestructive("rails db:drop", reasonContains: "database")
        expectDestructive("rails db:schema:load", reasonContains: "database")
        expectDestructive("python manage.py flush", reasonContains: "database")
        expectDestructive("flyway clean", reasonContains: "database")
        expectDestructive("liquibase drop-all", reasonContains: "database")
        expectDestructive("sequelize db:drop", reasonContains: "database")
        expectDestructive("knex migrate:rollback --all", reasonContains: "migrat")
        expectSafe("php artisan migrate")
        expectSafe("npx prisma migrate dev")
    }

    @Test("SQL, стирающий данные, деструктивен")
    func destructiveSQLIsCaught() {
        expectDestructive("psql -c \"DROP DATABASE prod\"", reasonContains: "database")
        expectDestructive("psql -c 'drop table users;'", reasonContains: "database")
        expectDestructive("mysql -e \"TRUNCATE TABLE orders\"", reasonContains: "database")
        expectDestructive("redis-cli FLUSHALL", reasonContains: "database")
        expectDestructive("mysql -e \"DELETE FROM users\"", reasonContains: "database")
        expectDestructive("mysql -e \"UPDATE users SET admin = 1\"", reasonContains: "database")
        expectDestructive("mysql prod < dump.sql", reasonContains: "database")
        expectSafe("mysql -e \"DELETE FROM users WHERE id = 1\"")
        expectSafe("mysql -e \"UPDATE users SET admin = 1 WHERE id = 1\"")
        expectSafe("psql -c 'SELECT * FROM users'")
    }

    // MARK: - Удаление файлов

    @Test("rm -rf и рекурсивные/шаблонные удаления деструктивны")
    func recursiveDeletionIsDestructive() {
        expectDestructive("rm -rf build", reasonContains: "delet")
        expectDestructive("rm -fr /tmp/x", reasonContains: "delet")
        expectDestructive("rm -r logs", reasonContains: "delet")
        expectDestructive("rm -f *.log", reasonContains: "delet")
        expectDestructive("rm *", reasonContains: "delet")
        expectDestructive("find . -name '*.log' -delete", reasonContains: "delet")
        expectDestructive("find . -name '*.tmp' -exec rm {} \\;", reasonContains: "delet")
        expectDestructive("shred -u secret.key", reasonContains: "delet")
        expectDestructive("truncate -s 0 prod.db", reasonContains: "overwrit")
        expectDestructive("dd if=/dev/zero of=prod.db bs=1m count=10", reasonContains: "overwrit")
        expectSafe("rm file.txt")
        expectSafe("rm -f file.txt")
    }

    // MARK: - Git

    @Test("Перезапись истории git деструктивна")
    func destructiveGitIsCaught() {
        expectDestructive("git push --force origin main", reasonContains: "git")
        expectDestructive("git push -f", reasonContains: "git")
        expectDestructive("git push --force-with-lease", reasonContains: "git")
        expectDestructive("git push --delete origin old-branch", reasonContains: "git")
        expectDestructive("git reset --hard HEAD~3", reasonContains: "git")
        expectDestructive("git clean -fdx", reasonContains: "git")
        expectDestructive("git branch -D feature", reasonContains: "git")
        expectDestructive("git stash drop", reasonContains: "git")
        expectDestructive("git stash clear", reasonContains: "git")
        expectDestructive("git restore src/", reasonContains: "git")
        expectDestructive("git checkout -- .", reasonContains: "git")
        expectDestructive("git filter-branch --force", reasonContains: "git")
        expectSafe("git push origin main")
        expectSafe("git status")
        expectSafe("git reset HEAD file.txt")
        expectSafe("git reset --soft HEAD~1")
        expectSafe("git clean -n")
        expectSafe("git checkout main")
        expectSafe("git commit -m 'fix: rsync --delete bug'")
    }

    // MARK: - Инфраструктура

    @Test("Инфраструктурные удаления деструктивны")
    func infrastructureDestructionIsCaught() {
        expectDestructive("terraform destroy -auto-approve", reasonContains: "infrastructure")
        expectDestructive("terraform apply -destroy", reasonContains: "infrastructure")
        expectDestructive("kubectl delete namespace prod", reasonContains: "kubernetes")
        expectDestructive("helm uninstall my-release", reasonContains: "kubernetes")
        expectDestructive("docker system prune -af", reasonContains: "docker")
        expectDestructive("docker volume rm pgdata", reasonContains: "docker")
        expectDestructive("docker compose down -v", reasonContains: "docker")
        expectDestructive("aws s3 rm s3://bucket --recursive", reasonContains: "aws")
        expectDestructive("aws s3 rb s3://bucket --force", reasonContains: "aws")
        expectDestructive("heroku pg:reset DATABASE_URL", reasonContains: "heroku")
        expectDestructive("firebase firestore:delete --all-collections", reasonContains: "firebase")
        expectSafe("terraform plan")
        expectSafe("kubectl get pods")
        expectSafe("helm list")
        expectSafe("docker ps")
        expectSafe("aws s3 ls")
    }

    // MARK: - Цепочки, обёртки, кавычки

    @Test("Деструктивная команда ловится внутри цепочки и обёрток")
    func catchesDestructiveCommandsInsideChainsAndWrappers() {
        expectDestructive("cd api && rsync -a --delete ./ prod:/srv/api/", reasonContains: "rsync")
        expectDestructive("echo start; rm -rf build", reasonContains: "delet")
        expectDestructive("sudo rm -rf build", reasonContains: "delet")
        expectDestructive("env FOO=1 rm -rf build", reasonContains: "delet")
        expectDestructive("xargs rm -rf", reasonContains: "delet")
        expectDestructive("npx prisma migrate reset", reasonContains: "migrat")
    }

    @Test("Текст в кавычках не считается командой")
    func quotedTextIsNotACommand() {
        expectSafe("echo 'rm -rf /'")
        expectSafe("git commit -m 'do not rsync --delete'")
        expectSafe("grep -r 'DROP TABLE' docs/")
    }

    @Test("Подстановка команд не прячет деструктивную команду")
    func commandSubstitutionCannotHideDestruction() {
        expectDestructive("echo $(rm -rf build)", reasonContains: "delet")
        expectDestructive("echo \"$(rsync -a --delete api/ prod:/srv/)\"", reasonContains: "rsync")
        expectDestructive("echo `php artisan migrate --force`", reasonContains: "migrat")
        expectDestructive("echo $(echo $(rm -rf build))", reasonContains: "delet")
        expectSafe("echo $(date)")
        expectSafe("echo \"$(git rev-parse HEAD)\"")
    }

    @Test("Оболочки и удалённые команды классифицируются по вложенной команде")
    func shellsAndRemoteCommandsAreClassified() {
        expectDestructive("bash -c 'rm -rf build'", reasonContains: "delet")
        expectDestructive("sh -c \"rsync -a --delete ./ prod:/srv/\"", reasonContains: "rsync")
        expectDestructive("zsh -lc 'php artisan migrate --force'", reasonContains: "migrat")
        expectDestructive("eval \"git reset --hard HEAD~1\"", reasonContains: "git")
        expectDestructive("ssh prod 'rm -rf /srv/app'", reasonContains: "delet")
        expectDestructive("sudo -u root bash -c 'rm -rf build'", reasonContains: "delet")
        expectSafe("bash -c 'ls -la'")
        expectSafe("ssh prod 'git status'")
    }

    @Test("Обычные команды разработки безопасны")
    func ordinaryDevelopmentCommandsAreSafe() {
        expectSafe("npm test")
        expectSafe("swift build")
        expectSafe("swift test")
        expectSafe("npm run build")
        expectSafe("ls -la")
        expectSafe("git diff")
        expectSafe("pwd && whoami")
    }
}
