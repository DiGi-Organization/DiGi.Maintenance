---
name: coding-webapi-contracts
description: "Use when changing a WebAPI route, parameter, controller or extension, or writing an HTTP client of one - renamed query parameters break clients silently, omitted parameters keep default(T), enum sentinels and integers on the wire, camelCase JSON bodies, /Query client plumbing, failures named by status (503/502) never read as empty, timeout layering, Modify.InitializeAsync entry point, one public constructor, Content(...) instead of Ok(x), no [Produces] over string errors."
---

# Coding — WebAPI Contracts (Controllers and Their HTTP Clients)

The wire contract between a `DiGi.*.WebAPI` controller and its HTTP callers (`DiGi.GIS.WebAPI.UI`, `DiGi.GIS.UI`, background
tasks, page scripts). Live testing: `Coding - Deployed WebAPI.md`; 3D: `Coding - WebAPI GLTF.md`; API keys:
`Coding - WebAPI Simple Authorization.md`.

## 1. The contract has no compiler — a renamed parameter breaks clients silently
> A client reaches a `*.WebAPI` over HTTP only (no `HintPath`, no project reference). Rename a `[FromQuery(Name = "…")]`
> and the client keeps sending the old name, ASP.NET Core ignores it, and the endpoint answers **200 with the unfiltered
> result**.

`itemsbypoint` renamed `type` to `administrativearealtype`; `DiGi.GIS.WebAPI.UI/Controllers/Building2DController.cs` kept
sending `type=County` and got every level covering the point, headed by `Polska` (2 119 202 bytes instead of 387 089 for
`m. St. Warszawa`), resolved no county and dropped `countyid` downstream — for months, with a clean build.
**After changing a route or parameter name, diff both sides by hand:**
```bash
grep -rnoE '\[FromQuery\(Name = "[^"]+"\)\]' --include=*.cs DiGi.GIS.WebAPI/Classes/Controller/ | sort -u
grep -rnoE 'AddParameter\("[^"]+"|api\.digiproject\.uk[^"]*' --include=*.cs DiGi.GIS.WebAPI.UI DiGi.GIS.UI DiGi.GIS.IO | sort -u
grep -rnE "fetch\(|\?[a-z]+=" --include=*.js --include=*.cshtml
```
Consumers of the GIS Web API: `DiGi.GIS.WebAPI.UI` (`Controllers/`, `Query/`, `Create/`), `DiGi.GIS.UI`
(`MainWindow.xaml.cs`, `Modify/TryDownload.cs`), `DiGi.GIS.IO` (`Modify/Update.cs` builds an `ortodatas/imagebyreference`
URL), and the front end. A rename is a **breaking wire change**: accept both names for one release, or ship the client
change with the deployment.

## 2. Binding traps that fail silently
- **An omitted parameter is not a binding failure.** `[ApiController]` answers 400 for a present but unparseable value
  (`administrativearealtype=`, `=Nonsense`), but an **absent** one keeps `default(T)` (`0`, `0.0`, `false`, `(T)0`). When
  absence must be distinguishable, **bind nullable and reject `null`** — a `double x` cannot tell an omitted coordinate
  from `0`.
- **An enum sentinel that is not `0` makes the obvious guard dead code.** `AdministrativeArealType.Undefined` is `-1`, so an
  omitted non-nullable parameter binds `Country (0)` and `== Undefined` never fires — omitting `administrativearealtype` on
  `administrativeareal2Dreferencesbyadministrativearealtype` returns a payload byte-identical to `=0`:
  ```csharp
  // RIGHT - absence is representable, so it can be rejected
  public async Task<IActionResult> GetAsync([FromQuery(Name = "administrativearealtype")] AdministrativeArealType? administrativeArealType, CancellationToken cancellationToken = default)
  {
      if (administrativeArealType is null || administrativeArealType.Value == AdministrativeArealType.Undefined)
      {
          return BadRequest();
      }
  ```
  A genuinely optional filter stays nullable with `null` = "no filter".
