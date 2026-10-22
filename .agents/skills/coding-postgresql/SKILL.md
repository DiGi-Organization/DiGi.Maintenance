---
name: coding-postgresql
description: "Use when designing database schemas or executing queries with Npgsql / PostgreSQL in DiGi solutions - Classes/Converter/ architecture, NULLS NOT DISTINCT composite unique indexes for nullable columns, query batching (batchSize = 1000, ANY(@array)), commandTimeout parameter standard, and connection asset isolation in user files/. Also whole-partition reads of wide tables in physical order with bounded ctid windows (Tid Range Scan, REPEATABLE READ for an exact walk), the Main vs Storage database split (no join across them), running a skipped integration fact with the confs beside the executing assembly, and NULL in a resolved-later column meaning \"unknown\" (filter sources, COALESCE the update, grep every sibling upsert)."
---

# AI Guidelines: PostgreSQL & Npgsql Development

**Environment:** PostgreSQL 15+ / 18, Npgsql, .NET 9.0+, C# 10+.  
**Domain:** Database persistence, GIS relational data, table partitioning, and bulk data processing (`DiGi.PostgreSQL`, `DiGi.GIS.PostgreSQL`).

---

## 1. Architecture & Converter Pattern

Data models are separated from database persistence logic using static partial class converters and extension methods.

### Structure Breakdown
- **Converters (`/Classes/Converter/`):** Class-specific converters (e.g. `BuildingPostgreSQLConverter`, `TablePostgreSQLConverter`, `OrtoDatasPostgreSQLConverter`) manage mapping between DiGi model objects and PostgreSQL tables/views.
- **Schema Creation (`/Create/TableAsync.cs`):** Static asynchronous methods responsible for DDL execution (table creation, partitioning definitions, index generation). All DDL commands should be idempotent (`IF NOT EXISTS`).
- **Queries (`/Query/`):** Read-only data access methods extending `NpgsqlConnection?` (e.g. `PullAsync`, `Building2DsAsync`).
- **Modifications (`/Modify/`):** Write/update/delete operations extending `NpgsqlConnection?` or `Table<TColumn, TRow>` (e.g. `PushAsync`, `UpdateAsync`, `DeleteAsync`).
- **Background Tasks (`/Classes/BackgroundTask/`):** Long-running data synchronization and migration tasks inheriting from `ReportableBackgroundTask`.

---

## 2. Composite Unique Constraints & `NULLS NOT DISTINCT` (PostgreSQL 15+)

### The Problem with Nullable Columns in Unique Indexes
In standard SQL and default PostgreSQL behavior, `NULL` values are treated as distinct (`NULL != NULL`). If a composite unique index includes nullable columns (e.g. `(county_id, reference, lod, year)` where `lod` or `year` can be `NULL`):
- PostgreSQL allows multiple rows with identical `county_id` and `reference` whenever `lod` or `year` is `NULL`.
- An `INSERT ... ON CONFLICT (county_id, reference, lod, year) DO UPDATE ...` fails to match the existing row containing `NULL` values, causing duplicate insertions or constraint violations.

### The Rule
For any unique index or constraint on a composite key that contains nullable columns, always specify **`NULLS NOT DISTINCT`**:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_building_ref_lod_year
ON building (county_id, reference, lod, year) NULLS NOT DISTINCT;
```

### Benefits & Mechanics
1. **Deterministic UPSERT:** `ON CONFLICT (county_id, reference, lod, year)` properly matches rows where one or more fields are `NULL` and updates the existing record.
2. **Performance:** Index lookup and traversal speed is identical to standard B-Tree indexes ($O(\log N)$).

---

## 3. Query Performance, Batching & Timeout Prevention (`Error 57014`)

### Prohibition of Per-Item Loop Queries
> **NEVER execute individual SQL queries inside a loop over a collection.**

Executing queries inside a loop (e.g. 50,000 separate `SELECT` commands for each building reference) causes connection pool starvation, severe latency, and statement cancellation exceptions:
`Npgsql.PostgresException (0x80004005): 57014: cancelling statement due to user request` (Npgsql command timeout).

### Query Batching Pattern
- **Chunked Lookups:** Batch lookups in configurable chunks (defaulting to `int batchSize = 1000`).
- **Array Parameter Matching:** Use PostgreSQL `ANY(@arrayParameter)` rather than building dynamic `IN (...)` SQL strings:

```csharp
using Npgsql;
using NpgsqlTypes;

