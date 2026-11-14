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
  `bin/*.xml`; rebuild to refresh after changing signatures or doc comments). Never read a namespace page whole — look the member up with `GetApi.ps1`.
- **Scripts before reading:** `DiGi.Maintenance/Scripts` answers routine questions in a few lines — `StatusAllRepos.ps1` (git state of every repository), `GetApi.ps1` (a signature + summary), `TestSummary.ps1` (build the library, run facts, failures only), `BuildAll.ps1 -Summary`, `CheckGuidelineRules.ps1 -Changed` (rules no analyzer checks). Workflow skills: `digi-verify`, `digi-status`, `digi-api`, `digi-issue`, `digi-guideline-change`.

## Skills — load the one matching the task (`skills/<name>/SKILL.md`)
A skill opens with its **Checklist**; the full sections are in `guideline.md` beside it (incidents in `evidence.md`) — read the section a checklist line names before changing code it covers, not the whole file.

<!-- guidelines:begin -->
### Coding
- **coding-general:** Use when writing or editing any C# - no var, type-prefixed naming, parameter line breaks, CancellationToken last, Query/Modify/Create/Convert, cheap constructors, enums, constants, files vs user files, logging, cancellation filter, TODO [Marker], binding traps.
- **coding-serialization:** Use when creating or changing a SerializableObject or *Options type, or debugging a JSON round trip - three constructors, [JsonInclude] fields, DateTimeOffset, serializer traps, SerializationCheck plus copy-constructor facts.
- **coding-host-dependencies:** Use when adding a NuGet package, when a host throws FileNotFoundException or returns a partial result, or on CS0012/CS0246 walls - HintPath drops transitive packages, stale deps.json, CheckHostDependencies.ps1, rebuilding consumers.
- **coding-project-setup:** Use when creating a project or repository from templates/ or changing build configuration - .gitignore, Directory.Build.props, analyzers and suppressions, .editorconfig overrides only under [*.cs], DIGI0001.
- **coding-automatic-tests:** Use when writing xUnit facts - Facts layout, fixtures in DiGi.Test/files, build the library before dotnet test, Short/Medium/Long attributes, reproduce-first, guards that can fail, database facts on *_Test.conf.
- **coding-performance:** Use when optimizing or measuring code - no caching unless allowed, isolated benchmark facts with warm-up, A/B on the intended binary, parity tests, the wiki Benchmark.md page.
- **coding-references:** Use when comparing, matching, keying or de-duplicating an IReference/IUniqueReference - == on interfaces is a silent reference comparison, use Core.Query.Equals.
- **coding-geometry:** Use when orienting, closing, triangulating, hashing or sweeping DiGi.Geometry/DiGi.Solar geometry - SunDirection points away from the sun, Vector3D.Unit never null, IsClosed not monotonic, sub-tolerance corners, hash keys.
- **coding-computesharp:** Use when writing or changing a ComputeSharp IComputeShader - constant buffer layout, odd root constants with odd resources corrupt doubles on NVIDIA, layout guard and parity facts.
- **coding-grasshopper:** Use when writing a Grasshopper/Rhino component (DiGi.*.Rhino) - fixed ComponentGuid, name-based parameter lookup, Goo/Param pairs, Inspect, .gha project setup.
- **coding-background-tasks:** Use when writing a tray-application background task (DiGi.GIS.PostgreSQL.UI) - ReportableBackgroundTask<long>, Error log before return false, UI<Task> dialogs on a copy, Create.VisualBackgroundTasks registration, post tasks.
- **coding-wpf-deferred-loading:** Use when a WPF window or dialog needs slow data, or when checking WPF layout without its host - open at once, background read, progress bar, cancel on Closed, null means unknown, STA facts, off-screen render harness.
- **coding-yolo:** Use when working on the YOLO Year Built detector - model.pt resolution and SHA-256, training data and scratch outside the workspace, chunked scratch, allowlisted runner deploy.
- **coding-laya:** Use when working on the Laya decision model - checkpoint identity by DirectorySHA256, fine-tune and calibrate, LAYA_MODELS_DIRECTORY and DeployLaya.ps1, host venv outside the synced directory.
- **coding-webapi-gltf:** Use when building a Web API on the DiGi.GLTF 3D framework - IGLTFNodeConverter in WORLD coordinates, batched payloads, gltf-viewer-core.js edited only in its owner, what the payload does not carry.
- **coding-webapi-contracts:** Use when changing a WebAPI route, parameter, controller or extension, or writing its HTTP client - silent parameter renames, omitted parameters, enums on the wire, failure statuses never read as empty, timeouts, one public constructor, Content(...) not Ok(x).
- **coding-webapi-simple-authorization:** Use when implementing or auditing API-key tiered authorization on a WebAPI - deny by default, key header, constant-time compare, fail-closed factory, what the host authentication pipeline inserts.
- **coding-deployed-webapi:** Use when checking a change against api.digiproject.uk or deciding which server runs what - per-prefix Swagger, deployed build lag, sequential querying, cold-partition timeouts, where each log lives. Manual curl only.
- **coding-browser-testing:** Use when verifying interactive front-end behaviour in a real browser - Playwright, toggles, drag-resize, keyboard, localStorage, phone layouts, rendered output by screenshot statistics; host shell only.
- **coding-gis-administrative-data:** Use when touching administrative_areal_2d, building_2d or anything keyed by a county code or id - a code is not a key (406 parts for 380 counties), fallbackByReference, sibling-part pruning, the Subdivision layer.
- **coding-postgresql:** Use when writing Npgsql/PostgreSQL code - NULLS NOT DISTINCT keys, batching, forwarded timeouts and tokens, partition pruning, disposal, whitelisted identifiers, production only through the API, *_Test.conf databases.
- **coding-postgresql-distributed-queue-processing:** Use when designing or maintaining a claim/acknowledge update queue in PostgreSQL - FOR UPDATE SKIP LOCKED, attempts and poison-row retirement, lease vs batch time, ownership, observation vs coverage.

