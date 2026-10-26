# Regression Loop

This file is the execution checklist for the six reported defects. The single
canonical status spreadsheet is `docs/FEATURE_SPREADSHEET.csv`; do not create a
second feature registry.

| Step | Evidence | Status |
|---|---|---|
| 1 | Trace every control to current code | COMPLETE |
| 2 | Write user story/expected behavior | COMPLETE in activity/error files |
| 3 | Run targeted regression tests | COMPLETE: web suites pass |
| 4 | Run full `swift test` | COMPLETE: 1858 tests / 265 suites |
| 5 | Record every failure | COMPLETE: no failing tests; native/network limits documented |
| 6 | Fix code/UX/logistic errors | COMPLETE for reported six source-level issues |
| 7 | Repeat targeted tests | COMPLETE |
| 8 | Repeat full suite | COMPLETE |
| 9 | Mark CSV status and limits | COMPLETE |

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
