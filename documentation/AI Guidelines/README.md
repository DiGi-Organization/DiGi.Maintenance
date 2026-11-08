# AI Guidelines — Index

> [!IMPORTANT]
> **Portability Rule:** all markdown files use **relative paths**; never an absolute machine path (`C:\Users\...`).

Entry points: `DiGi/CLAUDE.md` (Claude Code) and `.agents/AGENTS.md` (other agents) carry the always-apply rules and route
here. Files are **read on demand**, one per task; each becomes a generated skill. Maintaining this folder:
[Maintenance - AI Guidelines Propagation.md](Maintenance%20-%20AI%20Guidelines%20Propagation.md).

## Coding
| File | Read when |
|------|-----------|
| [Coding - General.md](Coding%20-%20General.md) | Writing or editing any C# — naming/typing, `Query`/`Modify`/`Create`/`Convert`, enums, constants, assets, logging, cancellation, temporary-code markers, binding traps. |
| [Coding - Serialization.md](Coding%20-%20Serialization.md) | Creating or changing a `SerializableObject` type or options class, or debugging a JSON round trip. |
| [Coding - Host Dependencies.md](Coding%20-%20Host%20Dependencies.md) | Adding a NuGet package; `FileNotFoundException`/partial results in a host; `CS0012`/`CS0246` walls; `deps.json`; after changing a public surface. |
| [Coding - Project Setup.md](Coding%20-%20Project%20Setup.md) | New project or repository from `templates/`, `.editorconfig`, `Directory.Build.props`/LangVersion, Roslyn analyzers. |
| [Coding - Automatic Tests.md](Coding%20-%20Automatic%20Tests.md) | Writing xUnit facts — structure, fixtures, build-before-test, duration classes, reproduce-first, guards, database facts. |
| [Coding - Performance.md](Coding%20-%20Performance.md) | Optimizing (no caching unless allowed), benchmark and parity facts, the wiki `Benchmark.md` page. |
| [Coding - References.md](Coding%20-%20References.md) | Comparing or keying `IReference`/`IUniqueReference` (`==` is a silent bug). |
| [Coding - Geometry.md](Coding%20-%20Geometry.md) | Orienting, closing, triangulating, hashing or sweeping `DiGi.Geometry`/`DiGi.Solar` geometry. |
| [Coding - ComputeSharp.md](Coding%20-%20ComputeSharp.md) | Writing or changing an `IComputeShader` (odd/odd layout defect, guard and parity facts). |
| [Coding - Grasshopper.md](Coding%20-%20Grasshopper.md) | Grasshopper/Rhino components, Goo/Param pairs, `Inspect`, `.gha` project setup. |
| [Coding - Background Tasks.md](Coding%20-%20Background%20Tasks.md) | Tray-application background tasks, their `UI<Task>` dialogs and registration, post tasks. |
| [Coding - WPF Deferred Loading.md](Coding%20-%20WPF%20Deferred%20Loading.md) | A WPF window needing slow data; STA facts; the off-screen WPF render harness. |
| [Coding - YOLO.md](Coding%20-%20YOLO.md) | The YOLO Year Built detector — runner, `model.pt`, training outside the workspace, scratch, allowlisted deploy. |
| [Coding - Laya.md](Coding%20-%20Laya.md) | The Laya decision model — checkpoint SHA identity, training, calibration, `DeployLaya.ps1`, host venv. |
| [Coding - WebAPI GLTF.md](Coding%20-%20WebAPI%20GLTF.md) | Web APIs on `DiGi.GLTF` — converters, batching, `gltf-viewer-core.js`, payload facts. |
| [Coding - WebAPI Contracts.md](Coding%20-%20WebAPI%20Contracts.md) | Changing a route/parameter/controller, writing an HTTP client, failure statuses, extension entry point. |
| [Coding - WebAPI Simple Authorization.md](Coding%20-%20WebAPI%20Simple%20Authorization.md) | API-key tiers, deny-by-default, `key` header, the host's authentication pipeline. |
| [Coding - Deployed WebAPI.md](Coding%20-%20Deployed%20WebAPI.md) | Testing against `api.digiproject.uk` (per-prefix Swagger, gotchas) and which server runs what. |
| [Coding - Browser Testing.md](Coding%20-%20Browser%20Testing.md) | Verifying interactive front-end behaviour with Playwright, rendered output, phone layouts. |
| [Coding - GIS Administrative Data.md](Coding%20-%20GIS%20Administrative%20Data.md) | `administrative_areal_2d`, `building_2d`, anything keyed by a county code/id; the Subdivision layer. |
| [Coding - PostgreSQL.md](Coding%20-%20PostgreSQL.md) | Npgsql converters, keys, batching, timeouts, partition pruning, identifiers, production vs `*.conf`, test databases. |
| [Coding - PostgreSQL Distributed Queue Processing.md](Coding%20-%20PostgreSQL%20Distributed%20Queue%20Processing.md) | Claim/acknowledge update queues, attempts, ownership, observation, coverage. |

## Documentation
| File | Read when |
|------|-----------|
| [XML Documentation.md](XML%20Documentation.md) | Reading `documentation/API/` before source; adding or auditing XML doc comments. |

## GitHub & Wiki
| File | Read when |
|------|-----------|
| [GitHub - Branches and Commits.md](GitHub%20-%20Branches%20and%20Commits.md) | Before the first edit and every commit — working branch, pre-commit sweep, plan files, pulling all repos, release (explicit request only). |
| [GitHub - Issues.md](GitHub%20-%20Issues.md) | Creating, editing, verifying, closing issues; `--body-file` encoding; dependencies. |
| [GitHub - Labels.md](GitHub%20-%20Labels.md) | Label taxonomy and the mandatory `ai: *` tier. |
| [GitHub - Sub-Issues.md](GitHub%20-%20Sub-Issues.md) | Splitting a feature into a tracking issue plus per-repository sub-issues. |
| [GitHub - Workspace Setup.md](GitHub%20-%20Workspace%20Setup.md) | Folder layout, new machine, `user files/` restore, migration, `WIKI_SYNC_PAT`. |
| [GitHub Wiki.md](GitHub%20Wiki.md) | Editing wiki pages and `Home.md`. |

## Maintenance
| File | Read when |
|------|-----------|
| [Maintenance - Scripts.md](Maintenance%20-%20Scripts.md) | Running or writing `DiGi.Maintenance/Scripts`; scripted edits and line endings. |
| [Maintenance - AI Guidelines Propagation.md](Maintenance%20-%20AI%20Guidelines%20Propagation.md) | Adding, renaming, splitting or removing a guideline; regenerating `.agents/skills`. |