### Documentation
- **xml-documentation:** Use when reading a public API (documentation/API before .cs) or adding or auditing XML doc comments - every public member, params in signature order, one summary, no docs on partial declarations.

### GitHub & Wiki
- **github-branches-and-commits:** Use before the first edit and before every commit - commit on the active version branch (no branch, worktree or PR unless asked), pre-commit sweep, push only when asked, plan files, release bump only on explicit request.
- **github-issues:** Use when creating, editing, commenting on, filtering or closing GitHub issues - --body-file encoding traps, mandatory labels and assignee ZiolkowskiJakub, verifying premises, resolution comments, FilterIssues.ps1, blocked_by dependencies.
- **github-labels:** Use when applying or syncing GitHub labels or choosing an issue's mandatory 'ai: *' tier - the 21-label taxonomy, tier criteria, SyncLabelsAllRepos.ps1.
- **github-sub-issues:** Use when splitting a feature into sub-issues - a tracking issue with the shared spec plus one self-contained sub-issue per repository, sibling order as blocked_by.
- **github-workspace-setup:** Use when setting up a new machine or changing the local folder layout - one folder per owner, SetupWorkspace.ps1, restoring user files, AI-app root files, WIKI_SYNC_PAT.
- **github-wiki:** Use when editing a GitHub wiki page or Home.md - wiki clones under DiGi/wiki, generated API pages never hand-edited, linking every page from Home, SyncWiki.ps1 parser rules.

### Maintenance
- **maintenance-scripts:** Use when running or writing DiGi.Maintenance scripts or making scripted edits - context scripts first, conf keys, *AllRepos sweeps and the -NoCommit trap, BuildAll order, deploy, editing bytes not lines, line endings.
- **maintenance-ai-guidelines-propagation:** Use when adding, splitting, renaming or removing an AI Guideline or regenerating .agents/skills - the Guidelines.json manifest, checklist-first layout with Evidence files, stable section anchors, UpdateAgents.ps1.
<!-- guidelines:end -->
