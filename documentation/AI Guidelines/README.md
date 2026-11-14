# AI Guidelines — Index

> [!IMPORTANT]
> **Portability Rule:** all markdown files use **relative paths**; never an absolute machine path (`C:\Users\...`).

Entry points: `DiGi/CLAUDE.md` (Claude Code) and `.agents/AGENTS.md` (other agents) carry the always-apply rules and route
here. Files are **read on demand**, one per task; each becomes a generated skill. Maintaining this folder:
[Maintenance - AI Guidelines Propagation.md](Maintenance%20-%20AI%20Guidelines%20Propagation.md).

<!-- guidelines:begin -->
## Coding
| File | Read when |
|------|-----------|
| [Coding - General.md](Coding%20-%20General.md) | Writing or editing any C# - no var, type-prefixed naming, parameter line breaks, CancellationToken last, Query/Modify/Create/Convert, cheap constructors, enums, constants, files vs user files, logging, cancellation filter, TODO [Marker], binding traps. |
| [Coding - Serialization.md](Coding%20-%20Serialization.md) | Creating or changing a SerializableObject or *Options type, or debugging a JSON round trip - three constructors, [JsonInclude] fields, DateTimeOffset, serializer traps, SerializationCheck plus copy-constructor facts. |
| [Coding - Host Dependencies.md](Coding%20-%20Host%20Dependencies.md) | Adding a NuGet package, when a host throws FileNotFoundException or returns a partial result, or on CS0012/CS0246 walls - HintPath drops transitive packages, stale deps.json, CheckHostDependencies.ps1, rebuilding consumers. |
| [Coding - Project Setup.md](Coding%20-%20Project%20Setup.md) | Creating a project or repository from templates/ or changing build configuration - .gitignore, Directory.Build.props, analyzers and suppressions, .editorconfig overrides only under [*.cs], DIGI0001. |
| [Coding - Automatic Tests.md](Coding%20-%20Automatic%20Tests.md) | Writing xUnit facts - Facts layout, fixtures in DiGi.Test/files, build the library before dotnet test, Short/Medium/Long attributes, reproduce-first, guards that can fail, database facts on *_Test.conf. |
| [Coding - Performance.md](Coding%20-%20Performance.md) | Optimizing or measuring code - no caching unless allowed, isolated benchmark facts with warm-up, A/B on the intended binary, parity tests, the wiki Benchmark.md page. |
| [Coding - References.md](Coding%20-%20References.md) | Comparing, matching, keying or de-duplicating an IReference/IUniqueReference - == on interfaces is a silent reference comparison, use Core.Query.Equals. |
| [Coding - Geometry.md](Coding%20-%20Geometry.md) | Orienting, closing, triangulating, hashing or sweeping DiGi.Geometry/DiGi.Solar geometry - SunDirection points away from the sun, Vector3D.Unit never null, IsClosed not monotonic, sub-tolerance corners, hash keys. |
| [Coding - ComputeSharp.md](Coding%20-%20ComputeSharp.md) | Writing or changing a ComputeSharp IComputeShader - constant buffer layout, odd root constants with odd resources corrupt doubles on NVIDIA, layout guard and parity facts. |
| [Coding - Grasshopper.md](Coding%20-%20Grasshopper.md) | Writing a Grasshopper/Rhino component (DiGi.*.Rhino) - fixed ComponentGuid, name-based parameter lookup, Goo/Param pairs, Inspect, .gha project setup. |
| [Coding - Background Tasks.md](Coding%20-%20Background%20Tasks.md) | Writing a tray-application background task (DiGi.GIS.PostgreSQL.UI) - ReportableBackgroundTask<long>, Error log before return false, UI<Task> dialogs on a copy, Create.VisualBackgroundTasks registration, post tasks. |
| [Coding - WPF Deferred Loading.md](Coding%20-%20WPF%20Deferred%20Loading.md) | A WPF window or dialog needs slow data, or when checking WPF layout without its host - open at once, background read, progress bar, cancel on Closed, null means unknown, STA facts, off-screen render harness. |
| [Coding - YOLO.md](Coding%20-%20YOLO.md) | Working on the YOLO Year Built detector - model.pt resolution and SHA-256, training data and scratch outside the workspace, chunked scratch, allowlisted runner deploy. |
| [Coding - Laya.md](Coding%20-%20Laya.md) | Working on the Laya decision model - checkpoint identity by DirectorySHA256, fine-tune and calibrate, LAYA_MODELS_DIRECTORY and DeployLaya.ps1, host venv outside the synced directory. |
| [Coding - WebAPI GLTF.md](Coding%20-%20WebAPI%20GLTF.md) | Building a Web API on the DiGi.GLTF 3D framework - IGLTFNodeConverter in WORLD coordinates, batched payloads, gltf-viewer-core.js edited only in its owner, what the payload does not carry. |
| [Coding - WebAPI Contracts.md](Coding%20-%20WebAPI%20Contracts.md) | Changing a WebAPI route, parameter, controller or extension, or writing its HTTP client - silent parameter renames, omitted parameters, enums on the wire, failure statuses never read as empty, timeouts, one public constructor, Content(...) not Ok(x). |
| [Coding - WebAPI Simple Authorization.md](Coding%20-%20WebAPI%20Simple%20Authorization.md) | Implementing or auditing API-key tiered authorization on a WebAPI - deny by default, key header, constant-time compare, fail-closed factory, what the host authentication pipeline inserts. |
| [Coding - Deployed WebAPI.md](Coding%20-%20Deployed%20WebAPI.md) | Checking a change against api.digiproject.uk or deciding which server runs what - per-prefix Swagger, deployed build lag, sequential querying, cold-partition timeouts, where each log lives. Manual curl only. |
| [Coding - Browser Testing.md](Coding%20-%20Browser%20Testing.md) | Verifying interactive front-end behaviour in a real browser - Playwright, toggles, drag-resize, keyboard, localStorage, phone layouts, rendered output by screenshot statistics; host shell only. |
| [Coding - GIS Administrative Data.md](Coding%20-%20GIS%20Administrative%20Data.md) | Touching administrative_areal_2d, building_2d or anything keyed by a county code or id - a code is not a key (406 parts for 380 counties), fallbackByReference, sibling-part pruning, the Subdivision layer. |
| [Coding - PostgreSQL.md](Coding%20-%20PostgreSQL.md) | Writing Npgsql/PostgreSQL code - NULLS NOT DISTINCT keys, batching, forwarded timeouts and tokens, partition pruning, disposal, whitelisted identifiers, production only through the API, *_Test.conf databases. |
| [Coding - PostgreSQL Distributed Queue Processing.md](Coding%20-%20PostgreSQL%20Distributed%20Queue%20Processing.md) | Designing or maintaining a claim/acknowledge update queue in PostgreSQL - FOR UPDATE SKIP LOCKED, attempts and poison-row retirement, lease vs batch time, ownership, observation vs coverage. |

