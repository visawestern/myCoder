# Ошибка 01: MiMo-Auto default

**User story:** As a new user, I can send through Xiaomi's free `mimo-auto`
model immediately.

| Проверка | Expected | Current quality |
|---|---|---|
| Provider option | Built-in provider visible | PASS |
| Default provider | `selectedProviderID == mimo-auto` when no preference | FIXED |
| Default model | `selectedModel == mimo-auto` | FIXED |
| Send readiness | Model validation passes | FIXED by effective model route |
| Route | `.mimoAuto` | PASS |
| Stream | Direct MiMo API | PASS by code, network QA |

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
