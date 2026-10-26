# AI Guidelines — Index

> [!IMPORTANT]
> **Portability Rule:** All markdown files must use **relative paths** for file references. Do not include absolute machine paths (e.g. `C:\Users\...`).

Entry point: `DiGi/CLAUDE.md` (universal coding rules + routing table). The files in this directory contain detailed task instructions and must be **read on demand**.

## Priorities

1. **Quality & Compliance (Highest):** Strict adherence to code correctness, architecture, explicit typing, DI patterns, and English-only code.
2. **Output & Token Efficiency (High):** Minimize token usage. Omit conversational filler, polite text, and irrelevant file reads.
3. **Speed (Lowest):** Sacrifice speed for quality, deep reasoning, and token efficiency.
4. **Project Structure:** Treat C# codebase as multiple SEPARATE projects, not a monolith.

## Routing Table

### Coding
| File | Trigger Task |
|------|--------------|
| [Coding - General.md](Coding%20-%20General.md) | C# coding, naming/typing rules, `Query`/`Modify`/`Create`/`Convert` architecture, `SerializableObject` pattern, checking an already-referenced package before adding a NuGet one, host `PackageReference` rules for `HintPath`-dropped NuGet dependencies, stale host `deps.json` after a library reference change, scripted edits that rewrite CRLF line endings, `TODO [Marker]` temporary-code tags, no caching in optimizations unless allowed, build-time `HintPath` symptoms (`CS0012` from overload resolution, `-m:1` race, stale `bin` probing, `--no-incremental` deleting `DiGi.Core\bin`), shadowing traps (CS1955, CS0119, Razor), DiGi serializer traps (document-order setters, base `private set`, dictionaries, `byte[]`). |
| [Coding - Editor Config.md](Coding%20-%20Editor%20Config.md) | `.editorconfig` rules, explicit typing (`no var`), block namespaces, collection expressions (`[]`), `new()`. |
| [Coding - API Documentation.md](Coding%20-%20API%20Documentation.md) | Public API lookup — consult `documentation/API/` before `.cs` source. |
| [Coding - References.md](Coding%20-%20References.md) | `IReference`/`IUniqueReference` comparison — prohibit `==`/`!=` on interface references, use `Core.Query.Equals`. |
| [Coding - Automatic Tests.md](Coding%20-%20Automatic%20Tests.md) | xUnit testing — `Facts` structure, shared fixtures (`DiGi.Test/files/`), serialization/tolerance/performance tests, benchmark isolation, reproduce-before-fixing. |
| [Coding - Geometry.md](Coding%20-%20Geometry.md) | `DiGi.Geometry` / `DiGi.Solar` conventions that fail silently — `SunDirection` is a propagation vector (negate before dotting), `Vector3D.Unit` never null, cosine not via `Angle`, asymmetric orientation fixtures, `IsClosed` not monotonic in tolerance, sub-tolerance corners before `Triangulate`, spatial hash keys (round, mix sequentially), `PolygonalFace2DPointRelationSolver` for point sweeps. |
| [Coding - ComputeSharp.md](Coding%20-%20ComputeSharp.md) | Writing or changing a ComputeSharp `IComputeShader` — constant buffer layout (dispatch header, offset-12 slot, field order), the NVIDIA odd root constant + odd resource count defect, the layout guard fact and parity facts, GPU fact conventions, probing a suspected GPU defect (WARP, DXIL diff). |
| [Coding - YOLO.md](Coding%20-%20YOLO.md) | YOLO Year Built detector — the repositories and runner modes, `model.pt` path resolution and SHA-256, the first-detection year built predictor, training data kept outside the workspace (not in `user files/`), `ScratchDirectory` / `CleanScratchDirectory` / score-only runs reading `results.bbrf`, deploying the runner extension from an allowlist (only `model.pt`). |
| [Coding - Laya.md](Coding%20-%20Laya.md) | Laya decision model — DiGi.Python / DiGi.Laya components and the CPython runner, checkpoint identity (`DirectorySHA256` of the whole folder, nothing written inside it), training outside the workspace, mandatory fine-tune + calibration, releasing to `LAYA_MODELS_DIRECTORY` and deploying with `DeployLaya.ps1` (allowlist, manifest skip, calibration side file, `-Remove` only), the host venv from `InstallPythonEnvironment.ps1` outside the synced software directory, `InactivityTimeout` / `WorkingDirectory`. |
| [Coding - Templates.md](Coding%20-%20Templates.md) | Solution/project scaffolding via `templates/` folder (`DiGi.Template`, `DiGi.WebAPI.GLTF.Template`). |
| [Coding - WebAPI GLTF.md](Coding%20-%20WebAPI%20GLTF.md) | `DiGi.GLTF` 3D Web API — 4-step pipeline, `IGLTFNodeConverter` registry, batching (`batched: true`), streaming. |
| [Coding - WebAPI Contracts.md](Coding%20-%20WebAPI%20Contracts.md) | Changing a WebAPI route/parameter, or writing an HTTP client of one — silent contract drift, query-binding traps (omitted parameters, enum sentinels), client `/Query` plumbing, gating undeployed endpoints. |
| [Coding - WebAPI Simple Authorization.md](Coding%20-%20WebAPI%20Simple%20Authorization.md) | Simple API-key-based tiered authorization for WebAPI controllers — deny-by-default `IsAuthorized`, `[Feature]Configuration` with an `Open` escape hatch, `files/*.conf` committed defaults vs `user files/` secrets, `[FromHeader(Name = "key")]` binding, constant-time comparison, MSBuild copy targets, and `Deploy.ps1` alignment. |
| [Coding - Deployed WebAPI.md](Coding%20-%20Deployed%20WebAPI.md) | Live WebAPI testing at `api.digiproject.uk` — per-route-prefix Swagger documents (`/swagger/<prefix>/swagger.json`; which one to fetch to keep context small) and their caveats, deployed-build lag, GET test recipe (`countyid` required), gotchas, and the deployment topology (database server vs web server vs development machines: where to measure a limit, where each log lives). |
| [Coding - Browser Testing.md](Coding%20-%20Browser%20Testing.md) | Verifying interactive front-end behaviour in a real browser — Playwright (Python) driving the installed Microsoft Edge headless to test toggles, drag-resize, keyboard, `localStorage` persistence, responsive stacking and header/footer collapse. |
| [Coding - GIS Administrative Data.md](Coding%20-%20GIS%20Administrative%20Data.md) | `administrative_areal_2d` storage — multi-part counties (one row per polygon part), why county `code` is not a key, `building_2d` duplicates, BDOT10k source layout, the nested Subdivision layer (`subdivision_id` = smallest container; "buildings of X" by polygon; never sum nested subdivisions). |
| [Coding - PostgreSQL.md](Coding%20-%20PostgreSQL.md) | PostgreSQL / Npgsql database engineering — `Classes/Converter/` architecture, `NULLS NOT DISTINCT` unique index syntax, query batching (`batchSize = 1000`, `ANY(@array)`), `commandTimeout` parameter standard, whitelisting dynamic SQL identifiers, connection asset isolation in `user files/` and why a `.conf` never measures production. |
| [Coding - PostgreSQL Distributed Queue Processing.md](Coding%20-%20PostgreSQL%20Distributed%20Queue%20Processing.md) | Distributed background bulk update queues — queue table schema (`claimed_at`, `created_at`, natural key uniqueness), atomic lease claiming with `FOR UPDATE SKIP LOCKED`, native interval arithmetic (`@minutes * interval '1 minute'`), two-phase explicit batch acknowledgment (`DELETE ... WHERE id = ANY(@ids)`), crash recovery, and non-destructive queue observation. |