## Documentation
| File | Read when |
|------|-----------|
| [XML Documentation.md](XML%20Documentation.md) | Reading a public API (documentation/API before .cs) or adding or auditing XML doc comments - every public member, params in signature order, one summary, no docs on partial declarations. |

## GitHub & Wiki
| File | Read when |
|------|-----------|
| [GitHub - Branches and Commits.md](GitHub%20-%20Branches%20and%20Commits.md) | Before the first edit and before every commit - commit on the active version branch (no branch, worktree or PR unless asked), pre-commit sweep, push only when asked, plan files, release bump only on explicit request. |
| [GitHub - Issues.md](GitHub%20-%20Issues.md) | Creating, editing, commenting on, filtering or closing GitHub issues - --body-file encoding traps, mandatory labels and assignee ZiolkowskiJakub, verifying premises, resolution comments, FilterIssues.ps1, blocked_by dependencies. |
| [GitHub - Labels.md](GitHub%20-%20Labels.md) | Applying or syncing GitHub labels or choosing an issue's mandatory 'ai: *' tier - the 21-label taxonomy, tier criteria, SyncLabelsAllRepos.ps1. |
| [GitHub - Sub-Issues.md](GitHub%20-%20Sub-Issues.md) | Splitting a feature into sub-issues - a tracking issue with the shared spec plus one self-contained sub-issue per repository, sibling order as blocked_by. |
| [GitHub - Workspace Setup.md](GitHub%20-%20Workspace%20Setup.md) | Setting up a new machine or changing the local folder layout - one folder per owner, SetupWorkspace.ps1, restoring user files, AI-app root files, WIKI_SYNC_PAT. |
| [GitHub Wiki.md](GitHub%20Wiki.md) | Editing a GitHub wiki page or Home.md - wiki clones under DiGi/wiki, generated API pages never hand-edited, linking every page from Home, SyncWiki.ps1 parser rules. |

## Maintenance
| File | Read when |
|------|-----------|
| [Maintenance - Scripts.md](Maintenance%20-%20Scripts.md) | Running or writing DiGi.Maintenance scripts or making scripted edits - context scripts first, conf keys, *AllRepos sweeps and the -NoCommit trap, BuildAll order, deploy, editing bytes not lines, line endings. |
| [Maintenance - AI Guidelines Propagation.md](Maintenance%20-%20AI%20Guidelines%20Propagation.md) | Adding, splitting, renaming or removing an AI Guideline or regenerating .agents/skills - the Guidelines.json manifest, checklist-first layout with Evidence files, stable section anchors, UpdateAgents.ps1. |
<!-- guidelines:end -->
