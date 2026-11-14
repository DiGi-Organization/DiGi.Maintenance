# AI Guidelines: PostgreSQL & Npgsql

Scope: `DiGi.PostgreSQL`, `DiGi.GIS.PostgreSQL` and their consumers (PostgreSQL 15+/18). Queues:
`Coding - PostgreSQL Distributed Queue Processing.md`; county-keyed tables: `Coding - GIS Administrative Data.md`.

## Checklist
Read this first; open a section only when its line applies to the change.
- Converters in `/Classes/Converter/`, idempotent DDL in `/Create/TableAsync.cs`, reads in `/Query/`, writes in `/Modify/` (§1).
- Nullable columns in composite unique indexes use `NULLS NOT DISTINCT` (§2).
- Collections batched (`batchSize = 1000`, `ANY(@array)`), no per-item statement in a loop (§3).
- `commandTimeout` and the token reach every `NpgsqlCommand` and `ReadAsync` — traced, not assumed (§3).
- No `@x IS NULL OR county_id = …` on a partitioned table — separate SQL texts for scoped and unscoped (§3).
- Wide-table partition walks in physical order with bounded `ctid` windows (§3).
- Copied resolved-later columns filter `NULL` sources and `COALESCE` the update (§3).
- `await using` for commands, readers, transactions and any connection/reader the method creates; one open reader per connection (§4).
- Values parameterized as Npgsql-accepted CLR types (§4); identifiers whitelisted against the stored list and quoted, overrides delegate (§5).
- A missing table answers `null`/404, not 500 (§4).
- Production figures measured through the API, not a `*.conf`; a report says which database it describes (§6).
- Database facts use their own `*_Test.conf`, refuse the host's database, restore what they write (§6).
- Every table in a statement on the same database — Main vs Storage, no join across them (§6).

## 1. Layout
- **Converters** (`/Classes/Converter/`, `BuildingPostgreSQLConverter`, `TablePostgreSQLConverter`, …) map DiGi objects to
  tables/views.
- **DDL** in `/Create/TableAsync.cs`, always idempotent (`IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`) — it is also the
  migration.
- **Reads** in `/Query/` and **writes** in `/Modify/` as extensions on `NpgsqlConnection?` or `Table<TColumn, TRow>`
  (`PullAsync`, `PushAsync`, `UpdateAsync`, `DeleteAsync`).
- **Long-running jobs** in `/Classes/BackgroundTask/` (`Coding - Background Tasks.md`).

## 2. Composite unique keys with nullable columns — `NULLS NOT DISTINCT`
By default `NULL != NULL`, so a unique index over `(county_id, reference, lod, year)` admits duplicates whenever `lod` or
`year` is null, and `ON CONFLICT (…) DO UPDATE` never matches such a row. Always:
```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_building_ref_lod_year
ON building (county_id, reference, lod, year) NULLS NOT DISTINCT;
```

## 3. Query performance, batching, timeouts (`57014`)
- **Never one SQL statement per item in a loop** — 50 000 single `SELECT`s starve the pool and end in
  `57014: cancelling statement due to user request`. Batch in chunks (`int batchSize = 1000`) and match with
  `= ANY(@array)`, never a built `IN (...)`:
  ```csharp
  public static async Task<List<Building2D>> Building2DsByReferencesAsync(NpgsqlConnection? npgsqlConnection, IEnumerable<string>? references, int batchSize = 1000, int commandTimeout = 30, CancellationToken cancellationToken = default)
  {
      if (npgsqlConnection == null || references == null)
      {
          return [];
      }

      List<Building2D> building2Ds_Result = [];
      List<string> references_List = [.. references.Where(x => !string.IsNullOrWhiteSpace(x))];

      for (int i = 0; i < references_List.Count; i += batchSize)
      {
          cancellationToken.ThrowIfCancellationRequested();

          string[] references_Chunk = [.. references_List.Skip(i).Take(batchSize)];

          await using NpgsqlCommand npgsqlCommand = new("SELECT id, county_id, reference, geometry_wkt FROM building_2d WHERE reference = ANY(@references);", npgsqlConnection);
          npgsqlCommand.CommandTimeout = commandTimeout;
          npgsqlCommand.Parameters.Add(new NpgsqlParameter("references", NpgsqlDbType.Array | NpgsqlDbType.Text) { Value = references_Chunk });

          await using NpgsqlDataReader npgsqlDataReader = await npgsqlCommand.ExecuteReaderAsync(cancellationToken);
          while (await npgsqlDataReader.ReadAsync(cancellationToken))
          {
              // map the record to Building2D
          }
      }

      return building2Ds_Result;
  }
  ```
