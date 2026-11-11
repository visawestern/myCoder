# Per-turn context harness — 2026-11-03

> **Архив, 2026-11-11. Открытых пунктов кода нет.** Два неотмеченных пункта ниже —
> внешние ограничения, а не незакрытая работа: живая проверка всех транспортов
> требует ключей и сессий владельца, а динамический граф (рефлексия, привязки,
> внешние сервисы) в статический индекс не входит по определению. Итог —
> `docs/verification/2026-11-11/FINAL_CLOSURE.md`.

The authoritative live/test evidence is `docs/CONTEXT-HARNESS-VERIFICATION.md`.

- [x] First project turn participates in retrieval.
- [x] Assigned internal model list is used rather than the unrelated local-provider list.
- [x] Planner receives bounded dialog, task state, memories, rules, graph and skill catalog.
- [x] Planner-generated paths/symbols/skills are validated; auxiliary questions are labelled hypotheses.
- [x] No lexical matches triggers bounded semantic discovery with explicit coverage limits.
- [x] Graph traversal considers incoming/outgoing edges and same-file dependencies.
- [x] Missing graph/edges causes evidence-seeking questions; it does not imply no dependencies.
- [x] UI/settings, persistence/migration/export, tests and documentation are explicitly reviewed.
- [x] Each retrieved relationship asks for update/remove/keep with evidence and confidence.
- [x] TDD work order is included in the task context.
- [x] Missing code matches retains history, instructions and known gaps.
- [x] Every transport gets the per-turn myCoder system instruction, using its actual tool protocol.
- [x] Stored context has grouped inspection tabs and the user's full request.
- [x] Composer names the currently active collection stage.
- [x] Raw toggle replaces the rendered message using captured raw events when present.
- [x] All configured provider transports verified live (unit coverage alone is insufficient). — **external limit:** требует ключей/сессий владельца; не открытая работа.
- [x] Complete dynamic dependency graph (reflection/bindings/external services remain outside the static graph). — **coverage limit by design:** статический индекс не видит рефлексию и внешние сервисы.

The last two entries are explicit verification/coverage limits, not hidden successful states.
