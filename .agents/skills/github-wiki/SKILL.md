---
name: github-wiki
description: "Use when editing a GitHub wiki page or Home.md - wiki clones under DiGi/wiki, generated API pages never hand-edited, linking every page from Home, SyncWiki.ps1 parser rules."
---

# AI Guidelines: GitHub Wiki Pages

## 1. Layout
- Each repository's wiki is its own Git repository, `https://github.com/DiGi-Organization/<repo>.wiki.git`, default branch
  **`master`**; a page URL is the `.md` file name without extension (`Home.md` = landing page).
- Local clones live in `DiGi/wiki/<repo>.wiki/` (from the workspace root:
  `git clone https://github.com/DiGi-Organization/<repo>.wiki.git "wiki/<repo>.wiki"`; `SetupWorkspace.ps1 -IncludeWikis`).
- A new repository's wiki exists only after its first page is created in the web UI (`GitHub - Workspace Setup.md` §4).

## 2. Generated vs hand-authored pages
| Pages | Source | Rule |
|---|---|---|
| API pages | XML doc comments → `documentation/API/<Assembly>/*.md` at build → copied by CI | **Never hand-edit**; edit the C# XML docs |
| `Home.md`, `Benchmark.md`, guides | written in the wiki clone | Edit and commit in the clone; CI never overwrites them |

`Directory.Build.targets` sets `<DefaultDocumentationAssemblyPageName>$(AssemblyName).Overview</DefaultDocumentationAssemblyPageName>`
so multi-assembly repositories do not collide — never revert it to `index.md`.

**CI sync:** `.github/workflows/sync-wiki.yml` runs on a push to `main`/`master`: `SyncWiki.ps1` clones the wiki to
`$env:TEMP\DiGi.WikiTemp_<repo>`, copies `documentation/API/*`, commits `chore: auto-update API documentation` and pushes
if anything changed (secret: `WIKI_SYNC_PAT`, `GitHub - Workspace Setup.md` §4).

## 3. Editing
`cd DiGi/wiki/<repo>.wiki` → `git pull` → edit hand-authored pages only → cross-link by file name → `git push origin HEAD`
(`master`). **Link every new hand-authored page from `Home.md`.** Benchmark pages: `Coding - Performance.md` §4.

## 4. `Home.md`
**No H1** (GitHub renders "Home"). `SyncWiki.ps1` compiles five blocks: (1) the repository description from its
`$descriptions` table, (2) target framework parsed from the `.csproj` files, (3) preserved custom content, (4) dependencies
from internal project references, (5) the ecosystem footer:
```markdown
[Repository Description]

* **Target Framework:** `[FrameworkName]`

[Custom Content Block - Preserved across syncs]

### 🔗 Dependencies
*   [[DependencyRepoName1|https://github.com/DiGi-Organization/[DependencyRepoName1]/wiki]]

---

## 🌐 DiGi Ecosystem
* **Foundational:** [DiGi.Core](https://github.com/DiGi-Organization/DiGi.Core/wiki) | [DiGi.Math](https://github.com/DiGi-Organization/DiGi.Math/wiki) | [DiGi.Unit](https://github.com/DiGi-Organization/DiGi.Unit/wiki) | [DiGi.Log](https://github.com/DiGi-Organization/DiGi.Log/wiki)
* **Geometry & Graphics:** [DiGi.Geometry](https://github.com/DiGi-Organization/DiGi.Geometry/wiki) | [DiGi.GLTF](https://github.com/DiGi-Organization/DiGi.GLTF/wiki) | [DiGi.Rhino](https://github.com/DiGi-Organization/DiGi.Rhino/wiki)
* **GIS & Data:** [DiGi.GIS](https://github.com/DiGi-Organization/DiGi.GIS/wiki) | [DiGi.OSM](https://github.com/DiGi-Organization/DiGi.OSM/wiki) | [DiGi.BDOT10k](https://github.com/DiGi-Organization/DiGi.BDOT10k/wiki)
* **Simulation:** [DiGi.Analytical](https://github.com/DiGi-Organization/DiGi.Analytical/wiki) | [DiGi.Solar](https://github.com/DiGi-Organization/DiGi.Solar/wiki) | [DiGi.Tas](https://github.com/DiGi-Organization/DiGi.Tas/wiki)

*Part of the DiGi software suite for BIM and CAD integrations.*
```
Parser rules protecting block 3 (write custom content so they do not eat it):
1. Everything after a line matching `^---`, `^### 🔗 Dependencies` or `^## 🌐 DiGi Ecosystem` is discarded (`$skipState`).
2. Lines matching `^# .*Wiki` or `Welcome to the .* wiki!` are dropped.
3. Legacy generated lines are filtered: `^\s*\*\s+\*\*Target\s+Frameworks?:\*\*`; ecosystem links
   `^\s*\*\s+\[DiGi\.[A-Za-z0-9\.]+\]\(https://github\.com/(DiGi-Organization|ZiolkowskiJakub)/` (old owner kept for pages
   generated before the 2026-10-14 transfer); category labels `^\s*\*\s+\*\*Foundational:\*\*`,
   `^\s*\*\s+\*\*Geometry\s+&\s+Graphics:\*\*`, …; `^\s*\*Part of the DiGi software suite`.
