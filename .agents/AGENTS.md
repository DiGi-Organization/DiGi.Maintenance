# AI General Rules & Priorities

> [!IMPORTANT]
> **Portability Rule:** all markdown files (guidelines, READMEs, CLAUDE.md, …) use **relative paths**; never an absolute
> machine path (`C:\Users\...`).

## Priorities (unless the prompt says otherwise)
1. **Quality & guideline adherence (highest):** correctness, architecture, explicit typing, English-only code — never
   compromised.
2. **Token efficiency (high):** no filler, introductions or conclusions; output only the code, logic or explanation asked
   for; do not read irrelevant guideline files.
3. **Speed (lowest):** sacrifice it for quality and reasoning.

Always:
- The C# codebase is many **separate** projects, not one solution.
- **Read the generated API docs before source:** `documentation/API/<AssemblyName>/<Namespace>.md` in each repository holds
  every public signature and `<summary>`; open `.cs` only to edit it or read internal logic (fallback: source and
  `bin/*.xml`; rebuild to refresh after changing signatures or doc comments).

## Skills — load the one matching the task (`skills/<name>/SKILL.md`)

### Coding
- **coding-general:** Any C# edit — naming/typing, `Query`/`Modify`/`Create`/`Convert` architecture, cheap constructors, one member per file, enums, constants, `files` vs `user files`, logging, cancellation filter, `TODO [Marker]`, binding traps.
- **coding-serialization:** `SerializableObject` types and options classes — three constructors, `DateTimeOffset`, serializer traps, `SerializationCheck` + copy-constructor facts.
- **coding-host-dependencies:** NuGet packages and `HintPath` hosts — re-declaring packages on hosts, partial-result `FileNotFoundException`, stale `deps.json`, `CS0012`/`-m:1` build walls, rebuilding consumers.
- **coding-project-setup:** New project/repository from `templates/`, `.editorconfig` (overrides only under `[*.cs]`), `Directory.Build.props`/LangVersion, analyzers.
- **coding-automatic-tests:** xUnit facts — structure, fixtures, build-before-test, duration classes, reproduce-first, guards that fail, database facts.
- **coding-performance:** Optimizing (no caching unless allowed), isolated benchmarks, A/B binaries, parity tests, the wiki `Benchmark.md` page.
- **coding-references:** Comparing `IReference`/`IUniqueReference` — `==` on interfaces is a silent bug; `Core.Query.Equals`.
- **coding-geometry:** `SunDirection` points away from the sun, `Vector3D.Unit` never null, `IsClosed` not monotonic, sub-tolerance corners before `Triangulate`, hash keys, point-in-polygon sweeps.
- **coding-computesharp:** `IComputeShader` layout — odd root constants with odd resources corrupt doubles on NVIDIA; guard and parity facts.
- **coding-grasshopper:** Grasshopper/Rhino components — fixed GUIDs, name-based parameter lookup, Goo/Param pairs, `Inspect`, `.gha` projects.
- **coding-background-tasks:** Tray background tasks — `ReportableBackgroundTask<long>`, Error log before `return false`, `UI<Task>` dialogs on a copy, `VisualBackgroundTasks` registration.
- **coding-wpf-deferred-loading:** WPF windows with slow data — open at once, background read, bottom-left progress, cancel on `Closed`, `null` = unknown, STA facts, off-screen render harness.
- **coding-yolo:** YOLO Year Built detector — `model.pt` resolution/SHA, training outside the workspace, chunked scratch, allowlisted runner deploy.
- **coding-laya:** Laya model — `DirectorySHA256` identity, fine-tune + calibrate, `DeployLaya.ps1`, host venv outside the synced tree.
- **coding-webapi-gltf:** `DiGi.GLTF` Web APIs — converters in WORLD coordinates, batching, `gltf-viewer-core.js` edited only in its owner, payload facts.
- **coding-webapi-contracts:** Routes/parameters/controllers and HTTP clients — silent parameter renames, omitted parameters, enums as integers, failures never read as empty, one public constructor, `Content(...)` not `Ok(x)`, timeouts.
- **coding-webapi-simple-authorization:** API-key tiers — deny by default, `key` header, constant-time compare, what the host pipeline really inserts.
- **coding-deployed-webapi:** Live checks at `api.digiproject.uk` — per-prefix Swagger, deployed-build lag, gotchas, which server runs what.
- **coding-browser-testing:** Playwright checks of interactive UI and rendered output; phone layouts; host shell only.
- **coding-gis-administrative-data:** County code ≠ key (406 parts for 380 codes), `fallbackByReference`, sibling-part pruning, the nested Subdivision layer.
- **coding-postgresql:** Npgsql — `NULLS NOT DISTINCT`, batching, forwarded timeouts, partition pruning, disposal, identifiers, production vs `*.conf`, test databases.
- **coding-postgresql-distributed-queue-processing:** Claim/acknowledge queues — `SKIP LOCKED`, attempts and retirement, lease vs batch time, ownership, observation vs coverage.

### Documentation
- **xml-documentation:** Adding or auditing XML doc comments; reading `documentation/API/`.

### GitHub
- **github-branches-and-commits:** Working branch (active version branch, no branch/PR unless asked), pre-commit sweep, plan files, pulling all repos; release bump **only on explicit request**.
- **github-issues:** Creating/editing/closing issues — `--body-file` and encoding traps, verifying premises, resolution comments, `FilterIssues.ps1`, `blocked_by` dependencies.
- **github-labels:** The label taxonomy and the mandatory `ai: *` tier.
- **github-sub-issues:** Tracking issue + one self-contained sub-issue per repository.
- **github-workspace-setup:** Folder layout, new machine, `user files/` restore, migration, `WIKI_SYNC_PAT`.
- **github-wiki:** Editing wiki pages and `Home.md`.

### Maintenance
- **maintenance-scripts:** `DiGi.Maintenance/Scripts` — conf keys, sweeps and the `-NoCommit` trap, build/deploy flow, new-script conventions, scripted edits and line endings.
- **maintenance-ai-guidelines-propagation:** Adding, splitting, renaming or removing a guideline and its five hand-synced targets.
