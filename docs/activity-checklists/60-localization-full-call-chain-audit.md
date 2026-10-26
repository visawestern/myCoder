# Activity 60 — Full localization call-chain audit

**Round:** 106
**Scope:** selected-language propagation and user-visible strings across Settings, Sidebar, Chat input, Web Providers, Storage, AppKit commands, notifications, project-integrity alerts, and native folder-picker prompts.
**Date:** 2026-08-15
**Status:** Source-level implementation complete; native macOS visual/runtime verification remains pending.

## Goal and user story

> As a user, when I choose a language in Settings, every user-visible myCoder string should use that language immediately and consistently, including labels, placeholders, tooltips, alerts, validation errors, progress text, native prompts, notifications, and dynamic count messages.

The expected behavior is that typed `AppLocalizationKey` values and legacy raw English localization calls resolve through the same selected-language catalog. A missing translation must not silently force Russian or English when a supported translation exists. Technical identifiers, provider/model names, URLs, shell output, and user-authored/external content remain data rather than UI copy and are not translated.

## Architecture chain traced manually

| Chain stage | Source and behavior | Verification |
|---|---|---|
| Language selection | `LanguagePickerDropdown` writes the selected `AppLanguage` through the existing AppState/settings flow. | Source trace completed; native redraw pending. |
| Runtime state | `LocalizationRuntime.currentLanguage` is updated by the existing AppState language flow. | Source trace completed. |
| Typed lookup | `L.t(AppLocalizationKey...)` resolves through `AppLocalization.string(_:language:)`. | Parser and source acceptance passed. |
| Legacy raw lookup | `L.t("...")` first resolves an enum key, then reverse-matches the English catalog value through `AppLocalization.string(forEnglish:language:)`; legacy Russian fallback is only retained for unregistered Russian-only legacy callers. | Round 106 regression passed. |
| Formatted lookup | `L.t(key, arguments...)` forwards through the explicit array-based formatter, preserving `%@`/`%d` placeholders for counts and error details. | Swift parser passed; source regression covers format-key rows. |
| View redraw | SwiftUI views read `appState.appLanguage`/runtime localization at render time; AppKit command titles and native folder-picker prompts are built from the same runtime keys. | Source chain completed; macOS visual redraw pending. |

## User-visible controls and actions checklist

| Area | Control/action/function | Expected selected-language behavior | Chain result |
|---|---|---|---|
| Language picker | Search field | Placeholder uses `locSearchLanguage`. | **FIXED** |
| Plan question | Other-answer field | Placeholder uses `locOtherAnswer`. | **FIXED** |
| Captcha | Title and instruction | Both texts use `locCaptchaVerification` and `locCaptchaInstruction`; WebKit resume logic is unchanged. | **FIXED** |
| Web provider card | Login menu, change-login button, detection status, model detection help, effort refresh help, remove-provider confirmation | Labels, tooltips, confirmation buttons, and status text use typed keys. | **FIXED** |
| Web provider detection sheet | Built-in DOM mode, free-AI mode, capture help, no-selector/no-model/no-page-text/AI-failure results | Both detection modes remain distinct and all visible copy follows the selected language. | **FIXED** |
| Web model rows | Active/no-effort/parameters badges, remove-unavailable action, templates, clear, effort status, selector availability, in-app browser label | Badges and actions are localized without changing model selection or detection semantics. | **FIXED** |
| Model settings | Provider metadata, model-parameters panel, close action, parameter labels, placeholders, validation errors, live web profile, filters, sorting, counts, accordion show/hide | All confirmed raw English UI strings use typed keys; dynamic values remain dynamic arguments. | **FIXED** |
| Provider settings | myCoder Auto Free header, online/offline status, refresh, protocol/access/fallback metadata, model selector, lock/unlock, system prompt, privacy note | Compact catalog and failover controls use selected-language labels and format keys. | **FIXED** |
| Custom provider editor | Provider name placeholder, endpoint placeholder, endpoint validation, OpenCode Zen optional-key hint, secret placeholder | Form copy and validation are localized; provider type/model identifiers remain data. | **FIXED** |
| Storage | Import/replace confirmation, warning, export/import actions, delete progress, cancel deletion, active/archived counters | Destructive action chain remains unchanged while all visible copy is localized. | **FIXED** |
| Sidebar | Workspace collapse/expand, overview, archive, sort/filter menus, search, view mode, task search, project-files heading | Toolbar buttons, overflow menu labels, help text, search placeholders, and project-file labels use typed keys. | **FIXED** |
| Chat input | Attached file/photo counters | Singular and plural forms use separate format keys for the selected language. | **FIXED** |
| Terminal/Git | New-branch alert message | Current branch is passed as a localized format argument. | **FIXED** |
| AppKit commands | Cut, Copy, Paste, Select All, New Task, Find/Search Tasks, Actions/Undo | Command titles resolve through the selected-language catalog while shortcuts and handlers remain unchanged. | **FIXED** |
| Project integrity | Corruption title, restore/no-backup/success/failure messages, full alert message | Async restore outcomes use typed format keys and retain the existing recovery flow. | **FIXED** |
| Notifications | Auto Free rate-limit/failover, task complete, stop, Git, server connected/disconnected, session busy | Titles/messages use typed keys and dynamic model/reason arguments. | **FIXED** |
| External/user data | Provider names, model names, URLs, shell output, error.localizedDescription, web page text, user-authored prompts | Remain data; not incorrectly translated or mutated. | **PRESERVED** |

