# AI Guidelines: GIS Administrative Data (`administrative_areal_2d` & county keying)

## Mandatory Rule

> **A county code does NOT identify one county row. Key every write and every lookup by the county `id`, never by `code`.**

18 of Poland's 380 counties have disconnected territory and are stored as **several rows sharing one
code**. Resolving a code to "the" county picks one of them, and everything filed under the losing row
reads back `404` / `204` with no error anywhere. Full evidence:
[DiGi.GIS.PostgreSQL#1](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/1).

---

## 1. How the data is stored

### Source

Geoportal BDOT10k, `Polska_GML.zip`, three levels of nesting:

```
Polska_GML.zip
└── BDOT10k/<voivodeship>_GML.zip      16 files (02, 04, …, 32)
    └── <countyCode>_GML.zip           380 total, one per county, codes unique
        └── PL.PZGiK.<n>.<code>/BDOT10k/…__OT_ADJA_A.xml   administrative units
                                       …__OT_ADMS_A.xml   settlements
                                       …__OT_BUBD_A.xml   building footprints
```

**Entry naming is inconsistent** — voivodeship `24` holds bare `2401_GML.zip`, every other voivodeship
holds `26/2601_GML.zip`. Match on the basename, never the full path.

`OT_ADJA_A.xml` is the administrative-division layer (`rodzaj` = `państwo` / `województwo` / `powiat` /
`gmina`). `OT_ADMS_A.xml` is settlements — **not** the hierarchy, despite the similar name.

### The multi-part rule

**BDOT10k stores one `OT_ADJA_A` feature per polygon part.** A county whose territory is disconnected
appears as several `powiat` features in its own package, and the importer creates one
`administrative_areal_2d` row per feature.

> **Row count for a code == `powiat` feature count in that code's source package.** Verified 25/25
> (all 18 multi-part codes plus 7 single-row controls). There is no re-import artifact anywhere in
> this table — the source has 380 packages, 380 distinct codes, zero duplicates.

### Resulting table shape

| Level | Rows | Distinct codes | Codes with >1 row |
|---|---|---|---|
| Country (`type_id` 0) | 406 | **1** (`10`, "Polska"/"POLSKA") | 1 |
| Voivodeship (1) | 406 | 16 | 16 |
| County (2) | 406 | 380 | 18 |
| Municipality (3) | 2 555 | 2 477 | 64 |

**Every part carries its own private ancestor chain.** Each country row has exactly one voivodeship;
each voivodeship exactly one county. Hence 406 country rows for a single country. `country_id` /
`voivodeship_id` on a county row point into that county's *own* chain — they are not shared, and two
rows of the same county have different parents. `county_id` is **null** on every county row.

### The parts are real area — never "deduplicate" them

| Code | County | Parts | Main (ha) | Other parts (ha) |
|---|---|---|---|---|
| 2412 | rybnicki | 3 | 11 441 | **8 477, 2 412** |
| 0418 | włocławski | 3 | 139 379 | **7 068**, 505 |
| 1206 | krakowski | 2 | 116 625 | **6 271** |
| 2401 | będziński | 2 | 32 718 | **3 662** |
| 2212 | słupski | 2 | 235 118 | 0.05 |

26 non-main parts, median 11.6 ha, max 8 477 ha, 8 above 100 ha. For `2412` the largest polygon is
only 52 % of the county. **Deleting sibling rows discards up to 43 % of a county's territory.**
The multi-part codes are `0418 0620 0662 1016 1019 1206 1423 2212 2262 2401 2402 2404 2405 2410 2412
2479 2612 3020`.

---

## 2. Key-resolution matrix — every consumer picks a different part

| Consumer | Selection | Picks for `2212` |
|---|---|---|
| WebAPI `updateitems…?code=` (writes) | `GetIdsByCodeAsync` → **every part**, split per item | 73482 *and* 73485 |
| `GetIdByCodeAsync` (reads, `idbycode`) | `ORDER BY id ASC` + `LIMIT 1` → lowest | 73482 |
| `…referencesbyadministrativearealtype&uniquecode=true` | `DISTINCT ON (code) … ORDER BY code, id ASC` → lowest | 73482 |
| `GetBuilding2DReferenceByReferenceAsync` | `ORDER BY id ASC` → lowest | 73482 |
| Subdivision import | by geometry — genuinely split across parts | 1 / 356 |

The write path stopped collapsing the code: the five `updateitems…?code=` actions pass every part to
their `updateitemsbycountyids` counterpart, which files each item under the part it belongs to.
`DiGi.GIS.UI`'s `MainWindow.xaml.cs` upload sites (OrtoDatas, YearBuiltData, OccupancyData) do the same
since `54a9eaf` — each resolves an item's part via `GetIdsByCodeAsync` + `Query.CountyIdsByReferencesAsync`
and skips an item no part holds. The remaining `GetIdByCodeAsync` caller is the read endpoint `idbycode`,
which stays a deliberate lowest-part convenience for reads.

`ORDER BY` on the first three was added as part of the issue #1 fix. **Before it, `LIMIT 1` with no
ordering returned 73485** — heap order differs from id order in this table today, so the pick was
arbitrary in fact, not just in theory, and it demonstrably changed between import runs.

> **Any `LIMIT`/`FirstOrDefault` over `administrative_areal_2d` or `building_2d` needs an explicit
> `ORDER BY`.** Without one PostgreSQL guarantees nothing, and the row silently changes with the
> query plan, a vacuum, or heap ordering.

---

## 3. `building_2d` duplication across sibling parts — repaired 2026-08-14

Three codes held the same building reference under two parts at once — **86 196 duplicate rows**,
produced by repeated imports resolving one code to different parts back when that resolution had no
`ORDER BY`. **They were removed on 2026-08-14** by `PostgreSQLBuilding2DCountyPartRepairTask`, which
re-filed each building under the part its footprint lies in and deleted the copies left behind:

```
             before                          after
2212  73482 (10 198)  73485 (44 809)   ->   73482 (1)      73485 (44 809)
2405  76989 (24 260)  76984 (42 588)   ->   76989 (3)      76984 (42 585)
2612  86713 (51 740)  86698 (51 739)   ->   86713 (1)      86698 (51 739)
```

The union per code is unchanged — 44 810 / 42 588 / 51 740 — so no building lost its last row. Full
account in [DiGi.GIS.PostgreSQL#1](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/1).

Still true, and still worth knowing:
- A `reference` is **not unique** in `building_2d`; it is unique only per `county_id`. The repair
  removed today's duplicates, it did not add a constraint.
- Of the 44 rows in the 18 multi-part groups, **23 hold no `building_2d` at all**. Only those three
  groups ever had more than one part holding building data. The other 15 carry no duplicates, and an
  import now assigns a building to a part by geometry, so they cannot acquire any the way these did.
- Re-generating models per county id materialises a model under each part holding that building —
  which after the repair is one part per building for these codes.

### The other half of it: the right building under the wrong part - repaired 2026-09-08

That repair removed **copies**. It skipped, deliberately, every reference held by exactly one part:
*"Held by one part only - whether that is the right part is a question for the import, not for a repair
that exists to remove copies."* For twelve codes that one part is the wrong one, and the part holding
the territory reads back empty. Full evidence, including the audit method, in
[DiGi.GIS.PostgreSQL#68](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/68).

Audited 2026-09-06 against the deployed API, every multi-part code, footprint centroids against each
part polygon:

| Code | Populated part | Buildings | Sample lands in |
|---|---|---|---|
| 0418 | 8948 | 60 419 | 8957 |
| 0620 | 16580 | 93 672 | 16589 |
| 1016 | 25886 | 68 361 | 25887 |
| 1206 | 29861 | 163 699 | 29866 |
| 1423 | 50427 | 38 324 | 50447 |
| 2401 | 75133 | 63 312 | 75138, part 75133 - genuinely split |
| 2402 | 75348 | 66 319 | 75364 |
| 2404 | 76453 | 100 543 | 76454 |
| 2410 | 77971 | 42 951 | 77973 |
| 2412 | 78238 | 32 728 | 78238, 78244, 78249 - genuinely split |
| 2479 | 80374 | 13 880 | 80379 |
| 3020 | 97360 | 37 260 | 97358 |

Roughly **781 000 rows**. Clean: `0662 1019 2262 2405`, plus the main parts of `2212` and `2612`, which
each still hold one stray row from the 2026-08-14 run. Code `3020` is the clearest case - part 97360 is
a 246 x 575 m exclave holding all 37 260 buildings of the county.

**Everything keyed on a building inherits it.** For `3020` alone, 105 265 `building` rows and 37 260
`building_data` rows sit under part 97360 as well, and every read of those tables filters `county_id`
first.

Repaired 2026-09-08 (production, tray task, run twice). The mechanism above - `countypartmismatches`
as the before/after measurement, `PostgreSQLBuilding2DCountyPartRefreshTask` deciding each building by
`Query.CountyId` (containing part, else nearest, else most overlap) and moving it with `building`,
`building_data`, `orto_datas`, `building_model`, `year_built_data` and `occupancy_data_building_2d`,
deleting nothing - plus `UpdateAsync` no longer taking a caller-supplied `CountyId` on trust when its
code holds several parts (that trust made the wrong part permanent: a client resolves the part from the
row it is about to overwrite).

| Run | Read | Moved | Blocked | Carried | Stepped over |
|---|---|---|---|---|---|
| 2026-09-06/07 (first) | 989 341 | 758 394 | 0 | 40 | 12 |
| 2026-09-08 (re-run) | 989 341 | 0 | 0 | 351 562 | 0 |

The first run's 12 stepped-over codes were failures in the child-row carry sweep; the re-run proves they
were transient (zero stepped over, zero to move - idempotent) and carried the 351 562 rows left behind,
all `building_model`. **`year_built_data` was never at risk and needs no re-check**: audited end to end
on 2026-09-09, it holds **zero rows for all 18 multi-part codes** - every one of its 410 712 rows sits
under a single-part code, with 0 orphans against `building_2d` and 0 duplicates. The carry listed it
because the sweep covers every child table, not because it had anything to move. After the runs, `building_data` matches the final `building_2d` per-part
distribution exactly (all 18 codes), `building_model` answers under the destination part, and the
`building` partitions the first run left are the blocked-duplicate / orphan rows the task leaves for a
person by design. The union per code is unchanged - no building lost its last row. Full per-part
before/after in the [#68 comment](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/68).

`0662` keeps its 2: they are **not misfiled**. The geometry decision places them on 17371 and three
consecutive runs agree 0662 has zero misfiled buildings. `countypartmismatches` counts box-outside as a
documented lower bound and will keep flagging the two - an explained artifact, not an open defect.

The temporary code was deleted once the estate reached that state (2026-09-08): the task + options +
result, `GetCountyPartMovesAsync` + `Building2DCountyPartMoveResult`, `Query.CountyIds`, the tray
registration, and the task-bound Facts. Kept, because they are how a county part is repaired at all:
`RefreshCountyIdsAsync`, `countypartmismatches`, `Building2DCountyPartMismatchResult`, `Query.CountyId`,
and the `UpdateAsync` three-tier guard. `a418678` (PostgreSQL `0.8.9`), `1e5db1f` (UI `0.8.9`),
`9d38cee` (Test `0.8.11`).

---

## 4. Rules for writing code against this data

| Situation | Do |
|---|---|
| Uploading `BuildingModel` / `Building` / `OrtoDatas` / `YearBuiltData` / `OccupancyData` | POST `updateitemsbycountyids` with a repeated `countyids` parameter — one occurrence per polygon part (`?countyids=73482&countyids=73485`; a single comma-separated value does **not** bind). The `code` endpoints now do the same thing server-side, so either is correct. |
| Deciding which part one item belongs to | Don't write it again. Read it from the `building_2d` row the reference is already filed under (`Query.CountyIdsByReferencesAsync` in `DiGi.GIS.WebAPI`), and fall back to `DiGi.GIS.PostgreSQL.Query.CountyId` — inside the part, else nearest, else largest overlap — only for something carrying geometry of its own. An item that neither can place is reported and left unwritten. |
| Querying items by county ID across multi-part partitions | In PostgreSQL converters, support `bool fallbackByReference = false`. When enabled, if querying by `county_id` yields no records, perform a secondary lookup by item `reference` (via `Query.CountyIdsByReferencesAsync` / `building_2d`) to resolve records filed under sibling parts. |
| **Reading** a table keyed on a building | **Set `fallbackByReference: true`.** It defaults to `false`, so omitting it is silent: the read prunes to the one part it was given and a row under a sibling part is simply not returned. Pass it **by name** — it sits before `CancellationToken` (CA1068). Live omissions cost the `predicted_year_built` projection and the ML training table their rows (`DiGi.GIS.PostgreSQL#70`, `DiGi.GIS.ML#7`); the pipeline's own read gets it right (`DiGi.GIS.YOLO.UI/Query/YearBuiltDatasAsync.cs:78`). |
| A background post task | **Set `CountyIds` (plural), not `CountyId`.** Every `*PostTask` still exposes a scalar `int? CountyId` that forwards as `(IEnumerable<int>)[countyId]`, which lands on the trusted single-id branch below — for a multi-part county that files every row under the one part named. Use it only for a code you know has one part. |
| Writing a controller that takes `countyids` | **The number of ids the caller sent is not evidence about how many parts the code has.** A caller that sends one id gets `countyIds_Candidate.Count == 1`, and the shared `countyId_Single` shortcut then writes it verbatim with no `building_2d` check. That is safe **only** where something downstream re-decides: `building` and `orto_datas` pass `countyIds_Candidate` to a converter overload that re-resolves by geometry, and `building_2d`'s converter re-files by footprint. It is **not** safe for a table keyed on a building with no geometry of its own — `year_built_data`, `occupancy_data_building_2d`, `building_model` and `building_data` all write the caller's single id straight through (`DiGi.GIS.WebAPI#25`). Resolve every item through `Query.CountyIdsByReferencesAsync` regardless of how many ids arrived; it handles the one-candidate case correctly, and `MainWindow.xaml.cs:3022` already does exactly that. |
| Client already iterating counties | It is iterating **parts**. Use `AdministrativeAreal2DReference.Id`, and expect 406 entries, not 380. |
| Need to know a code is ambiguous | `AdministrativeAreal2DPostgreSQLConverter.GetIdsByCodeAsync` (returns every part). `GetIdByCodeAsync` collapses to the lowest and tells you nothing. |
| Need every building of a county | Query **each** part id — one part's `referencesbycountyid` is not the whole county. |
| Pruning a **spatial** read to `county_id = ANY(...)` | **Ask where the ids came from.** A subdivision's `county_id`, a point-in-polygon resolve and `idbycode` each name **one** part, while the buildings may be filed under a sibling — the read then returns nothing, indistinguishable from an empty area. This emptied every spatial building read (`itemsbyboundingbox`, `itemsbycircle`, `itembypoint`, the 3D `BuildingModel` endpoints, Communication) in 12 of the 18 multi-part codes (`DiGi.GIS.PostgreSQL#64`). Prune by every part sharing the code: `DiGi.GIS.PostgreSQL.Query.SiblingCountyGroups` or `AdministrativeAreal2DPostgreSQLConverter.GetCountyIdsByBoundingBox2DAsync`. Per-building datasets take the part from the building's own row; only a write placing a brand-new row resolves by geometry. Reproduce with `gis/building2d/itemsbyboundingbox` ±300 m around a known building in code 0418. |
| Verifying a repopulation run of `building_data` | **A fill rate is not usable data.** `CheckBuildingDataColumns.ps1` and `buildingdata/coveragebycountyid` count non-null cells and cannot tell a value from a placeholder: county 8948 read "17 % filled", and 312 of its 333 filled rows were exactly `0.0` written by `Update_RadialRatios` for an unreadable neighbourhood — 0 % usable. Compare the **distribution** with `-Distribution -All` (count, exact zeros, min, median, max per numeric column; `-All` pages the whole part, 3–12 s, because one sampled page measures only that page). Assert the failure's signature — no exact zeros where the invariant forbids them (a building always counts towards its own radial ratio), every column present, medians monotonic in radius — not a cross-county median, which legitimately varies by an order of magnitude. |
| Filing a point that carries no county of its own (PRG address points) | **The commune code names a county; the point may lie in its neighbour.** PRG and BDOT10k county boundaries differ, so a point can lie in none of the parts of its commune's county while the building under it is filed under the neighbouring county (county 2263 Słupsk: 661 of 8 347 points, nearest building under 2212). `Modify.UpdateAddressPointsAsync` retries such a point (`retryOutside`, default true) against the county parts containing it and files it under that part, counted in `Rescued`; only a point in no county part stays `Outside`. **A rescue is kept only if the point then matches a building of that part (`Inside` or `Nearest`):** PRG also carries points with their two coordinates reversed (county 3021, Mosina: 34 points landed in counties 1009 and 2406, hundreds of km away, as `Unmatched`), and a rescue that matches nothing stays `Outside` (`DiGi.GIS.PostgreSQL#118`). Never key by code (`DiGi.GIS.PostgreSQL#109`). |
| Writing a new `SELECT … LIMIT`/`FirstOrDefault` here | Add `ORDER BY id ASC`. |
| Tempted to dedupe `administrative_areal_2d` | Don't. See §1 — the rows are geometry, not noise. |

---

## 5. Re-deriving any of this

Live checks (read-only GET, see [Coding - Deployed WebAPI.md](Coding%20-%20Deployed%20WebAPI.md)):

```bash
curl -s "https://api.digiproject.uk/gis/administrativeareal2d/idbycode?code=2212&administrativearealtype=2"
```

```bash
curl -s "https://api.digiproject.uk/gis/administrativeareal2d/administrativeareal2dreferencesbycode?code=2212"
```

`referencesbycode` returns every part; `idbycode` and `administrativeareal2dreferencebycode` return
one. Comparing the two is the quickest way to spot an ambiguous code.

Source-side check — count `powiat` features in a county package without extracting anything:

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

Streaming a voivodeship costs ~3-12 s; the nested archives are stored effectively uncompressed, so
never extract them to disk.

---

## 6. Enum & wire gotchas

- `AdministrativeArealType`: `Undefined = -1`, `Country = 0`, `Voivodeship = 1`, `County = 2`,
  `Municipality = 3`, `Subdivision = 4`. Member 4 was misspelled `Subdivison` and was renamed — a
  breaking wire change with no alias kept, so `Subdivison` is now rejected. The value never changed,
  so nothing stored under `type_id` was affected. Integer `4` binds against any build; `Subdivision`
  only against a build carrying the rename.
- **`Undefined` is `-1`, not `0`, so it is not what an omitted parameter binds to.** A non-nullable
  `[FromQuery] AdministrativeArealType` left out of the request keeps `default(T)` — which is
  `Country`. A controller guard written as `administrativeArealType == AdministrativeArealType.Undefined`
  therefore never fires for the case it looks like it covers, and the request quietly returns countries:
  omitting the parameter on `administrativeareal2Dreferencesbyadministrativearealtype` returns a payload
  byte-identical to passing `0`. Bind it as `AdministrativeArealType?` and reject `null`. Same trap, and
  the fix, in [Coding - WebAPI Contracts.md](Coding%20-%20WebAPI%20Contracts.md) §2.
- `AdministrativeAreal2DReference.CountyId` is the **parent** county, so it is `null` on a county row.
  A county row's own identity is `Id`. `GetIds()` returns the chain plus `Id`.
- `GetBuilding2DReferencesByAdministrativeAreal2DIdsAsync` resolves an area **above** the subdivision
  level through its Subdivision children (`subdivision_id` membership), and a **Subdivision** through
  its **polygon** — the buildings whose bounding-box centre it contains (`DiGi.GIS.PostgreSQL#75`). It
  returns an empty list for a county row that has no subdivisions — which is not the same thing as
  "no buildings there". §7 says why the two paths differ.

---

## 7. The Subdivision layer nests — one building, one `subdivision_id`, never a sum

**Nesting is the norm, not a Warsaw peculiarity.** A village and its named parts (`part_of_village`),
a town and its same-named unit, a city and its districts and their neighbourhoods are all type-4 rows
of one municipality: `GetCountyIdsWithNestedSubdivisionsAsync` names **404 of the 406 county parts**.
Warsaw's layer is 217 rows deep to five levels (Marcelin ⊂ Sielce ⊂ Dolny Mokotów ⊂ Mokotów ⊂
Warszawa). `Query.ContainerIds` gives the nesting of a polygon layer, containers smallest first;
`GetInternalPoint` + `IsInside` decides a pair in O(1), never an intersection — 199² of those on a
city outline is a minute.

**Districts arrive as type 4 too.** `district_or_delegation` and `town_in_urban_rural_municipality`
are `AdministrativeDivision` objects stored under `AdministrativeArealType.Subdivision`
(`Query.AdministrativeArealType`). Warsaw has 18, coincident with its 18 `part_of_city` district
polygons, carrying no figure. They are never picked for a building (divisions are the pick's last
resort, used only when no subdivision candidate exists), they are not part of the occupancy layer,
and they nest under the city so no top-level sum counts them. A "subdivisions of the county" read
returns them; do not dedupe them away and do not sum them.

**The column is a per-building attribution key.** `building_2d.subdivision_id` is the **smallest
subdivision containing the building** — the most specific unit — decided in `GetSubdivisionIdAsync`
and, for a refresh, in memory by `SubdivisionIdSolver` (`DiGi.GIS.PostgreSQL#77`, `#79`). Before that
the tie between nested containers went to the lowest identifier, which filed all 155 307 Warsaw
buildings under the 49 lowest ids and 57 551 under the city row. A fresh `building_2d` row carries
**NULL**; nothing on the load path derives the column and *Refresh Building2Ds* is its only writer —
the order of a rebuild is on the `DiGi.GIS.PostgreSQL.UI` wiki page *Loading from scratch*.

**Two questions, two paths — never cross them:**

| Question | Answer through |
|---|---|
| "which subdivision is building *b* filed under" (occupancy row, `building_data` columns) | the column — exactly one, the smallest container |
| "the buildings of subdivision *X*" (a district's coverage, its building list, a count) | *X*'s **polygon** — the column names a district only for the buildings none of its neighbourhoods hold (Bemowo: 2 466 of 6 435 by column) |
| "the buildings of a municipality / county" | its **own polygon**, or the county partition — **never Σ over its subdivisions**, which counts a nested city once per level |

**Figures under a nested layer.** The administrative roll-up sums **top-level** subdivisions only
(`ContainerIds` empty); summing every row wrote Warsaw's municipality as 4 605 603 against a city of
1 622 594. A missing `liczbaMieszkancow` is stored as `null`, never `0` — the building side has to
tell the two apart. A building's share comes from the **smallest figured subdivision containing it**
(`Query.OccupancySubdivisionId`), with that subdivision's figure spread over *every* building inside
it (`DiGi.GIS.PostgreSQL#80`): distributing a district's own figure over the few buildings filed
directly under it put Białołęka's 123 668 on 76 buildings, and a naive "borrow the ancestor's
figure" double-counts. Figures do not reconcile across levels (Mokotów 194 777, its neighbourhoods
355 214), so no residual scheme survives contact with the data; per-building density does.

**Code traps met on the way.** `GetAdministrativeAreal2DsByAdministrativeArealType(Subdivision,
countyId)` already widens a county part to every sibling part sharing its code — no sibling loop
around it. `BoundingBox2D.Inside(box)` is strict, so a district sharing the city's outer edge fails
it; test box containment on coordinates with the tolerance outside the container. Testing many
points against one polygon goes through `PolygonalFace2DPointRelationSolver`, built once per polygon
(`DiGi.Geometry#5`): `PolygonalFace2D.Inside` walks every vertex per point, and a city outline
against a county's centroids took 52 s on the host that way, 0.4 s the other. `orto_datas.subdivision_id`
is a copy of the building's column taken at download or *Refresh OrtoDatas* time and is NULL for
everything downloaded before the refresh; nothing measures through it.
