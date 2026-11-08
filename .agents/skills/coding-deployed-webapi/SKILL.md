---
name: coding-deployed-webapi
description: "Use when checking a change against the live WebAPI at api.digiproject.uk or deciding which server runs what - per-prefix Swagger documents (fetch one operation, not the full document), the deployed build lagging the repository (commit hash in InformationalVersion), the county-reference-building GET recipe, sequential querying, cold-partition timeouts, CRLF id lists giving 000, the database server vs web server vs development machines and where each log lives. Manual curl only, never DiGi.Test."
---

# Coding — Deployed WebAPI (Live Endpoint Testing)

Manual, on-demand checks against production (`https://api.digiproject.uk`). **Never add them to `DiGi.Test`.** Which
machine runs what — and so where to measure and where a log is — is §5.

## 1. Endpoints & Swagger
- Base URL `https://api.digiproject.uk` (root `/` answers 404).
- **`InformationController`:** `GET /information/health` (status, `ServerTimeUtc`, uptime, PID), `/version` (host and
  `DiGi.WebAPI` versions, CLR), `/controllers` (deployed controllers, assembly metadata, route prefixes), `/endpoints`
  (routes, verbs, parameters; `?includeignored=true` adds write/internal routes hidden from Swagger), `/assemblies`
  (loaded assemblies — verifies `extensions/`), `/system` (memory, GC, thread pool, OS). Protected ones need the key (§2).

### Fetch the smallest Swagger document that answers the question
`DiGi.WebAPI.WindowsService` publishes one OpenAPI document per **first route segment** plus a full one:

| URL | Contents | Size (2026-10-01) |
|---|---|---|
| `/swagger/gis/swagger.json` | `DiGi.GIS.WebAPI` — 95 paths, 83 schemas | ~407 KB |
| `/swagger/information/swagger.json` | diagnostics — 6 paths | ~27 KB |
| `/swagger/user/swagger.json` | `DiGi.User.WebAPI` — 5 paths | ~10 KB |
| `/swagger/gltf/swagger.json` | `DiGi.GLTF.WebAPI` — 2 paths | ~18 KB |
| `/swagger/swagger.json` (= `/swagger/full/swagger.json`) | everything — 108 paths, 99 schemas | ~454 KB |

1. Route/parameter names only → skip Swagger: `InvestigateServer.ps1 -Endpoints -Controller "<Name>"` (§2).
2. `user`, `gltf`, `information` → read the prefix document whole (self-contained).
3. `gis` → extract the operation and its schemas, not the file:
   ```powershell
   $doc = Invoke-RestMethod "https://api.digiproject.uk/swagger/gis/swagger.json"
   $doc.paths.PSObject.Properties.Name -like "*/terrain/*"                  # routes (keys are lower case)
   $doc.paths."/gis/terrain/mesh3dbycircle" | ConvertTo-Json -Depth 20     # one operation
   $doc.components.schemas.Mesh3D | ConvertTo-Json -Depth 20               # the schema it references
   ```
   `Invoke-RestMethod` decodes UTF-8; `curl.exe | ConvertFrom-Json` goes through the console code page
   (`GitHub - Issues.md` §1).
4. The full document only when several prefixes are needed at once.

Host rules: the document name is the lower-case first segment (`gis/[controller]` → `gis`, `[controller]` on
`UserController` → `user`); a new prefix gets its own document automatically (not `full`/`swagger`). **A 404 on a prefix
document means no Swagger-visible endpoint, not a missing extension** (`communication` today — use
`/information/endpoints?includeignored=true`). A prefix document's `info.version` is its extension's version; the full one
carries the host's. If `/swagger/swagger.json` answers 404 the host predates `DiGi.WebAPI.WindowsService#2` — use
`/swagger/v1/swagger.json`.

### Swagger contract limitations
1. **Incomplete list:** the base `WebAPIController` sets `[ApiExplorerSettings(IgnoreApi = true)]`; an action appears only
   when it or its controller opts back in (`IgnoreApi = false`) — all of `user/*`, `information/*`, but not the write
   endpoints (`updateitem(s)`) or several `item*` reads. Use `/information/endpoints?includeignored=true`.
