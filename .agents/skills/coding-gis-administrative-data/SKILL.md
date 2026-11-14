---
name: coding-gis-administrative-data
description: "Use when touching administrative_areal_2d, building_2d or anything keyed by a county code or id - a code is not a key (406 parts for 380 counties), fallbackByReference, sibling-part pruning, the Subdivision layer."
---

# AI Guidelines: GIS Administrative Data (`administrative_areal_2d` & county keying)

> **A county code does NOT identify one county row. Key every write and every lookup by the county `id`, never by `code`.**

18 of Poland's 380 counties have disconnected territory and are stored as **several rows sharing one code**. Resolving a
code to "the" county picks one, and everything filed under the others reads back `404`/`204` with no error.
Evidence: [DiGi.GIS.PostgreSQL#1](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/1).

## Checklist
Read this first; open a section only when its line applies to the change (§4 is the situation → action table).
- Key by county `id`; iterating counties iterates **parts** (406, not 380); never deduplicate the parts (§1, §4).
- Any `LIMIT`/`FirstOrDefault` over `administrative_areal_2d` or `building_2d` has an explicit `ORDER BY id ASC` (§2).
- A `reference` is unique only per `county_id`; everything keyed on a building inherits its part and filters `county_id` first (§3).
- Uploads: POST `updateitemsbycountyids` with a repeated `countyids` parameter, each item resolved through `Query.CountyIdsByReferencesAsync` — whatever number of ids arrived (§4).
- Reads of a building-keyed table pass `fallbackByReference: true` by name; a background post task sets `CountyIds` (plural) (§4).
- A spatial read pruned to `county_id = ANY(...)` prunes by every sibling part (`Query.SiblingCountyGroups`) (§4).
- A `building_data` fill rate is not usable data — compare distributions (§4). PRG address points are never keyed by code (§4).
- Is a code ambiguous: `GetIdsByCodeAsync` (every part), not `GetIdByCodeAsync` (§4); live re-checks (§5).
- `AdministrativeArealType` goes as an integer; `AdministrativeAreal2DReference.CountyId` is the parent county (§6).
- Subdivisions nest: `building_2d.subdivision_id` is the smallest containing one; buildings of an area come from its polygon, never a sum over subdivisions; figures roll up top-level only (§7).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
