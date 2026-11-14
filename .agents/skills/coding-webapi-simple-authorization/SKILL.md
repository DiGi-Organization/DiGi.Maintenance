---
name: coding-webapi-simple-authorization
description: "Use when implementing or auditing API-key tiered authorization on a WebAPI - deny by default, key header, constant-time compare, fail-closed factory, what the host authentication pipeline inserts."
---

# Coding — WebAPI Simple Authorization (Tiered Access & API Key)

Lightweight API-key tiers for WebAPI controllers and diagnostic/administrative endpoints, configured by a local `.conf`
instead of an OAuth2/JWT provider.

> [!CAUTION]
> **Deny by default.** Every branch that is not an exact key match returns **401**: a missing or unreadable configuration,
> `Enabled=false`, a blank configured key, a blank supplied key. The first version returned "authorized" when enforcement
> was not configured, and `api.digiproject.uk` served host telemetry, the assembly inventory and the internal route catalog
> to anonymous callers — with a valid key unused in the conf and a green 28-test suite.

## 1. Tiers
- **Public:** health/readiness (`GET /information/health`), coarse version (`/information/version` without commit hashes),
  the route catalog the API explorer already publishes (`/information/endpoints`), ordinary unauthenticated reads.
- **Protected (`key` header):** host telemetry (`/information/system`), assembly inventory (`/information/assemblies`),
  controller inventory (`/information/controllers`), hidden/write route catalogs (`/endpoints?includeignored=true`), commit
  hashes on public responses (§6), administrative and maintenance actions.

## 2. Pattern (`DiGi.WebAPI`: `Classes/DiagnosticsConfiguration.cs`, `Query/IsAuthorized.cs`)
**Model** — a serializable `[Feature]Configuration` with three members: the key, whether enforcement is configured, and
the one escape hatch (standard three constructors, `Coding - Serialization.md` §3):
```csharp
public class DiagnosticsConfiguration : SerializableObject, IWebAPISerializableObject
{
    [JsonInclude, JsonPropertyName(nameof(Enabled))]
    private readonly bool enabled;

    [JsonInclude, JsonPropertyName(nameof(Key))]
    private readonly string? key;

    [JsonInclude, JsonPropertyName(nameof(Open))]
    private readonly bool open;

    // The parameterless form denies every protected request - it is what an unconfigured host gets.
    public DiagnosticsConfiguration(string? key = null, bool enabled = false, bool open = false)
    {
        this.key = key;
        this.enabled = enabled;
        this.open = open;
    }
}
```
`Open` keeps local development usable: the **only** setting granting unauthenticated protected access, never set on a
deployed host, logged as a warning when honoured. File name constant: `Constants.FileName.WebAPI_Diagnostics =
"WebAPI_Diagnostics.conf"`.

**Factory** (`/Create/DiagnosticsConfiguration.cs`) — probe the explicit path, the base directory, the current directory;
read `Key`, `Enabled` (default: key non-blank), `Open` (default `false`) with `ConfigurationFile.GetValue<T>`; then the
`DIGI_DIAGNOSTICS_KEY` environment variable; **finally fail closed**: `new DiagnosticsConfiguration(null, enabled: true)`.
Probe only paths the build produces (`CopyFiles`/`CopyUserFiles` flatten into the output root — `bin/user files/` never
exists). Log a Warning on every path ending in an unusable configuration.

**Check** (`/Query/IsAuthorized.cs`):
```csharp
public static bool IsAuthorized(this DiagnosticsConfiguration? diagnosticsConfiguration, string? key)
{
    if (diagnosticsConfiguration is null)
    {
        return false;
    }

    if (diagnosticsConfiguration.Open)
    {
        return true;
    }

    if (!diagnosticsConfiguration.Enabled)
    {
        return false;
    }

    string? key_Configured = diagnosticsConfiguration.Key;
    if (string.IsNullOrWhiteSpace(key_Configured) || string.IsNullOrWhiteSpace(key))
    {
        return false;
    }

    return CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(key_Configured), Encoding.UTF8.GetBytes(key));
}
```
- **`Enabled == false` means "no key check configured", never "let everyone in"** — reading it the other way shipped the
  endpoints open.
- **Constant-time comparison:** `string.Equals` exits on the first differing byte and leaks the matching prefix length.

## 3. Controller
1. **Register the configuration once on the host** (`DiGi.WebAPI.WindowsService/Program.cs`, before `AddControllers()`):
   `serviceCollection.AddSingleton(WebAPI.Create.DiagnosticsConfiguration());` — a controller is activated per request,
   so loading the file in its constructor is disk I/O on every call. The constructor falls back:
   `this.diagnosticsConfiguration = diagnosticsConfiguration ?? Create.DiagnosticsConfiguration();` (still exactly one
   public constructor, `Coding - WebAPI Contracts.md` §5).
2. **Bind the key from a header, never the query string** (query strings land in Kestrel/IIS logs, `Referer`, browser and
   shell history, the plaintext leg of an HTTPS redirect); `[FromHeader]` keeps it in Swagger and header names are
   case-insensitive:
   ```csharp
   [HttpGet("system")]
   [ProducesResponseType(StatusCodes.Status401Unauthorized)]
   public async Task<IActionResult> GetSystemInformationAsync([FromHeader(Name = "key")] string? key = null, CancellationToken cancellationToken = default)
   {
       if (!diagnosticsConfiguration.IsAuthorized(key))
       {
           return Unauthorized();
       }
       // ...
   }
   ```
   The key parameter goes before the token (CA1068). Unauthorized → 401; authorized → 200 with the payload.
