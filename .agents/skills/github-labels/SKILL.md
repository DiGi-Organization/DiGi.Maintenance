---
name: github-labels
description: "Use when applying or syncing GitHub labels or choosing an issue's mandatory 'ai: *' tier - the 21-label taxonomy, tier criteria, SyncLabelsAllRepos.ps1."
---

# AI Guidelines: GitHub Labels & AI Complexity Tier

## 1. Rules
1. **Every new issue carries at least one `type: *`, one `priority: *` and exactly one `ai: *` label at creation**, in one
   `--label` argument (command and default assignee: `GitHub - Issues.md` §1).
2. Every pull request carries at least one `type: *` label (no `ai: *`).
3. `status: *` while blocked externally, in progress, awaiting review or parked; remove once resolved.
4. Only the 21 labels below — no bare/ad-hoc labels (`bug`, `help wanted`, `wontfix`).
5. Label sweeps and audits touch **open issues only**; closed issues only on explicit user instruction.

## 2. Taxonomy
| Label | Color | Meaning |
|---|---|---|
| `type: bug` | `#d73a4a` | Confirmed defect or regression |
| `type: feature` | `#0e8a16` | Substantial new functionality or public API |
| `type: enhancement` | `#a2eeef` | Improvement of an existing capability |
| `type: performance` | `#1d76db` | Speed, allocation or query tuning |
| `type: refactor` | `#6f42c1` | Structural cleanup, no behavior change |
| `type: breaking-change` | `#b60205` | Breaking API change (version increment) |
| `type: documentation` | `#0075ca` | XML docs, AI guidelines, wiki |
| `type: test` | `#fbca04` | Facts in `DiGi.Test`, benchmarks, fixtures |
| `type: maintenance` | `#d4c5f9` | CI/CD, dependencies, `.editorconfig`, build scripts |
| `priority: critical` | `#b60205` | Blocks deployment, corrupts data, outage |
| `priority: high` | `#d93f0b` | Severe bug or major blocker for the current release |
| `priority: medium` | `#fb8c00` | Normal cycle |
| `priority: low` | `#e0e0e0` | Minor, cosmetic, low impact |
| `status: in-progress` | `#0e8a16` | Active work |
| `status: blocked` | `#b60205` | Blocked by an upstream dependency (also set the GitHub dependency, `GitHub - Issues.md` §5) |
| `status: needs-review` | `#fb8c00` | Ready for verification/review |
| `status: parked` | `#cfd3d7` | Deliberately deferred, not blocked |
| `ai: light` | `#ffd3eb` | see §3 |
| `ai: standard` | `#f692ce` | see §3 |
| `ai: heavy` | `#d03592` | see §3 |
| `ai: ultra` | `#99286e` | see §3 |

## 3. Choosing the `ai: *` tier
The tier records how much AI capability the issue needs — a routing decision.

| Tier | Criteria | Capability band | Workspace signals |
|---|---|---|---|
| `ai: light` | Typos, docs, comments, boilerplate, an obvious localized fix | Small local model (< 14B) | XML docs, wiki pages, guideline text, a `TODO [Marker]` checklist |
| `ai: standard` | One method/feature in 1–2 files, unit tests, contained refactoring | Large local model (~31B–70B, workstation GPU) | One `Query`/`Modify`/`Create`/`Convert` member and its `[Fact]` |
| `ai: heavy` | Multi-layer change (schema + data access + endpoint), concurrency/async deadlocks, cross-cutting concerns (auth, middleware) | Frontier cloud model | A converter + its controller + an HTTP client |
| `ai: ultra` | Architecture design, migration strategy, deep performance/memory work, heavy domain deduction, undocumented third-party integration | Top extended-reasoning model + human oversight | Geometry/algorithmic correctness, allocation profiling, cross-repository schema or reference-format migrations |

Procedure: estimate the files touched and the depth of architectural understanding; **err to the higher tier when core
abstractions or core business logic change**. The `type:` label is a hint only (`type: documentation` is usually `light`,
a removal checklist spanning four live markers is not). When asked only to classify, output only the label. Re-tier when
the scope proves materially different, removing the old tier in the same `gh issue edit`. Each sub-issue is tiered from
its own scope (`GitHub - Sub-Issues.md`).

## 4. Synchronization
```powershell
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/SyncLabelsAllRepos.ps1" -DryRun
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/SyncLabelsAllRepos.ps1" -Repo "DiGi.Core"
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/SyncLabelsAllRepos.ps1"
```
It creates missing labels, updates colors/descriptions, migrates legacy labels (`bug` → `type: bug`, `enhancement`,
`documentation`) and deletes GitHub's defaults (`good first issue`, `help wanted`, `invalid`, `question`, `wontfix`,
`duplicate`).
