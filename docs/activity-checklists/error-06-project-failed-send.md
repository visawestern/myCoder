# Ошибка 06: Project created, first send failed

**User story:** As a user, after creating a project, a failed first request still
leaves the user message, assistant error, and session in that project.

| Проверка | Expected | Current quality |
|---|---|---|
| Project creation | Workspace selected and DB created | PASS |
| Preflight rejection | Creates local session and records user/error | FIXED path exists |
| Network failure | Persists unsent user message and error | FIXED path exists |
| Web failure | Creates local session before web turn | PASS |
| Reload | Session remains visible after refresh/reopen | PASS by code |
| Regression test | Forced failure verifies stored rows | PASS |

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
