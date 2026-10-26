# Ошибка 04: Qwen discovery

**User story:** As a Qwen user, I see every model exposed by the current Qwen
selector, not only the first three.

| Проверка | Expected | Current quality |
|---|---|---|
| Primary item selector | Reads visible models | PASS |
| Option selector | Merges additional option surfaces | FIXED by code |
| Deduplication | Same model appears once | PASS |
| Persisted list | Replaces old discovery | PASS |
| Live Qwen result | All current models | PARTIAL, live account needed |

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