- **Send enums as integers** — `urlBuilder.AddParameter("administrativearealtype", (int)AdministrativeArealType.County)`.
  Names bind only while both sides spell them alike: after `Subdivison` → `Subdivision`, `=Subdivision` and `=4` answer
  identically and `=Subdivison` is a hard 400. `….ToString()` is a latent 400 (DiGi.GIS.UI#9 removed the last one).
- **A JSON request body is renamed on the way out.** `JsonContent.Create(value)` / `PostAsJsonAsync` use
  `JsonSerializerDefaults.Web` (camelCase): `Email`/`Password` travel as `{"email":…,"password":…}`. It works while the
  receiver is case-insensitive (ASP.NET Core is) and surfaces elsewhere as a *domain* refusal. **Pass
  `options: JsonSerializerOptions.Default` whenever the contract names the properties** (naming policy `null`, a cached
  instance). Unaffected: primitive/collection bodies, and `JsonObject`/`JsonArray` bodies (keys are data). Exposed: body
  *objects* (`Building2DReferencesByPagingParameter`, `CountByAdministrativeAreal2DIdsParameter`, the login relay's
  `UserLogin`).

## 3. Client / proxy structure (reference: `DiGi.GIS.WebAPI.UI`)
The `Coding - General.md` architecture applies unchanged.
- **One base URI constant**, never a literal: `Constants.Default.GISWebAPIUri` (+ `…Uri_Development`), every URL composed
  from it (`public const string TerrainUri = GISWebAPIUri + "/gis/terrain";`).
- **HTTP plumbing lives in `/Query`**, one member per file, extensions on `HttpClient?`, `T : Core.Interfaces.ISerializableObject`:

  | Member | Returns |
  |---|---|
  | `JsonAsync(requestUri, cancellationToken)` | raw body, for verbatim relay |
  | `ItemsAsync<T>(requestUri, cancellationToken)` | `List<T>?` via `Core.Convert.ToDiGi<T>` |
  | `ItemAsync<T>(requestUri, cancellationToken)` | the first item |
  | `PostJsonAsync<T>(requestUri, value, cancellationToken)` | raw body, for body-criteria endpoints (the verb stays in the name — the recognised exception to property-like `Query` names) |
  | `…ResponseAsync` siblings (`Query.Building2DReferenceResponseAsync`) | body **plus the upstream status**, for actions that must report it |
- **A failure never reads as empty or absent.** A page assembled from independent requests still degrades panel by
  panel, but each failing request is named by its own status: no upstream answer (unreachable, timeout) → **503**; an
  upstream fault answered → **502**; an upstream 404 → 404, other answered statuses mirrored; a known scope with no rows →
  200 with an empty list (or 204 where the panel contract hides on it); a bad caller value → 400; never map an upstream
  failure to `BadRequest()` or to the empty scope's 204. Collapsing every failure to `null` made an outage read as
  "Building not found" (`DiGi.GIS.WebAPI.UI#40`, `#48`); use the status-preserving `…ResponseAsync` sibling where the
  status matters, and keep the `null`-collapsing helpers for decoration rendered as *unknown* (`Coding - WPF Deferred Loading.md` §4).
- **Do not reuse `DiGi.WebAPI.Query.GetAsync<T>` for pages** — it throws on any non-2xx and takes no token (it derives one
  from `PostOptions.Delay`); it fits background tasks.
- **`CancellationToken` on every action issuing an outbound request**, last, threaded through — otherwise a navigation
  away leaves the request running. Rethrow only a requested cancellation (`Coding - General.md` §1.22).
- **Three timeouts govern a `GISWebAPIManager` request; the smallest wins:**

  | Layer | Default | Where |
  |---|---|---|
  | `PostOptions.Delay` — each attempt | 20 s | `DiGi.WebAPI/Classes/Options/PostOptions.cs` |
  | `HttpClient.Timeout` — every request | 600 s | `DiGi.GIS.WebAPI/Create/ServiceProvider.cs` |
  | `commandtimeout` — server database budget | 600 s | e.g. `BuildingDataController` |

  A bulk write on default `PostOptions` is cut **by the client** at 20 s on an endpoint sized for 600 s; the
  `OperationCanceledException` that `UpdateItemsAsync` rethrows does not match a caller's
  `when (cancellationToken.IsCancellationRequested)` filter and reads as an unexplained item error. `RetryCount` 3 → four
  delays before failing (safe: writes conflict on their key). **Keep `HttpClient.Timeout` ≥ the server `commandtimeout`**
  (it was 60 s until DiGi.GIS.YOLO.UI#14 and silently cancelled slow reads; raising `Delay` past it does nothing). Measured:
  `tablebybuildingdatabyreferencesparameter`, 10 000 references, every column — 5.6 s / 33 MB.

## 4. Do not build on an endpoint that is not deployed yet
Check what runs: `GET /information/controllers` (`InformationalVersion` with commit hash, compare with `git log`) and
`GET /information/endpoints?includeignored=true` (exact route, verb, parameter names). A client that must ship first gates
the call with a `TODO [MarkerName]` (`Coding - General.md` §1.12) whose removal condition is observable ("once
`/information/controllers` reports a build carrying `idsbycode`").

**A live probe verifies the response, not the request.** Authentication and validation paths answer one status for every
cause (`POST /user/login` → 401 for an unknown email, no credential, a wrong password, wrong property names, or no body).
Where the failure status is uniform, **record the request**: point the base URI constant at a local stub for the test and
assert the exact bytes and headers (that found the camelCase body of §2 and a relay clearing the session cookie on 401,
which made refresh-and-retry impossible). Stub traps: `HttpClient` sends `JsonContent` **chunked** (a stub reading
`Content-Length` records an empty body); revert the URI, rebuild and grep the stub host across
`--include=*.cs --include=*.cshtml --include=*.js` before committing.

## 5. Controller side — shape, activation, responses
- **Extension entry point:** each `DiGi.*.WebAPI` exposes `public static async Task InitializeAsync(this IServiceCollection serviceCollection)`
  in `Modify/InitializeAsync.cs`, registering its dependencies as concrete-type singletons. The host finds it by
  reflection (a type named `Modify`, a public static `Initialize`/`InitializeAsync` taking exactly one
  `IServiceCollection`); anything else is skipped with only "Method initialization skipped" logged, the dependencies are
  missing, and every action answers 500.
- **Controller shape:** `[ApiController] [Route("<prefix>/[controller]")] public class XController : WebAPIController`;
  actions `Task<IActionResult> XxxAsync(…, CancellationToken cancellationToken = default)` with a lower-case concatenated
  route and a unique name: `[HttpGet("itemsbycountyid", Name = $"{nameof(XController)}_{nameof(XxxAsync)}")]` (duplicate
  names fail at start-up). GIS controllers carry `[TransientDatabaseFailure]`: a transient `NpgsqlException` →
  **503 + `Retry-After: 30`** (DiGi.GIS.WebAPI#71); a general catch logs and answers 500.
- **Exactly one public constructor.** Hosts call plain `AddControllers()`, so MVC activates through
  `ActivatorUtilities.CreateFactory(type, Type.EmptyTypes)`; a second public constructor throws "Multiple constructors
  accepting all given argument types" on **every** action as 500 (a test convenience constructor took down
  `gis/building2d` for a day, DiGi.GIS.WebAPI#6). Diagnose: a parameter-guard probe (`?id=0`) answering **500 instead of
  400** fails before the body. Guard: copy `DiGi.Test/DiGi.GIS.WebAPI.xUnit/Facts/ControllerActivation.cs` (builds the real
  factory for every `WebAPIController`, no database).
- **Return a DiGi object as `Content(Core.Convert.ToSystem_String(x), "application/json")`, never `Ok(x)`** — the MVC
  formatter writes camelCase without `_type`, and the client's `Core.Convert.ToDiGi<T>` returns `null` ("Nothing left to
  verify" while the API logged a successful draw, DiGi.GIS.WebAPI#39). Unit tests cannot see it (plain STJ keeps
  `[JsonPropertyName]`); only a live body can. `Ok(...)` is for MVC POCOs (`ProblemDetails`, plain records).
- **No action-level `[Produces("image/jpeg")]` over string-bodied error paths:** negotiation finds no formatter for the
  string 400/500/503 and answers **406**, masking the error (`File()`/`NotFound()` bypass it). Declare the type on the
  success response only: `[ProducesResponseType(typeof(FileContentResult), 200, "image/jpeg")]`. A uniform 406 → suspect a
  masked error path.

## 6. Checklist
**Changing a controller**
- [ ] Renamed/removed a `[FromQuery(Name = "…")]`? Every client and front-end query string grepped.
- [ ] Absence matters? Nullable binding, `null` rejected; no guard against a non-`0` sentinel.
- [ ] `CancellationToken` last and passed to the converter beneath.
- [ ] `Modify.InitializeAsync(this IServiceCollection)` present; route names unique; one public constructor;
      `ControllerActivation` fact present.
- [ ] DiGi objects via `Content(Core.Convert.ToSystem_String(x), "application/json")`; failures answer 503/502/500, not
      empty; no action-level `[Produces]` over string errors.

**Writing a client**
- [ ] Base URI from a constant; `/Query` helpers; enums as integers; `JsonSerializerOptions.Default` for named bodies;
      body names confirmed on the wire.
- [ ] Each panel degrades on its own, and an upstream failure is reported by its status, never as empty or 404.
- [ ] `PostOptions.Delay` sized for the batch; `HttpClient.Timeout` ≥ server `commandtimeout`.
- [ ] Every endpoint used is deployed, or gated behind a `TODO [MarkerName]`.