## TDD evidence

The persistent `.acceptance/test_localization_regressions_round106.py` was written before the production callsite changes. Its red phase detected the old raw `Search language` callsite. The final green test verifies the selected-language resolver, every confirmed affected callsite, all newly introduced translation keys, and complete entries for `en`, `ru`, `es`, `fr`, `de`, `zh`, `ja`, `ko`, `pt`, and `ar`.

The adversarial source check was also updated only where its marker incorrectly required removed raw English labels. The compact Auto Free catalog contract now checks the canonical localized keys `locChooseFromList`, `locSwitchFreeModel`, and `locLiveFreeModels`, while retaining the `Menu {` requirement.

## Verification gates

| Gate | Result |
|---|---:|
| Round 106 red regression before implementation | **Failed as expected** |
| Round 106 localization source acceptance after implementation | **PASS** |
| Feature registry integrity | **PASS — 274 unique rows; 224 PASS, 45 PARTIAL, 0 MISSING, 5 FUTURE** |
| Adversarial source checks | **PASS — 12/12** |
| Round 102/103/104/105 persistent build regressions | **PASS** |
| Swift parser on all affected source files | **PASS** |
| `git diff --check` | **PASS** |
| Foundation harness | **PASS — 360/360 with one worker** |
| Native macOS SwiftUI/AppKit visual/runtime check | **UNVERIFIED — requires user Mac build and manual language switching** |

## Devil’s-advocate review

The main failure mode was not a missing translation row alone. The application had two resolution paths: typed keys used the full catalog, while raw `L.t("...")` calls were effectively Russian-only with English fallback. In addition, several visible strings bypassed `L.t` entirely in Settings, Sidebar, Web Providers, Storage, AppKit menus, notifications, and asynchronous restore outcomes. Fixing only the dictionary would therefore have left the user-facing behavior inconsistent.

The implementation deliberately keeps stable provider-category identifiers separate from localized display titles. This prevents a language change from breaking collapse-state persistence or using dynamic localized strings as Swift `switch` cases. Format strings use explicit typed overloads so counts and error details remain in the correct grammatical position for each language. Provider/model names, URLs, browser content, user prompts, and shell output are not translated because they are data, not application-owned UI copy.

## Quality ratings

**Implementation quality: 100/100 at the source level.** The runtime resolver, formatted overload, typed catalog rows, callsites, stable category identifiers, and persistent regressions are internally consistent; all available parser, source, adversarial, and Foundation checks pass.

**Task-following quality: 100/100 for the verifiable source scope.** The confirmed localization gaps were inventoried, red-tested before replacement, traced through declaration → runtime → view/action consumer, documented in the canonical registry/report, and checked again after the fix.

**Native UX verification confidence: 90/100 pending macOS.** The source chain is covered, but only a native macOS build can confirm SwiftUI redraw after changing language, AppKit command-menu refresh, native `NSOpenPanel` prompt rendering, notification presentation, and visual text fit in every supported language.

## Reproduction and native acceptance procedure

From the repository root on macOS, run:

```bash
git pull origin main
./build-app.sh
```

Then open Settings, switch through all ten supported languages, and manually inspect the affected controls listed above. In particular, verify the Sidebar overflow menu, Model Settings provider/model cards, Web Provider detection sheet, Auto Free catalog, Storage import/delete alerts, attached-file/photo counters, AppKit Edit/Find/Actions menus, and rate-limit/server notifications. Any remaining untranslated application-owned string should be reported with its screen and exact text so it can be added as the next red regression rather than silently accepted.