- **`commandTimeout`:** every method running SQL exposes `int commandTimeout = 30` (60/120/600 for bulk work), placed
  before the `CancellationToken`, and assigns `npgsqlCommand.CommandTimeout = commandTimeout`.
- **A timeout or token that is accepted but never forwarded fails silently.** Trace every hop from the controller's
  `[FromQuery(Name = "commandtimeout")]` through the converter to `NpgsqlCommand.CommandTimeout` and every
  `ExecuteReaderAsync`/`ReadAsync` — four deployed endpoints offered a timeout that did nothing (DiGi.PostgreSQL #2–#5,
  DiGi.GIS.WebAPI #14, #48). Suspects: a method with an `int commandTimeout` parameter whose body never names it
  (`grep -L` over files declaring it), and calls passing it positionally (`Coding - General.md` §1.8).
- **Partition pruning needs a literal predicate.** `WHERE (@countyId IS NULL OR county_id = @countyId)` (or
  `= ANY(@ids)` behind an `IS NULL OR`) cannot be pruned, so every batch scans all 406 partitions: 12 of 18 codes of a
  national run timed out at 600 s (DiGi.GIS.PostgreSQL #50, #68, `c8890f6`). Emit separate SQL texts for the scoped and
  unscoped cases. `IS NOT DISTINCT FROM` cannot use an index — keep it for columns where `NULL` is a real key value.

### Reading a whole partition of a wide table — physical order, bounded `ctid` windows
Keyset paging by primary key is random heap I/O on a wide table: `building_data` (~230 columns) by
`(county_id, reference)` took **368 s cold / 654 s on a re-walk** for a 155 000-row part, against 7.5 s for the same part
read `reference`-only (index-only) — DiGi.GIS.WebAPI.UI#29, production.
- Select only key columns when you can (index-only scan); when you need the row, **read in physical order** and
  de-duplicate on the key.
- **A `ctid` window needs an upper bound:** `ctid > '(n,0)' ORDER BY ctid LIMIT k` alone plans a parallel seq scan + top-N
  sort (7 223 buffers per 1 000-row page, quadratic over a walk); `ctid > lower AND ctid < upper` is a **Tid Range Scan**
  (143–155 buffers). It carries no ordering, so size windows to about one page of rows from `reltuples / relpages` (an
  unanalysed partition reports `reltuples = -1` — `count(*)` it). `(n,0)` is an exclusive lower bound below block `n`.
  PostgreSQL ≥ 14.
- Concurrent updates move rows (read twice ahead, **missed** behind — HOT reuses earlier slots): one `REPEATABLE READ`
  transaction on the walking connection makes the walk exact.
- Reference: `TablePostgreSQLConverter.PullByPhysicalOrderAsync` (`DiGi.PostgreSQL.Table`), gated by
  `Query.IsPhysicalOrderSupported`; facts `Query_PhysicalOrderPullCommandText` (plan contains `Tid Range Scan`) and
  `PartitionPullByPhysicalOrderAsync_ConcurrentUpdate`.
- `EXPLAIN (ANALYZE, BUFFERS)` on the database that holds the table (the development one may lack it); a full walk of a
  large part loads production for minutes — never casually.

### Copying a column resolved later — `NULL` means unknown
When a column a later step fills (`subdivision_id`, a resolved county part) is copied between tables, a source `NULL` is
*not resolved yet*: filter such rows out **and** guard the assignment (`SET col = COALESCE(EXCLUDED.col, target.col)`), or
a re-run overwrites good values with nulls. Grep every `SET <column> =` and `ON CONFLICT … DO UPDATE` naming the column —
fixing one table's upsert does not fix its siblings.

## 4. Resources and lifecycle
1. **`await using`** every `NpgsqlCommand`, `NpgsqlDataReader`, `NpgsqlTransaction` — and every connection or reader a
   method **creates** for its caller: a convenience overload taking `ConnectionData` or a path opens one and must dispose
   it. DiGi.PostgreSQL#18 (`18015e0`): `TableExistsAsync`/`TableNames` leaked one per call, ~90 requests exhausted
   `max_connections` and the deployed API answered 503 until restarted (also DiGi.GIS.PostgreSQL#26, one pooled connection
   per tile).
2. **One open reader per connection:** querying again on a connection whose reader is still open throws
   `NpgsqlOperationInProgressException` — finish (or materialise) the reader first.
3. **Parameterize values** (`NpgsqlParameter`); an **identifier** cannot be a parameter — §5.
4. **Bind CLR types Npgsql accepts.** Filter values arriving from JSON are `JsonElement`s (arrays never reach a list
   branch) or unsigned integers Npgsql rejects — normalise to `int`/`long`/`double`/`string`/arrays first (DiGi.PostgreSQL
   #10, #17; `Coding - Serialization.md` §6).
5. Pass `cancellationToken` to every async Npgsql call (`ExecuteNonQueryAsync`, `ExecuteReaderAsync`,
   `ExecuteScalarAsync`, `ReadAsync`).
6. **A fresh, empty database is a supported state:** a read of a table that does not exist yet (`42P01`) answers
   `null`/404, never 500, and is distinguished from a table that merely has no statistics (`reltuples = -1`). bodyplan
   #122, DiGi.GIS.PostgreSQL #74.

## 5. Dynamic SQL identifiers (column and table names)
> **Resolve a dynamic identifier against the stored column/table list, reject anything not on it, and double-quote what
> survives.** `@column` is not valid SQL, so a runtime-chosen name must be built into the text; the list is the only guard.

Reference — delegate to it rather than copy: `TablePostgreSQLConverter.GetUniqueValuesAsync` (`DiGi.PostgreSQL.Table`)
validates **every** identifier the statement carries (target + filter columns):
```csharp
HashSet<string> uniqueIds = [columnUniqueId];
filterGroup?.CollectColumnUniqueIds(uniqueIds);

List<UColumn>? columns_Existing = await GetColumnsByUniqueIdsAsync(npgsqlConnection, uniqueIds);
if (columns_Existing is null || !columns_Existing.Exists(x => x?.UniqueId() == columnUniqueId))
{
    return null;
}

string commandQuery = $@"SELECT DISTINCT ""{columnUniqueId}"" FROM ""{TableName}"" WHERE {stringBuilder_Where} ORDER BY ""{columnUniqueId}""";
```
**An override delegates, never reimplements:** `BuildingDataPostgreSQLConverter.GetUniqueValuesAsync` added a county filter
with its own raw `SELECT DISTINCT {columnUniqueId} … ORDER BY {columnUniqueId}`, dropping the whitelist on the public,
unauthenticated `gis/buildingdata/uniquevalues` — caller text parsed as SQL. The fix folded the county into a
`FilterGroup` and called the base (−45 / +18 lines).
**Probe from outside:** an unknown identifier answering **500 instead of 404 reached the database**
(`uniquevalues?columnuniqueid=no_such_column` → 404; `…&countyid=…` → 500 before the fix). Regression fact:
`GetUniqueValuesAsync_UnknownColumn_Integration` (`DiGi.GIS.PostgreSQL.xUnit`). Table names follow the same rule
(`Query.IsOpenBuildingTableName`, DiGi.GIS.PostgreSQL#125).

## 6. Connection assets, production and test databases
- Connection settings come from git-ignored `user files/*.conf` (`GIS_PostgreSQL_Main.conf`); never commit a connection
  string, host or secret (`Coding - General.md` §3).

### A `.conf` never points at production
A `*.conf` resolves to a **development** database — partial, not current, specific to its machine: fine for exercising a
code path, proving a statement parses, creating a scratch table. Production is reached only through the API at
`api.digiproject.uk` (database server); the tray application runs on both servers, so a task's log is on the server that
ran it (topology: `Coding - Deployed WebAPI.md` §5).
> **Never answer a production question (row counts, coverage, "how many rows look like X") through a `.conf`.** When a
> local and an API number disagree, suspect the databases before the code.

A conf-backed diagnostic reported all 155 287 buildings of a county with NULL `subdivision_id` while the deployed
`buildingdata/coveragebycountyid` reported zero — both right about their own database; the same mistake later produced
"the run never happened" from searching an editing machine's logs. A diagnostic fact states **in its summary** which
database its figures describe (`BuildingDataUnreachableBuildings`, `DiGi.GIS.PostgreSQL.xUnit`).

### A test project reads its own conf, never a deployed host's
Nothing but a conf's contents keeps a workstation off production: a host conf and a development conf share a file name,
and a test project copies `user files/` whole into its `bin`. Tests run only on development machines.
- **Connect through the project's own `*_Test.conf`** (`Bodyplan_PostgreSQL_Test.conf`), a name no host reads, pointing at
  a droppable database; without it every database fact skips.
- **Refuse a test conf naming the host conf's database** (compare host, port, database at the single connection entry
  point) and **fail one plain `[Fact]`** on it — a skip alone reads green.
- **Restore what you write outside your scratch rows:** a fact-wide transaction cannot (converters open their own
  connections). Snapshot rows (`to_jsonb`) before the first write, write them back in `finally` by primary key, assert
  equality (bodyplan `Query.RowsJsonAsync`, `Modify.RestoreRowsAsync`); remove scratch rows (`TST-*`, `ZZ-*`) before and
  after. A fact running a whole import cannot be restored — the separate database is the real guard.

### A report says which database it describes
A run's evidence (an importer's `reports/<timestamp>` dumps, a fact's report) describes **one** database. bodyplan#47
"hardened" the suite against a production write that never happened: the "control run" report it relied on described a
development database (bodyplan#48).
- **Never deploy a build output's run artifacts** — exclude `reports/` (and logs) from the sync
  (`SyncDirectory.ps1 -ExcludeDirectory`; top-level files `-ExcludeFile`); output writing unpredictable folder names needs
  an allowlist (`Coding - YOLO.md` §5).
- **Check a surprising report against a neighbouring run:** two runs on one database share every untouched row; untouched
  rows with different `confirmed_at`, or timestamps running backwards, mean another database.

### Two databases per environment — Main and Storage
| Conf | Tables |
|---|---|
| `GIS_PostgreSQL_Main.conf` | `administrative_areal_2d`, `address_point`, `building_2d`, `year_built_data`, occupancy, EPW, unit, statistical data |
| `GIS_PostgreSQL_Storage.conf` | `orto_datas`, `building_data`, `building_model`, `building`, `terrain_point` |
- **No join across the two:** read each side once as a cheap projection and match in memory, in a `Query` taking both
  converters (`Query.SubdivisionLinksAsync`, `Query.CoveragesAsync`).
- Check which conf holds every table a statement names: a draw joining three tables on Storage found no
  `year_built_data`, returned `null` in 10 ms and the page said "Nothing left to verify" (DiGi.GIS.PostgreSQL#88) — a
  sub-50 ms "empty" answer from a query that should scan is an early return.
- A development-database fact seeds both sides on two databases.

### Running a skipped integration fact
`Create.GISPostgreSQLConverterManager()` looks for its confs beside the executing assembly (`DiGi.Test/bin/<Project>/`),
and nothing copies them there: copy the confs from `DiGi.GIS.PostgreSQL/user files/`, drop the `Skip`, run, restore the
`Skip`, delete the copies. `psql` is usually not on `PATH` — ad-hoc SQL (`EXPLAIN`, catalog reads) goes through a
temporary fact.

## 7. Checklist → the `## Checklist` at the top of this file