public static async Task<List<Building2D>> Building2DsByReferencesAsync(
    NpgsqlConnection? npgsqlConnection,
    IEnumerable<string>? references,
    int batchSize = 1000,
    int commandTimeout = 30,
    CancellationToken cancellationToken = default)
{
    if (npgsqlConnection == null || references == null)
    {
        return [];
    }

    List<Building2D> building2Ds_Result = [];
    List<string> references_List = references.Where(r => !string.IsNullOrWhiteSpace(r)).ToList();

    for (int i = 0; i < references_List.Count; i += batchSize)
    {
        cancellationToken.ThrowIfCancellationRequested();

        string[] referenceChunk = references_List.Skip(i).Take(batchSize).ToArray();

        const string sql = @"
            SELECT id, county_id, reference, geometry_wkt
            FROM building_2d
            WHERE reference = ANY(@references);";

        await using NpgsqlCommand npgsqlCommand = new(sql, npgsqlConnection);
        npgsqlCommand.CommandTimeout = commandTimeout;
        npgsqlCommand.Parameters.Add(new NpgsqlParameter("references", NpgsqlDbType.Array | NpgsqlDbType.Text) { Value = referenceChunk });

        await using NpgsqlDataReader reader = await npgsqlCommand.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            // Map record to Building2D
        }
    }

    return building2Ds_Result;
}
```

### Standard `commandTimeout` Parameter
- All methods executing database queries, bulk updates, table creation, or analytical aggregations must expose an optional `int commandTimeout = 30` parameter (or higher, e.g. 60/120 for bulk operations).
- Assign `npgsqlCommand.CommandTimeout = commandTimeout;` before execution.
- Order parameters with `commandTimeout` placed before `CancellationToken` (per rule CA1068).

### Reading A Whole Partition Of A Wide Table — Physical Order, Bounded `ctid` Windows
Keyset paging on the primary key is the textbook way to walk a table, and on a wide table it is the slow
one: rows come back in key order, which is **random heap I/O**.
- **Measured on production** (DiGi.GIS.WebAPI.UI#29): paging `building_data` (~230 columns) by
  `(county_id, reference)` took **368 s cold** for a 155 000-row part and **654 s on an immediate re-walk**
  — the heap never stays cached, and a big walk evicts the small parts. The same part read `reference`-only
  (index-only) took 7.5 s; page size and transfer were ≤ 0.1 s throughout. Everything else was heap I/O.
- **Select only primary-key columns when you can** (index-only scan). When you need the row, **read in
  physical order** and de-duplicate on the key.
- **A `ctid` window needs an upper bound.** `ctid > '(n,0)' ORDER BY ctid LIMIT k` alone plans as a parallel
  sequential scan plus a top-N sort of the rest of the partition (7 223 buffers per 1 000-row page —
  quadratic over a walk). `ctid > lower AND ctid < upper` is a **Tid Range Scan** (143–155 buffers). A Tid
  Range Scan carries no ordering, so `ORDER BY ctid LIMIT k` reads and sorts the whole window: size windows
  to about one page of rows from `reltuples / relpages` (an unanalysed partition reports `reltuples = -1`;
  `count(*)` it instead of guessing). Offsets start at 1, so `(n,0)` is an exclusive lower bound below every
  row of block `n`. Requires PostgreSQL ≥ 14.
- **Concurrent updates move rows across the walk** — read twice when the new version lands ahead, **missed**
  when it lands behind (HOT reuses earlier slots). One `REPEATABLE READ` transaction on the walking
  connection makes the walk exact.
- **Reference implementation:** `TablePostgreSQLConverter.PullByPhysicalOrderAsync` (`DiGi.PostgreSQL.Table`),
  gated by `Query.IsPhysicalOrderSupported`; the fact `Query_PhysicalOrderPullCommandText` asserts the plan
  contains `Tid Range Scan`, and `PartitionPullByPhysicalOrderAsync_ConcurrentUpdate` proves the transaction.
- **`EXPLAIN (ANALYZE, BUFFERS)` on the database that holds the table.** The development database may not
  have it at all (it has no `building_data`), and a full walk of a large part loads production for minutes —
  do not run one casually.

### Copying A Column That Is Resolved Later — `NULL` Means Unknown
When a column filled in by a later step (`subdivision_id`, a resolved county part) is copied from one table
into another, a `NULL` in the source means *not resolved yet*, not *empty*. Filter such rows out of the
write **and** guard the assignment (`SET col = COALESCE(EXCLUDED.col, target.col)`), or a re-run overwrites
good values with nulls. Fixing one table's upsert does not fix its siblings: grep every `SET <column> =` and
`ON CONFLICT … DO UPDATE` naming the column before closing the issue.

---

## 4. Resource Management & Async Lifecycle

1. **`await using` Disposal:** Always wrap `NpgsqlCommand`, `NpgsqlDataReader`, and `NpgsqlTransaction` in `await using` blocks to ensure unmanaged database resources and active readers are released immediately:
   ```csharp
   await using NpgsqlCommand npgsqlCommand = new(query, npgsqlConnection);
   npgsqlCommand.CommandTimeout = commandTimeout;
   await using NpgsqlDataReader reader = await npgsqlCommand.ExecuteReaderAsync(cancellationToken);
   ```
2. **Parameterized Queries:** Always parameterize input **values** using `NpgsqlParameter` or `Parameters.AddWithValue`. Never concatenate user input into raw SQL strings — it prevents SQL injection and lets PostgreSQL cache the query plan. An **identifier** (a column or table name) cannot be a parameter and needs the whitelist treatment in §5 instead.
3. **`CancellationToken` Threading:** Always pass `cancellationToken` to all asynchronous Npgsql operations (`ExecuteNonQueryAsync`, `ExecuteReaderAsync`, `ExecuteScalarAsync`, `ReadAsync`).

---

## 5. Dynamic SQL Identifiers (Column and Table Names)

A value can be a parameter. **An identifier cannot** — `@column` is not valid syntax for a column
name, so a query that names a column chosen at runtime is forced to build that name into the
statement text. "Never concatenate" is not a rule anyone can follow there, which is how this was got
wrong.

The rule that can be followed:

> **Resolve a dynamic identifier against the stored column list, reject anything not on it, and
> double-quote what survives.** The list is the guard, because nothing else can be.

### The reference implementation

`TablePostgreSQLConverter.GetUniqueValuesAsync` in `DiGi.PostgreSQL.Table` does this correctly and is
what to copy — or better, to delegate to:

```csharp
// Column whitelist validation to prevent SQL injection (target column + every filter column)
HashSet<string> uniqueIds = [columnUniqueId];
filterGroup?.CollectColumnUniqueIds(uniqueIds);

