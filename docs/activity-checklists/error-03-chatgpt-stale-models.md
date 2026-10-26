# Ошибка 03: ChatGPT stale models/features

**User story:** As a ChatGPT user, I see only models actually returned by the
current authenticated model selector, not 29 stale models or feature modes.

| Проверка | Expected | Current quality |
|---|---|---|
| Config default | Empty until live discovery | FIXED |
| Connectivity list | No vendor catalog fallback | FIXED |
| Refresh | Replaces previous stale discovery | FIXED by source path |
| Feature modes | Not mixed into model list | PARTIAL, live DOM verification |
| UI result | One current model where site has one | PARTIAL, live account needed |

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