2. **Payload schemas follow the writer** (`WireFormatSchemaFilter`, `DiGi.WebAPI.WindowsService#3`, enums since `#6`;
   production payloads validate strictly):
   - **DiGi `ISerializableObject`** (DiGi serializer): exact member names (PascalCase by convention; a member without
     `[JsonPropertyName]` keeps its field name, `Building.roofTypeId`), a required `_type` (`"Namespace.Type,ShortAssembly"`),
     every member `required` (nulls written explicitly), always an object — also for an `IEnumerable` type (`EPWFile`).
   - **Open DiGi schemas** (interface, abstract, own `ToJsonObject`) declare only `_type` and allow additional properties;
     a concrete type others derive from (`WeatherRecord`) lists its members and allows more.
   - **MVC payloads** (`Ok(...)` POCOs: `UpdateItemsResult`, `ProblemDetails`) are camelCase with **string** enums.
   - **Enums inside DiGi payloads are integers**, declared inline (`type: integer`, values in numeric order, names in
     `x-enum-varnames`/`x-enumNames`, `Wire values (integer): Undefined = -1, ...` in the description; nullable lists
     `null` last; `[Flags]` lists bits). Enum **components** are the name strings that query parameters and MVC payloads
     use; a query parameter `$ref`s its component and says to send the integer (`Coding - WebAPI Contracts.md` §2).
   - **DiGi request bodies are read by MVC:** a `[FromBody]` DiGi parameter (`HistogramRequestParameter`) is documented in
     the DiGi wire format, which MVC accepts (case-insensitive, `_type` ignored, enums as integers or names); a plain
     nested object (`FilterGroup`, `FilterCondition`) keeps camelCase with string enums.

### The deployed build lags the repository
> **A 404 usually means "not deployed yet", not "wrong URL".**

`/information/controllers` and `/version` return each assembly's `InformationalVersion` with its **commit hash** — compare
with `git log` before concluding anything (2026-08-21: `DiGi.GIS.WebAPI` 0.8.7 / `e6dd012` answered 404 for `idsbycode`,
`administrativeareal2Dreferencesbyids`, `building2d/referenceuniquenesssummary` and five `gis/terrain` diagnostics while
they sat committed). The hash is HEAD's **even for a build from uncommitted changes** (no dirty marker) — it proves the
base, not the content. Tell route-absent from data-absent with something that certainly exists:
`idsbycode?code=1465&administrativearealtype=2` → 404 while `idbycode` → `55417`. Building a client before the endpoint is
live: `Coding - WebAPI Contracts.md` §4.

## 2. Investigation tools and access rules
- Use `InvestigateServer.ps1` or `curl.exe` (not `WebFetch`: GET-only, no custom headers).
- **Read-only GETs are safe. Never call POST/PUT/DELETE write endpoints without explicit authorization** — this is live
  production.
- Protected diagnostics (`/system`, `/assemblies`, `/controllers`, `/endpoints?includeignored=true`, commit hashes on
  `/version`) need the key in the `key` **request header** (never the query string) and deny by default with 401; the key
  lives in `user files/WebAPI_Diagnostics.conf` (tier model, deployment: `Coding - WebAPI Simple Authorization.md`).
- **This API is the only way to measure production** — a `*.conf` names a development database
  (`Coding - PostgreSQL.md` §6).
```powershell
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/InvestigateServer.ps1" -All                    # health, version, system, controllers (key read from the conf)
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/InvestigateServer.ps1" -Endpoints -IncludeIgnored
PowerShell -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/InvestigateServer.ps1" -Endpoints -Controller "Terrain"
curl.exe -s "https://api.digiproject.uk/information/health"
curl.exe -s -H "key: <key>" "https://api.digiproject.uk/information/endpoints?includeignored=true"
```

## 3. Read-path recipe (county → reference → building)
| Step | Endpoint | Returns |
|---|---|---|
| 1 | `GET gis/administrativeareal2d/administrativeareal2Dreferencesbyadministrativearealtype?administrativearealtype=2` | `AdministrativeAreal2DReference[]` — county **parts** (`Id`) |
| 2 | `GET gis/building2d/referencesbycountyid?countyid=<id>` | `string[]` (cadastral references) |
| 3 | `GET gis/building/itembyreference?reference=<ref>&countyid=<id>` | `200` `Building` or `204` (no 3D match) |
| 4 | `GET gis/building/itembylatestcreatedat?countyid=<id>` | `200` or `204` |

## 4. Operational gotchas
- **Query sequentially.** Parallel requests exhaust the Npgsql pool and healthy endpoints answer 500
  (`yearbuiltdata/itemsbyreferences`: 500 under 12 workers, 200 in 0.07 s alone; `terrain/coveragebycountyid` needed a
  service restart). Re-test every 500 alone; keep sweeps to a handful of workers.
