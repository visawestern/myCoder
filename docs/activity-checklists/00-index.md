# Актуальный чеклист активити myCoder

Дата ручной сверки: 2026-08-11. Post-fix `swift test`: 1858/1858 tests,
265 suites. Старая папка удалена после резервной копии:
`/tmp/mycoder-activity-checklists-20260811-123808.tar.gz`.

Проверка выполнена по текущему коду `myCoder/Sources/**` и тестам. Канонический
реестр статусов остается единственным: `docs/FEATURE_SPREADSHEET.csv`.

## Ограничение

Здесь `MANUAL` означает ручную трассировку control -> handler -> state/service ->
result и локальный тест. Настоящие клики в WKWebView, Finder, Keychain и внешних
аккаунтах требуют live macOS-сеанса и отмечены `PARTIAL`, а не выданы за PASS.

## Активити

| Файл | Активити | Текущее качество |
|---|---|---|
| `01-app-shell.md` | ContentView и запуск | PASS с сетевым live-QA |
| `02-sidebar.md` | Workspace/sidebar | PASS по коду |
| `03-chat.md` | Composer и отправка | PASS после provider fix, live provider QA |
| `04-settings-providers.md` | Providers и model selection | PASS по коду |
| `05-web-login.md` | Web login/model discovery | PARTIAL без live WebKit |
| `06-web-chat.md` | Web chat/effort/features | PARTIAL без внешних аккаунтов |
| `07-mimo-auto.md` | MiMo-Auto provider | PASS по маршруту, network live-QA |
| `08-project-session.md` | Project/session persistence | PASS по кодовым цепочкам |
| `09-shell-status.md` | Top bar/status/menu | PASS по коду |
| `10-regression-loop.md` | Post-fix test loop | In progress until full suite |
| `13-live-qa-2026-08-11.md` | Live Kimi/ChatGPT/Qwen | Kimi/Qwen PASS; ChatGPT PARTIAL |
| `14-send-providers.md` | Send routing for every provider | PASS by route tests; external sends pending |

## Ошибки

| Файл | Ошибка | Статус |
|---|---|---|
| `error-01-mimo-auto-default.md` | MiMo-Auto был provider без выбранной модели | FIXED |
| `error-02-web-model-picker.md` | Ручной browser model picker вместо общего MiMo-Auto flow | FIXED in UI path |
| `error-03-chatgpt-stale-models.md` | ChatGPT показывал stale/feature entries как модели | FIXED in source policy; live verify pending |
| `error-04-qwen-discovery.md` | Qwen discovery теряла дополнительные модели | FIXED in source path; live verify pending |
| `error-05-effort-visibility.md` | Не был виден статус effort discovery | FIXED in card UI |
| `error-06-project-failed-send.md` | Неуспешная первая отправка теряла чат | FIXED in persistence path; regression test pending |

## Обязательный цикл

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