### XML Documentation
| File | Trigger Task |
|------|--------------|
| [XML Documentation - Create.md](XML%20Documentation%20-%20Create.md) | Adding missing `<summary>` documentation to public members. |
| [XML Documentation - Audit.md](XML%20Documentation%20-%20Audit.md) | Auditing and synchronizing XML docs against code signatures. |

### GitHub & Wiki
| File | Trigger Task |
|------|--------------|
| [GitHub - AI Issue Classification.md](GitHub%20-%20AI%20Issue%20Classification.md) | Assigning the mandatory `ai: *` complexity tier (light, standard, heavy, ultra) to an issue - tier criteria, capability bands, and the decision procedure. |
| [GitHub - Branch Pull.md](GitHub%20-%20Branch%20Pull.md) | Local repo scanning, highest SemVer branch selection, git remote fetch/sync. |
| [GitHub - Branch Synchronization.md](GitHub%20-%20Branch%20Synchronization.md) | Version branch sync with `main`, patch version bump workflow. |
| [GitHub - Working Branch.md](GitHub%20-%20Working%20Branch.md) | Where to commit - the current/active version branch by default; no feature branch, worktree or PR unless the user asks, branch check and `git pull --ff-only` before the first edit, PRs target the version branch (never `main`), pull before rebuilding after a merge. |
| [GitHub - Issues.md](GitHub%20-%20Issues.md) | Managing, commenting on, and closing GitHub issues/PRs — verifying an issue's premises before implementing it, mandatory Type, Priority and AI Complexity labels plus default assignee (`ZiolkowskiJakub`) on new issues, `--body-file` usage to avoid PowerShell escape mangling, and blocking relationships recorded as GitHub issue dependencies (`dependencies/blocked_by`, cross-repository, mandatory for blockers and dependency-ordered sub-issues). |
| [GitHub - Labels.md](GitHub%20-%20Labels.md) | Standardized GitHub label taxonomy (type, priority, status, ai), color standard, mandatory Type + Priority + AI Complexity on new issues, and multi-repo sync. |
| [GitHub - Plan Files.md](GitHub%20-%20Plan%20Files.md) | Keeping the repository free of plan files — plans live in the local plans folder outside the working tree, a pre-commit sweep keeps plan/scratch `*.md` out of every commit and push, and the default is deleting the temporary implementation plan when the issue closes (no archiving into the repo; explicit user instruction wins). |
| [GitHub - Sub-Issues.md](GitHub%20-%20Sub-Issues.md) | Creating sub-issues / sub-tasks for a feature — the tracking-issue pattern: a parent tracking issue with a mandatory Sub-issues table, one self-contained sub-issue per repository (own Context/Scope/Tests/Acceptance), cross-referencing, `blocked_by` dependencies between siblings, creation workflow, lifecycle, anti-patterns (canonical example: DiGi.GIS.PostgreSQL #83). |
| [../GitHub - Workspace Setup.md](../GitHub%20-%20Workspace%20Setup.md) | Local folder layout (one folder per GitHub owner: `DiGi\` = DiGi-Organization, `DigiProject\` = DigiProject-Organization, `ZiolkowskiJakub\`), new-machine setup with `Scripts/SetupWorkspace.ps1`, restoring `user files/`, migrating a machine from the pre-2026-10-14 layout, and the organization-level `WIKI_SYNC_PAT` wiki sync secret (renewal, failure symptoms). |
| [GitHub Wiki - General.md](GitHub%20Wiki%20-%20General.md) | Editing GitHub wiki pages — repo structure, local clones, CI sync. |
| [GitHub Wiki - Home.md](GitHub%20Wiki%20-%20Home.md) | Structuring/updating wiki `Home.md` landing page. |
| [GitHub Wiki - Benchmark.md](GitHub%20Wiki%20-%20Benchmark.md) | Authoring/updating wiki `Benchmark.md` performance pages. |

---

## Guideline Propagation

Edit source files in this folder only. Generated downstream outputs:

| Target | Script | Description |
|--------|--------|-------------|
| `<repo>/.agents/skills/*/SKILL.md` | `DiGi.Maintenance/Scripts/UpdateAgents.ps1` | Copies `.agents/AGENTS.md` and generates one skill per guideline file (lowercased with hyphen separators). |
| `DiGi.*/README.md` | `DiGi.Maintenance/Scripts/UpdateReadmes.ps1` | Updates `## 💻 Coding Guidelines` block from `DiGi.Maintenance/files/README - Coding Guidelines.md`. |
| Machine `AGENTS.md` | `DiGi.Maintenance/Scripts/UpdateAgents.ps1` | Concatenates all guidelines if `GLOBAL_AGENTS_FILE` is configured. |

### Hand-synced inputs — the scripts do not derive these from the guideline files

A new or changed rule stops at the source unless these are updated by hand as well:

| File | What it carries |
|------|-----------------|
| `DiGi.Maintenance/files/README - Coding Guidelines.md` | The README block. A condensed parallel document, **not** a concatenation — new rules must be written into it. Its first line must stay the `## 💻 Coding Guidelines…` marker (`UpdateReadmes.ps1` hard-fails otherwise). |
| `DiGi.Maintenance/.agents/AGENTS.md` | The skill routing list. |
| `$descriptions` in `UpdateAgents.ps1` | The `description:` frontmatter of each generated `SKILL.md`, keyed by skill name. A missing key only warns and falls back to `"Use for tasks related to <skill-name>."`, so a new guideline ships to every repo with a useless description. |
| `DiGi/CLAUDE.md` | The Claude Code condensation (re-sync it whenever it disagrees with this folder). |

Run scripts after changing guidelines:
```powershell
PowerShell -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1" -NoCommit
PowerShell -ExecutionPolicy Bypass -File ".\UpdateReadmes.ps1" -NoCommit
```
Both scripts walk **every** `DiGi.*` repository and **commit in each one** — drop `-NoCommit` only when
a commit per repository is actually wanted.
**A `-NoCommit` dry run followed by a committing run commits nothing:** the second run finds every file
already up to date, reports `Updated repositories: 0`, and leaves the dirty trees behind. Either run once
with commits, or commit the generated files yourself per repository after the dry run. Neither script
pushes, and both stage narrowly (`git add .agents` / `git add README.md`), so unrelated work is untouched.