List<UColumn>? columns_Existing = await GetColumnsByUniqueIdsAsync(npgsqlConnection, uniqueIds);
if (columns_Existing is null || !columns_Existing.Exists(x => x?.UniqueId() == columnUniqueId))
{
    return null;
}

string commandQuery = $@"
    SELECT DISTINCT ""{columnUniqueId}""
    FROM ""{TableName}""
    WHERE {stringBuilder_Where}
    ORDER BY ""{columnUniqueId}""";
```

Note that it validates **every** identifier the statement will carry, not only the obvious one: the
filter columns reach the SQL too.

### An override must delegate, not reimplement

`BuildingDataPostgreSQLConverter.GetUniqueValuesAsync` added a county filter by writing its own
statement, and in doing so dropped the whitelist:

```csharp
// WRONG - what this replaced
string commandQuery = $@"
    SELECT DISTINCT {columnUniqueId}
    FROM {TableName}
    WHERE (@countyId IS NULL OR county_id = @countyId)
      AND {columnUniqueId} IS NOT NULL
    ORDER BY {columnUniqueId}";
```

`columnUniqueId` arrives from the `columnuniqueid` query parameter of
`gis/buildingdata/uniquevalues`, which is public and takes no authentication — so caller-supplied
text was being parsed as SQL, `ORDER BY` included. The fix folded the county into a `FilterGroup` and
called the base method, deleting the raw statement: about 45 lines removed for 18 added, and one code
path instead of two. **A subclass that needs an extra condition expresses it as a filter and
delegates.**

### Finding it from outside

An unknown identifier that answers **500 instead of 404 reached the database**. That is the whole
test, and it needs no payload:

| request | result |
|---|---|
| `uniquevalues?columnuniqueid=no_such_column` | 404 — rejected before any SQL was built |
| `uniquevalues?columnuniqueid=no_such_column&countyid=…` | 500 — the identifier reached PostgreSQL |

A regression test belongs with the fix. `GetUniqueValuesAsync_UnknownColumn_Integration` in
`DiGi.GIS.PostgreSQL.xUnit` asserts that an unknown column is rejected identically on every branch,
and it fails against the unfixed code.

---

## 6. Database Connection Assets & Security

- **Connection Configurations:** Connection strings and server credentials must be loaded from `*.conf` files located in the git-ignored `user files/` directory (e.g. `user files/GIS_PostgreSQL_Main.conf`).
- **Never hardcode credentials:** Never commit connection strings containing passwords, host IPs, or secret tokens to source control.

### A `.conf` never points at production

A `*.conf` resolves to a **development** database: partial, not current, and specific to whichever
machine it sits on. It is the right place to exercise a code path, prove a statement parses, or
create and drop a scratch table. It is **not** the estate.

Production is reached only through the API at `api.digiproject.uk`, which runs on the database server
next to the production databases. `DiGi.GIS.PostgreSQL.UI` is installed on both servers, so a background
task's Serilog file is on the server that ran the task — never on the machine the code was edited on
(deployment roles: [Coding - Deployed WebAPI.md](Coding%20-%20Deployed%20WebAPI.md) §5).

> **Never answer a question about production by measuring through a `.conf`.** Row counts, coverage,
> "how many rows look like X" — those are production questions and they go through the API. When a
> number measured locally and a number from the API disagree, suspect the databases before the code.

Two conclusions were retracted for want of this rule. A diagnostic run through a conf reported every
one of a county's 155 287 buildings as having a NULL `subdivision_id`, while the deployed
`gis/buildingdata/coveragebycountyid` reported **zero** for the same county — both correct about
their own database, and briefly read as a converter defect. The same mistake later produced "the task
run never happened", from searching an editing machine's log folders for a run that had happened on
the server.

A diagnostic test that reads a database must say **in its own summary** which database its figures
describe. `BuildingDataUnreachableBuildings` in `DiGi.GIS.PostgreSQL.xUnit` is the worked example.

### A test project reads its own conf, never a deployed host's
The rule above is a convention, and nothing enforces it. Tests run only on development machines; the
servers have no development tooling ([Coding - Deployed WebAPI.md](Coding%20-%20Deployed%20WebAPI.md)
§5). But a deployed host's conf and a development machine's conf share one **file name**, and on the
server that file names the production database. Copy that conf to a workstation, or point a
workstation's conf at the server, and every tool there that reads the name reaches production. That
includes a test project, which copies the whole `user files/` folder into its `bin`.

bodyplan's facts read `Bodyplan_PostgreSQL_Main.conf`, the file its importer and Web API extension read.
No fact has written production. The near miss was reading the wrong database: an importer "control run"
reported a fact's note, `"xUnit propagation over a direct row"`, on what was taken for the production
map. Its report sat in the shared deploy folder next to the server's runs, but it described a development
database. All 295 rows carried timestamps that differed from the production run made 50 minutes earlier,
and some predated it. bodyplan#47 hardened the suite on that misreading, and bodyplan#48 found the real
cause (*A report says which database it describes*, below). The rules stand as prevention, because nothing
but a conf's contents keeps a workstation off production:

- **A database test project connects through its own `*_Test.conf`** (`Bodyplan_PostgreSQL_Test.conf`),
  a name no deployed host reads. Create it only on a development machine and point it at a database that
  may be dropped, never at a server's host. Without it every database fact skips.
- **Refuse a test conf that names the host conf's database, and fail one fact on it.** Both files sit in
  the same `bin`, so compare host, port and database at the single connection entry point and refuse
  there. A skip alone reads as green, so one plain `[Fact]` asserts that the two differ.
- **A fact restores what it writes outside its own scratch rows.** A test-wide transaction cannot do it:
  a converter built from connection data opens its own connection, so the fact's transaction never wraps
  the converter's writes. Snapshot the rows (`to_jsonb`) before the first write, write them back in
  `finally` keyed on the primary key, and assert that they equal the snapshot (bodyplan's
  `Query.RowsJsonAsync` and `Modify.RestoreRowsAsync`). Remove scratch rows (`TST-*`, `ZZ-*`) before the
  write and again in `finally`.
- A fact that runs a whole import rewrites the base the same way the importer does, and no restore undoes
  that. This is why the separate database is the guard and the restore is not.

### A report says which database it describes
Evidence written by a run (an importer's `reports/<timestamp>` dumps, a diagnostic fact's report) is
evidence about **one database**. Before reading it as a statement about production, establish that
production is the database it describes:

- **Never deploy a build output's own run artifacts.** A development machine's importer `bin` holds the
  reports of its runs against development databases. bodyplan's `Deploy.ps1` shipped that `reports/`
  folder to the shared software directory. That mixed development runs into the server's evidence and
  also stranded the destination's own reports in the deploy's temporary stash. Exclude such folders
  from the sync (`SyncDirectory.ps1 -ExcludeDirectory`), as logs already are (bodyplan#48). An output that
  writes run artifacts under names nobody fixed in advance needs an allowlist instead, because the next
  folder escapes the list (`Coding - YOLO.md` §5, the Year Built runner's `scratch_train9`);
  `-ExcludeFile` covers top-level file patterns.
- **Check a surprising report against its neighbours before acting on it.** Two runs on one database
  share every row they did not change. A dump whose untouched rows all carry different `confirmed_at`
  values, or whose timestamps run backwards against an earlier run's, describes another database. Five
  minutes of comparing two dumps would have spared bodyplan#47 its "the estate was corrupted" premise.

### Two databases per environment — Main and Storage
`GISPostgreSQLConverterManager` builds each converter from one of two confs, and the tables are split
between them:

| Conf | Tables (converters) |
|---|---|
| `GIS_PostgreSQL_Main.conf` | `administrative_areal_2d`, `address_point`, `building_2d`, `year_built_data`, occupancy, EPW, unit, statistical data |
| `GIS_PostgreSQL_Storage.conf` | `orto_datas`, `building_data`, `building_model`, `building`, `terrain_point` |

- **There is no join across the two.** Work that needs both sides is a `Query` extension taking both
  converters: read each side once as a cheap projection and match in memory (`Query.SubdivisionLinksAsync`,
  `Query.CoveragesAsync`).
- **Before writing SQL that names two tables, check which conf each one lives on.** A random draw joining
  three tables on the Storage connection found `year_built_data` absent there, returned `null` in 10 ms, and
  the page said "Nothing left to verify" (DiGi.GIS.PostgreSQL#88). A sub-50 ms "empty" answer from a query
  that should scan is an early return, not an empty pool.
- A development-database fact must seed the two sides on two databases, or it proves nothing.

### Running a skipped integration fact
`Create.GISPostgreSQLConverterManager()` looks for its confs beside the executing assembly — for a test host
that is `DiGi.Test/bin/<ProjectName>/`, not `DiGi.Test/user files/`, and nothing copies them there. To run a
`[Fact(Skip = …)]` integration fact: copy the confs from `DiGi.GIS.PostgreSQL/user files/` into that `bin`
folder, drop the `Skip`, run, then restore the `Skip` and delete the copies. The confs still point at a
development database (above). `psql` is usually not on `PATH`, so ad-hoc SQL (`EXPLAIN`, catalog reads) goes
through a temporary fact over Npgsql.

---

## 7. Verification & Detection Checklist

- [ ] Composite unique indexes on nullable columns use `NULLS NOT DISTINCT`?
- [ ] Large collection queries batched in chunks (`batchSize = 1000`) using `ANY(@parameter)`?
- [ ] No per-item `SELECT`/`INSERT` queries executing in a loop?
- [ ] `int commandTimeout = 30` parameter provided and assigned to `npgsqlCommand.CommandTimeout`?
- [ ] `CancellationToken` is the final parameter and passed to all async Npgsql calls?
- [ ] `await using` used for commands, readers, and transactions?
- [ ] Queries use parameterization rather than string concatenation?
- [ ] Dynamic identifiers resolved against the stored column list and quoted, never interpolated raw?
- [ ] Any figure quoted about production measured through the API rather than through a `*.conf`?
- [ ] Do the database facts connect through their own `*_Test.conf`, refuse one that names the host conf's database, and restore every row they write outside their scratch rows?
- [ ] Whole-partition reads of wide tables in physical order, with bounded `ctid` windows?
- [ ] Every table a statement names lives on the same database (Main vs Storage)?
- [ ] A copied resolved-later column filters `NULL` sources and guards the update with `COALESCE`?