3. **A second gate on the same action is indistinguishable from the first.** Write endpoints check the key **and** a
   per-dataset flag, both `return Unauthorized()` — one bodyless 401 on the wire.
   - **An absent flag denies:** `ConfigurationFile.GetValue<bool>(nameof(AllowUpdateX))` without `defaultValue` is
     `false`, so a conf predating the flag rejects every write and no key fixes it — correct; update the deployment, never
     default the flag to `true`.
   - **Ship every flag in the committed default** (`files/WebAPI_[Feature].conf`) so a diff against a deployed conf shows
     what is missing; **log the two denials differently** (the log is the only place they differ).
   - `BuildingDataController.UpdateItemsByCountyIdsAsync` (key check, then `GISWebAPIConfigurationFileWatcher.AllowUpdateBuildingData`):
     a deployed `GIS_WebAPI.conf` without the flag survived two key rotations and two pipeline runs.
4. **The key gate is a plain action check, not `[Authorize]` — and the pipeline is not what `Program.cs` suggests:**
   - A .NET 7+ `WebApplication` inserts `AuthenticationMiddleware`/`AuthorizationMiddleware` itself when their services are
     registered and `Use*` was not called — `Program.cs` never calls `UseAuthentication()`, yet `user/session` tokens
     answer 200 (`DiGi.WebAPI.WindowsService#1`, closed not planned). Observable:
     `((IApplicationBuilder)webApplication).Properties["__AuthenticationMiddlewareSet"]` after `StartAsync`.
   - `GetService<…>() != null` around `UseAuthorization()` is vacuous (`AddControllers()` registers
     `IAuthorizationService`; `IAuthenticationSchemeProvider` always resolves). A real gate:
     `await schemeProvider.GetDefaultAuthenticateSchemeAsync() != null`.
   - Without a registered scheme `[Authorize]` answers **500**, not 401 (`No authenticationScheme was specified…`) — why
     `DiGi.GIS.WebAPI` validates the user JWT inside the action (the host may run without the user extension).
   - Reproduce any pipeline claim with a `TestServer` mirror or the real executable before touching `Program.cs`.

## 4. Configuration files and deployment
- **Committed default** `files/WebAPI_[Feature].conf` ships deny-by-default (`Enabled=false`, `Key=""`); the **secret**
  lives in `user files/WebAPI_[Feature].conf`, which overrides it in `bin` (copy targets and `.gitignore`:
  `Coding - General.md` §3).
- `Deploy.ps1` syncs extensions into `DiGi.WebAPI.WindowsService\bin\extensions\*`, then that `bin` to
  `SOFTWARE_DIRECTORY\DiGi.WebAPI.WindowsService`. `SyncDirectory.ps1` keeps top-level `*.conf` that exist only on the
  target, but a conf the source carries **overwrites** it — the deployed secret then travels from a workstation. Prefer the
  production key on the server (or `DIGI_DIAGNOSTICS_KEY`), out of the build output.

## 5. Tests
Never read real confs or machine secrets; write synthetic `.conf` files to `assembly.ReportsDirectory()` to cover the
loader.
1. **Assert every denial, not just the grant:**
   ```csharp
   [Fact]
   public void DiagnosticsConfiguration_Authorization()
   {
       DiagnosticsConfiguration? diagnosticsConfiguration_Null = null;
       Assert.False(diagnosticsConfiguration_Null.IsAuthorized("any-key"));

       DiagnosticsConfiguration diagnosticsConfiguration_Default = new();
       Assert.False(diagnosticsConfiguration_Default.IsAuthorized(null));
       Assert.False(diagnosticsConfiguration_Default.IsAuthorized("any-key"));

       DiagnosticsConfiguration diagnosticsConfiguration_Disabled = new("test-mock-key", false);
       Assert.False(diagnosticsConfiguration_Disabled.IsAuthorized("test-mock-key"));

       DiagnosticsConfiguration diagnosticsConfiguration_BlankKey = new(null, true);
       Assert.False(diagnosticsConfiguration_BlankKey.IsAuthorized("any-key"));

       DiagnosticsConfiguration diagnosticsConfiguration_Enabled = new("test-mock-key", true);
       Assert.False(diagnosticsConfiguration_Enabled.IsAuthorized("TEST-MOCK-KEY"));
       Assert.True(diagnosticsConfiguration_Enabled.IsAuthorized("test-mock-key"));

       DiagnosticsConfiguration diagnosticsConfiguration_Open = new(null, false, true);
       Assert.True(diagnosticsConfiguration_Open.IsAuthorized(null));
   }
   ```
2. A default-configured controller returns `UnauthorizedResult` from every protected action, `ContentResult` from public ones.
3. The loader, including the `Enabled=false` + valid-key shape that shipped open.
4. `Core.xUnit.Query.SerializationCheck(...)` with `Open` set.
5. **Probe the running host** — unit tests skip model binding, and a wrong binding source is a permanent 401 no test sees.

## 6. What the public tier may show
Assume an anonymous attacker reads it; keep it to what a monitoring probe needs.
- **Commit hashes are protected:** `0.8.8.20260826151608+ec0a8cf…` names the exact revision of a public repository — trim
  from `+` for unauthorized callers.
- **Assembly inventories are protected** (exact third-party versions are a CVE shortcut); **controller/internal route
  catalogs are protected** (they hand over the write surface).
- Health and coarse version are public.
