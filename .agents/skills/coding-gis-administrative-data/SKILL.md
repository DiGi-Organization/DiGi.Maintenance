---
name: coding-gis-administrative-data
description: "Use when touching administrative_areal_2d, building_2d or anything keyed by a county code or id - a code is not a key (406 polygon parts for 380 counties, never deduplicate them), the key-resolution matrix and mandatory ORDER BY, countyids writes resolved per item, fallbackByReference: true on reads, pruning spatial reads by every sibling part, building_data fill rate vs usable data, PRG address points, the nested Subdivision layer (smallest container, never a sum)."
---

# AI Guidelines: GIS Administrative Data (`administrative_areal_2d` & county keying)

> **A county code does NOT identify one county row. Key every write and every lookup by the county `id`, never by `code`.**

18 of Poland's 380 counties have disconnected territory and are stored as **several rows sharing one code**. Resolving a
code to "the" county picks one, and everything filed under the others reads back `404`/`204` with no error.
Evidence: [DiGi.GIS.PostgreSQL#1](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/1).

## 1. How the data is stored
**Source:** Geoportal BDOT10k `Polska_GML.zip` → `BDOT10k/<voivodeship>_GML.zip` (16) → `<countyCode>_GML.zip` (380, codes
unique) → `PL.PZGiK.<n>.<code>/BDOT10k/…__OT_ADJA_A.xml` (administrative units, `rodzaj` = `państwo` / `województwo` /
`powiat` / `gmina`), `…__OT_ADMS_A.xml` (settlements — **not** the hierarchy), `…__OT_BUBD_A.xml` (building footprints).
Entry naming is inconsistent (voivodeship `24` holds bare `2401_GML.zip`, others `26/2601_GML.zip`) — match on the basename.

**One `OT_ADJA_A` feature per polygon part**, one `administrative_areal_2d` row per feature: rows for a code == `powiat`
features in its package (verified 25/25; no re-import artifacts).

| Level (`type_id`) | Rows | Distinct codes | Codes with > 1 row |
|---|---|---|---|
| Country (0) | 406 | 1 (`10`) | 1 |
| Voivodeship (1) | 406 | 16 | 16 |
| County (2) | 406 | 380 | 18 |
| Municipality (3) | 2 555 | 2 477 | 64 |

**Every part carries its own private ancestor chain** (hence 406 country rows): `country_id`/`voivodeship_id` on a county
row point into that part's own chain, so two parts of one county have different parents; `county_id` is null on county
rows.

**The parts are real territory — never "deduplicate" them.** `2412` rybnicki: 3 parts, main 11 441 ha, others 8 477 and
2 412 ha — the largest polygon is only 52 % of the county; 26 non-main parts, median 11.6 ha, max 8 477 ha. Multi-part
codes: `0418 0620 0662 1016 1019 1206 1423 2212 2262 2401 2402 2404 2405 2410 2412 2479 2612 3020`.

## 2. Key resolution — every consumer may pick a different part
| Consumer | Selection | Picks for `2212` |
|---|---|---|
| WebAPI `updateitems…?code=` (writes) | `GetIdsByCodeAsync` → **every part**, each item filed under its own | 73482 *and* 73485 |
| `GetIdByCodeAsync` (`idbycode`, reads) | `ORDER BY id ASC LIMIT 1` → lowest | 73482 |
| `…referencesbyadministrativearealtype&uniquecode=true` | `DISTINCT ON (code) … ORDER BY code, id` → lowest | 73482 |
| `GetBuilding2DReferenceByReferenceAsync` | `ORDER BY id ASC` → lowest | 73482 |
| Subdivision import | by geometry | split |

The five `updateitems…?code=` actions pass every part to their `updateitemsbycountyids` counterpart; `DiGi.GIS.UI`'s
`MainWindow.xaml.cs` uploads (OrtoDatas, YearBuiltData, OccupancyData) resolve each item's part with `GetIdsByCodeAsync` +
`Query.CountyIdsByReferencesAsync` and skip an item no part holds. `idbycode` stays a deliberate lowest-part read
convenience. Before the issue-#1 `ORDER BY`, `LIMIT 1` returned 73485 — heap order differs from id order, so the pick
changed between imports.
> **Any `LIMIT`/`FirstOrDefault` over `administrative_areal_2d` or `building_2d` needs an explicit `ORDER BY`.**

## 3. `building_2d` and the part a building is filed under
- A `reference` is **unique only per `county_id`**, and nothing enforces it. Repeated imports once filed the same building
  under two parts (86 196 duplicate rows, removed 2026-08-14) and twelve codes held their buildings under the wrong part
  (~781 000 rows, e.g. all 37 260 buildings of `3020` in a 246 × 575 m exclave; moved 2026-09-08, deleting nothing). Full
  accounts: [#1](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/1),
  [#68](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/68).
- **Everything keyed on a building inherits its part** (`building`, `building_data`, `orto_datas`, `building_model`,
  `year_built_data`, `occupancy_data_building_2d`), and every read of those tables filters `county_id` first.
- **The mechanisms that repair a part are kept:** `RefreshCountyIdsAsync`, the `countypartmismatches` measurement
  (`Building2DCountyPartMismatchResult`), `Query.CountyId` (containing part, else nearest, else largest overlap) and the
  `UpdateAsync` three-tier guard, which no longer trusts a caller-supplied `CountyId` for a multi-part code (a client
  resolves the part from the row it is about to overwrite). A building imported now is placed by geometry.
- `0662` keeps two buildings `countypartmismatches` flags: not misfiled (the box-outside count is a documented lower
  bound). `year_built_data` holds **no** rows under multi-part codes (audited 2026-09-09) — it was never at risk.

## 4. Rules for code against this data
| Situation | Do |
|---|---|
| Uploading `BuildingModel` / `Building` / `OrtoDatas` / `YearBuiltData` / `OccupancyData` | POST `updateitemsbycountyids` with a **repeated** `countyids` parameter, one per part (`?countyids=73482&countyids=73485`; a comma list does not bind). The `code` endpoints do the same server-side. |
| Deciding which part an item belongs to | Read it from the `building_2d` row the reference is filed under (`Query.CountyIdsByReferencesAsync`, `DiGi.GIS.WebAPI`); only something with geometry of its own falls back to `DiGi.GIS.PostgreSQL.Query.CountyId`. An item neither can place is reported, not written. |
| A converter reading by county id | Support `bool fallbackByReference = false`: when the part yields nothing, look the items up by `reference` (via `building_2d`) under sibling parts. |
| **Reading** a table keyed on a building | **Pass `fallbackByReference: true`** (by name — it sits before the token). It defaults to `false`, and a row under a sibling part is silently not returned: the `predicted_year_built` projection and the ML training table lost rows that way (DiGi.GIS.PostgreSQL#70, DiGi.GIS.ML#7). Reference: `DiGi.GIS.YOLO.UI` `StoredYearBuiltDatasAsync` (`AddParameter("fallbackbyreference", true)`). |
| A background post task | Set `CountyIds` (plural). The scalar `CountyId` forwards `[countyId]` onto the trusted single-id branch below and files every row under that one part. |
| Writing a controller taking `countyids` | **The number of ids sent says nothing about how many parts the code has.** One id makes the shared `countyId_Single` shortcut write it verbatim. Safe only where something downstream re-decides (`building`, `orto_datas` re-resolve by geometry; `building_2d` re-files by footprint); **not** for `year_built_data`, `occupancy_data_building_2d`, `building_model`, `building_data` (DiGi.GIS.WebAPI#25). Resolve every item through `Query.CountyIdsByReferencesAsync` regardless (as `MainWindow.xaml.cs` does). |
| Iterating counties | You iterate **parts** (`AdministrativeAreal2DReference.Id`): 406 entries, not 380. |
| Is a code ambiguous? | `AdministrativeAreal2DPostgreSQLConverter.GetIdsByCodeAsync` (every part); `GetIdByCodeAsync` tells you nothing. |
| Every building of a county | Query **each** part id — one part's `referencesbycountyid` is not the county. |
| Pruning a **spatial** read to `county_id = ANY(...)` | Ask where the ids came from: a subdivision's `county_id`, a point-in-polygon resolve or `idbycode` names **one** part while the buildings may sit under a sibling — the read returns nothing, indistinguishable from an empty area. This emptied every spatial building read (`itemsbyboundingbox`, `itemsbycircle`, `itembypoint`, 3D `BuildingModel`, Communication) in 12 of 18 codes (DiGi.GIS.PostgreSQL#64). Prune by every sibling part: `Query.SiblingCountyGroups` or `GetCountyIdsByBoundingBox2DAsync`. Reproduce: `gis/building2d/itemsbyboundingbox` ±300 m around a building in code 0418. |
| Verifying a `building_data` repopulation | **A fill rate is not usable data:** `CheckBuildingDataColumns.ps1` and `coveragebycountyid` count non-null cells — county 8948 read "17 % filled" while 312 of 333 filled rows were `0.0` placeholders from `Update_RadialRatios`. Compare distributions with `-Distribution -All` (count, exact zeros, min/median/max per column; `-All` pages the whole part, 3–12 s) and assert the failure's signature (no exact zeros where forbidden — a building counts towards its own radial ratio; every column present; medians monotonic in radius), not a cross-county median. |
| Filing a point with no county of its own (PRG address points) | The commune code names a county, but the point may lie in a neighbour's (PRG and BDOT10k boundaries differ: county 2263, 661 of 8 347 points). `Modify.UpdateAddressPointsAsync` retries an outside point (`retryOutside`, default true) against the parts containing it (`Rescued`), kept **only if it then matches a building of that part** (`Inside`/`Nearest`) — PRG also has swapped coordinates (county 3021: 34 points hundreds of km away, `Unmatched`). Never key by code (DiGi.GIS.PostgreSQL#109, #118). |
| A new `SELECT … LIMIT`/`FirstOrDefault` here | `ORDER BY id ASC`. |
| Tempted to dedupe `administrative_areal_2d` | Don't (§1). |

## 5. Re-deriving any of this
Read-only live checks (`Coding - Deployed WebAPI.md`) — `referencesbycode` returns every part, `idbycode` and
`administrativeareal2dreferencebycode` one; comparing them spots an ambiguous code:
```bash
curl -s "https://api.digiproject.uk/gis/administrativeareal2d/idbycode?code=2212&administrativearealtype=2"
curl -s "https://api.digiproject.uk/gis/administrativeareal2d/administrativeareal2dreferencesbycode?code=2212"
```
Source side — count `powiat` features without extracting (nested archives are stored uncompressed; 3–12 s per voivodeship):
```python
import zipfile, io, re, collections
outer = zipfile.ZipFile(r"<path>/Polska_GML.zip")
with outer.open("BDOT10k/22_GML.zip") as stream:
    inner = zipfile.ZipFile(stream)
    names = {n.split("/")[-1]: n for n in inner.namelist()}   # entry naming is inconsistent
    package = zipfile.ZipFile(io.BytesIO(inner.read(names["2212_GML.zip"])))
name = next(n for n in package.namelist() if n.endswith("OT_ADJA_A.xml"))
xml = package.read(name).decode("utf-8")
print(collections.Counter(re.findall(r"<ot:rodzaj>([^<]*)</ot:rodzaj>", xml)))
```

## 6. Enum & wire notes
- `AdministrativeArealType`: `Undefined = -1`, `Country = 0`, `Voivodeship = 1`, `County = 2`, `Municipality = 3`,
  `Subdivision = 4` (renamed from `Subdivison` with no alias; send the integer). An omitted non-nullable parameter binds
  `Country`, not `Undefined` — `Coding - WebAPI Contracts.md` §2.
- `AdministrativeAreal2DReference.CountyId` is the **parent** county (null on a county row; its identity is `Id`).
  `GetIds()` returns the chain plus `Id`.
- `GetBuilding2DReferencesByAdministrativeAreal2DIdsAsync` resolves an area above subdivision level through its
  Subdivision children (`subdivision_id`), a **Subdivision** through its **polygon** (bounding-box centres,
  DiGi.GIS.PostgreSQL#75); it returns an empty list for a county with no subdivisions — not "no buildings".

## 7. The Subdivision layer nests — one building, one `subdivision_id`, never a sum
- **Nesting is the norm:** a village and its parts, a town and its unit, a city with districts and neighbourhoods are all
  type-4 rows (`GetCountyIdsWithNestedSubdivisionsAsync`: 404 of 406 parts). Warsaw: 217 rows, five levels (Marcelin ⊂
  Sielce ⊂ Dolny Mokotów ⊂ Mokotów ⊂ Warszawa). `Query.ContainerIds` gives a layer's nesting, smallest first; decide a pair
  with `GetInternalPoint` + `IsInside` (O(1)), never an intersection (199² on a city outline is a minute).
- **Districts are type 4 too:** `district_or_delegation` and `town_in_urban_rural_municipality` are `AdministrativeDivision`
  objects stored as `Subdivision` (`Query.AdministrativeArealType`) — Warsaw's 18 coincide with its `part_of_city` polygons and carry no
  figure. Never picked for a building (last resort only), not in the occupancy layer, nested under the city; a
  "subdivisions of the county" read returns them — neither dedupe nor sum them.
- **`building_2d.subdivision_id` is the smallest subdivision containing the building** (`GetSubdivisionIdAsync`; a refresh
  uses `SubdivisionIdSolver` in memory, DiGi.GIS.PostgreSQL#77, #79) — before that, ties went to the lowest id and filed
  57 551 Warsaw buildings under the city row. A fresh row is **NULL**; *Refresh Building2Ds* is the only writer (rebuild
  order: `DiGi.GIS.PostgreSQL.UI` wiki *Loading from scratch*).

  | Question | Answer through |
  |---|---|
  | which subdivision is building *b* filed under (occupancy row, `building_data` columns) | the column — exactly one |
  | the buildings of subdivision *X* (coverage, list, count) | *X*'s **polygon** (Bemowo: 2 466 of 6 435 by column) |
  | the buildings of a municipality / county | its own polygon or the county partition — **never Σ over subdivisions** |
- **Figures:** the roll-up sums **top-level** subdivisions only (`ContainerIds` empty; summing all wrote Warsaw as
  4 605 603 against 1 622 594). A missing `liczbaMieszkancow` is `null`, never `0`. A building's share comes from the
  **smallest figured subdivision containing it** (`Query.OccupancySubdivisionId`), spread over every building inside it
  (DiGi.GIS.PostgreSQL#80) — spreading a district's own figure over its directly filed buildings put Białołęka's 123 668
  on 76 buildings; figures do not reconcile across levels (Mokotów 194 777 vs its neighbourhoods 355 214).
- **Code traps:** `GetAdministrativeAreal2DsByAdministrativeArealType(Subdivision, countyId)` already widens to every
  sibling part — no loop around it. `BoundingBox2D.Inside(box)` is strict (a district sharing the city's edge fails) —
  test containment on coordinates with the tolerance outside. Many points against one polygon:
  `PolygonalFace2DPointRelationSolver`, built once per polygon (DiGi.Geometry#5; 52 s → 0.4 s, `Coding - Geometry.md` §6). `orto_datas.subdivision_id` is a copy
  taken at download/*Refresh OrtoDatas* time and NULL for older rows — measure nothing through it.
