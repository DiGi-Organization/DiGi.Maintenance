---
name: coding-deployed-webapi
description: "Use when checking a change against api.digiproject.uk or deciding which server runs what - per-prefix Swagger, deployed build lag, sequential querying, cold-partition timeouts, where each log lives. Manual curl only."
---

# Coding — Deployed WebAPI (Live Endpoint Testing)

Manual, on-demand checks against production (`https://api.digiproject.uk`). **Never add them to `DiGi.Test`.** Which
machine runs what — and so where to measure and where a log is — is §5.

## Checklist
Read this first; open a section only when its line applies to the check.
- Route or parameter names only: `InvestigateServer.ps1 -Endpoints -Controller "<Name>"`, no Swagger (§1, §2).
- Swagger: the per-prefix document (`/swagger/gis/swagger.json`, …), and for `gis` only the operation and its schemas — never the full document; write endpoints are not listed (`/information/endpoints?includeignored=true`) (§1).
- A 404 usually means "not deployed yet": compare the commit hash on `/information/version` with `git log` first (§1).
- Read-only GETs only; never POST/PUT/DELETE without explicit authorization; the diagnostics key goes in the `key` header (§2).
- This API is the only way to measure production — never a `*.conf` (§2).
- County → reference → building read path (§3).
- Query sequentially; re-test every 500 alone; a 500 on a cold partition is usually a timeout; prefer `estimated=true` counts (§4).
- `itembyreference` takes the cadastral reference and always `countyid`; pass every filter explicitly — unknown parameters are not rejected (§4).
- `000` on every call of a sweep is a client bug (CRLF id list) until proven otherwise (§4).
- Measure a limit and read a log on the machine that ran the code: database server = PostgreSQL + GIS Web API + deployed tools, web server = `DiGi.GIS.WebAPI.UI`; tests never run on a server (§5).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
