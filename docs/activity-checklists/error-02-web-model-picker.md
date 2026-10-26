# Ошибка 02: Browser model picker

**User story:** As a user, I choose web models in the shared composer using the
MiMo-Auto-branded discovery flow, not a second manual browser picker.

| Проверка | Expected | Current quality |
|---|---|---|
| Browser login header | MiMo logo/status, no manual model picker | FIXED in UI path |
| Capture | Works after cookies exist | FIXED by code path |
| Discovery | Runs after authenticated session capture | PASS by code, live QA |
| Chat model menu | Uses discovered web models | PASS |
| Browser injection | Applies composer selection before send | PASS by code, live QA |

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
