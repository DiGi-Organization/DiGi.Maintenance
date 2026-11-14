# Evidence: Maintenance - AI Guidelines Propagation.md

History behind [Maintenance - AI Guidelines Propagation.md](../Maintenance%20-%20AI%20Guidelines%20Propagation.md), keyed
by its section numbers. Read only when a rule is disputed or being changed.

## §1.1 Why a guideline's size matters
A skill loads whole, so a file's size is paid on every task routed to it. Measured 2026-11-14 before the checklist-first
layout: 31 guidelines, 273 736 bytes; the eight largest 10 792–24 221 bytes; 31 skill descriptions 14 284 bytes, loaded by
every session of a skill-aware agent.

## §2 The five hand-synced targets (retired 2026-11-14)
Until the manifest, no script derived these and a guideline was not done until the source and all five hand-synced
targets were updated:

| Target | Update | Failure if skipped |
|---|---|---|
| `$descriptions` in `Scripts/UpdateAgents.ps1` | Key = derived skill name (alphabetical); value = `Use when <task> - <key traps>`, one line, ≤ ~60 words | Only a **warning**; the skill ships everywhere as `Use for tasks related to <name>.` and is never routed to |
| `DiGi.Maintenance/.agents/AGENTS.md` | A bullet under the right `###`: `**<skill-name>:** Use when … — specifics.` | Agents never learn the skill exists |
| `documentation/AI Guidelines/README.md` | A row in the matching routing section | The human index misses it |
| `files/README - Coding Guidelines.md` | A row in the Full Guideline Set table | Every repository README omits it, and the two drift |
| `DiGi/CLAUDE.md` (workspace root, in no repository) | A routing-table row; re-sync any always-apply essential; fix paths on a move/rename | Claude Code routes to a missing file or never learns of it |

Inside the PowerShell string of `$descriptions` a literal `$` was `` `$ `` and a literal `"` was `""`. The old
verification step read: a non-generic `description:` (`Use for tasks related
to` = missing or misspelled `$descriptions` key); the source check was "the five targets carry it".
The first four lists now come from `Guidelines.json` (the README block is still hand-written and only checked for
coverage).