- **A 500 on a large cold partition is usually a timeout** — cache warmth decides, not row count (county 204: 500 after
  55.6 s, then 200 in 0.13 s). Retry or warm the partition first. (`referencesbycountyid`'s former hard-coded 30 s is
  fixed — it takes `commandtimeout`, default 600, DiGi.GIS.WebAPI#27 — but an older deployment may still have it.)
- **Prefer `estimated=true` counts in sweeps** (`countbycountyid`: ~33 s exact vs ~0.05 s estimated, identical on every
  county checked; an exact 406-county sweep is ~37 minutes of production load).
- **County `Id` = polygon part; a `building_2d` reference is unique only per `countyid`** — step 1 returns 406 rows for 380
  codes, `&uniquecode=true` picks an arbitrary part (`Coding - GIS Administrative Data.md`).
- `itembyreference` takes the **cadastral** reference from `referencesbycountyid`, not a CityGML `UniqueId` (stripping
  `ID-` fails), and **always with `countyid`** (omitting it answers 500).
- **An unknown or omitted query parameter is not rejected** (a stale name returns the unfiltered result; an omitted one
  keeps `default(T)`) — pass every filter explicitly, and suspect a parameter name when a response is too large or headed
  by the wrong kind of row (`Coding - WebAPI Contracts.md` §1–2). Integer `4` is the only `Subdivision` token every build
  accepts.
- **`gis/terrain/mesh3d*` 404 can mean the radius is below the 10–100 m lattice step** (at `x=638000&y=486000`: radius
  50 → 404, 100+ → 200, elevations 111–112 m). Widen it before concluding the table is missing.
- **`000` on every call of a sweep is a client bug until proven otherwise:** an id list written by Python on Windows is
  CRLF, `while read -r id` keeps the `\r`, and curl fails before connecting — `%{http_code}` `000` with an empty body, as a
  hang would show. Normalise (`tr -d '\r'`, `open(path, 'w', newline='\n')`) and print `%{time_total}` beside
  `%{http_code}`: a malformed URL returns instantly with zero timings; a real hang shows `time_appconnect` and the full
  timeout. Uniform from request #1 = client; degrading partway = server.
- **Hung API vs UI regression:** when the API hangs, IIS still finishes TLS but `/information/health` never answers, while
  the UI's pages load and every relay fails (`503`, or `204` where a relay collapses failures). One call:
  `curl.exe -s -o NUL -w "%{time_appconnect} %{time_starttransfer} %{http_code}\n" https://api.digiproject.uk/information/health`
  (a long server task starving host memory did this, DiGi.GIS.PostgreSQL#97).

## 5. Deployment topology — which machine runs what
| Role | Runs | Reached through |
|---|---|---|
| **Database server** (separate, stronger) | production PostgreSQL; `DiGi.WebAPI.WindowsService` with the GIS Web API and `extensions\*`; deployed tools (`bodyplan.Importer`, the tray application). **No development tooling** — no Visual Studio, source, builds or xUnit | `https://api.digiproject.uk` |
| **Web server** | `DiGi.GIS.WebAPI.UI` under IIS; no development tooling | `https://gis.digiproject.uk` |
| **Development / test machines** | editing, builds, `DiGi.Test`, development databases behind `*.conf` | — never production (`Coding - PostgreSQL.md` §6) |

The tray application (`DiGi.GIS.PostgreSQL.UI`) is installed on **both** servers; a task runs where it was started.
Hardware is deliberately not recorded — read it at measurement time and cite the measurement (issue comment, date).
- **Tests never run on a server**; a server runs only what `Scripts/Deploy.ps1` carried there. Verify on it with the
  deployed tools (`bodyplan.Importer` and its `reports/`, the tray) or through the API. A test's write found in a database
  came from a development machine — first ask whether that database is production at all (bodyplan#47/#48,
  `Coding - PostgreSQL.md` §6).
- **Measure a limit on the machine that runs the code, and name the role.** `DiGi.Solar#7` measured the shading solver on
  the database server believing it was the web server: its limits (100 receivers, "about 16 s") were 4–10× too generous —
  51–159 s on the web server, cut to 30 by `DiGi.GIS.WebAPI.UI#59`. Relative findings transferred; absolute times did not.
- **A log lives on the machine that ran the code:** the GIS Web API's Serilog files on the database server (per extension,
  `Coding - General.md` §1.21); `DiGi.GIS.WebAPI.UI` writes `logs\log-yyyyMMdd.txt` beside itself on the web server (IIS
  discards console output); a tray task's log on the server that ran it. Searching a development machine proves nothing.
- **A slow page is not necessarily a slow API:** compare both logs (in `#59` the API answered in milliseconds; the minutes
  were the web server's own computation).
- **Heavy computation competes with serving pages** on the web server: gate it (one solve at a time, a size ceiling
  answering 413), sized from web-server measurements.
- **A development machine often runs the tray application twice** — the deployed copy under `SOFTWARE_DIRECTORY` and the
  repository `bin` look identical (same icon, `extensions\`, log lines except paths; a run from `bin` cost two pipeline
  runs). Check: `Get-Process -Name "DiGi.GIS.PostgreSQL.UI.Application" | Select-Object Id, StartTime, Path`. The `bin`
  instance locks its dlls (the next build fails until it exits). A missing **Server** tab is a start-up database probe that
  failed once silently — relaunch, do not redeploy.
