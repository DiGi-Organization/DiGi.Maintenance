---
name: coding-webapi-contracts
description: "Use when changing a WebAPI route, parameter, controller or extension, or writing its HTTP client - silent parameter renames, omitted parameters, enums on the wire, failure statuses never read as empty, timeouts, one public constructor, Content(...) not Ok(x)."
---

# Coding — WebAPI Contracts (Controllers and Their HTTP Clients)

The wire contract between a `DiGi.*.WebAPI` controller and its HTTP callers (`DiGi.GIS.WebAPI.UI`, `DiGi.GIS.UI`, background
tasks, page scripts). Live testing: `Coding - Deployed WebAPI.md`; 3D: `Coding - WebAPI GLTF.md`; API keys:
`Coding - WebAPI Simple Authorization.md`.

## Checklist
Read this first; open a section only when its line applies to the change.
**Changing a controller**
- Renamed/removed a `[FromQuery(Name = "…")]`? Every client and front-end query string grepped.
- Absence matters? Nullable binding, `null` rejected; no guard against a non-`0` sentinel.
- `CancellationToken` last and passed to the converter beneath.
- `Modify.InitializeAsync(this IServiceCollection)` present; route names unique; one public constructor;
      `ControllerActivation` fact present.
- DiGi objects via `Content(Core.Convert.ToSystem_String(x), "application/json")`; failures answer 503/502/500, not
      empty; no action-level `[Produces]` over string errors.

**Writing a client**
- Base URI from a constant; `/Query` helpers; enums as integers; `JsonSerializerOptions.Default` for named bodies;
      body names confirmed on the wire.
- Each panel degrades on its own, and an upstream failure is reported by its status, never as empty or 404.
- `PostOptions.Delay` sized for the batch; `HttpClient.Timeout` ≥ server `commandtimeout`.
- Every endpoint used is deployed, or gated behind a `TODO [MarkerName]`.

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
