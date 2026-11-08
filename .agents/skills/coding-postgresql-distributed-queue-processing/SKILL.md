---
name: coding-postgresql-distributed-queue-processing
description: "Use when designing or maintaining a distributed claim/acknowledge update queue in PostgreSQL - schema (claimed_at, attempts DEFAULT 0, natural uniqueness by county part), DDL on every path, the parenthesised FOR UPDATE SKIP LOCKED claim ordered to its index, lease longer than the slowest batch, acknowledging only stored work (idempotent target or owner-checked), re-enqueue during a claim, poison-row retirement, read-only observation, coverage measured on the target."
---

# AI Guidelines: PostgreSQL Distributed Queue Processing

**Reference implementation:** the orthophoto download queue `orto_datas_building_2d_reference_update` —
`OrtoDatasPostgreSQLConverter.UpdateBuilding2DReferencesAsync` (enqueue), `GetNextBuilding2DReferencesAsync` (retire +
claim), `AcknowledgeBuilding2DReferencesAsync`, `GetQueueSummariesByCountyIdsAsync`, and the
`nextbuilding2dreferences` / `acknowledgebuilding2dreferences` / `queuesummariesbycountyids` actions of
`OrtoDatasController`. **When this document and that code disagree, the code is the current state — fix the document.**

## 1. Lifecycle — claim/acknowledge, never a destructive drain
A queue read with `DELETE … RETURNING` loses work whenever a worker crashes, times out or fails downstream, and cannot be
observed without draining it. Every DiGi queue instead runs four stages:
1. **Enqueue / refresh:** the producer inserts missing or outdated records with `ON CONFLICT DO NOTHING`.
2. **Observe:** read-only summaries report depth, age and attempts without claiming anything (§5).
3. **Atomic claim:** workers lease batches non-destructively (`claimed_at = now()`, `attempts + 1`,
   `FOR UPDATE SKIP LOCKED`), after exhausted rows are retired (§4).
4. **Two-phase acknowledge:** after the results are **stored**, the worker deletes its ids; on failure it skips the
   acknowledgment and the expired lease returns the rows.

## 2. Table schema
Single unpartitioned table `{TargetTable}_{EntityType}_update`, created and migrated by `Create/TableAsync.cs`:
```sql
CREATE TABLE IF NOT EXISTS {tableName} (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    county_id INT NOT NULL,
    reference TEXT NOT NULL,
    subdivision_id INT,
    created_at timestamptz DEFAULT now(),
    claimed_at timestamptz,
    attempts INT NOT NULL DEFAULT 0,
    PRIMARY KEY (id, county_id)
);
ALTER TABLE {tableName} ADD COLUMN IF NOT EXISTS claimed_at timestamptz;
ALTER TABLE {tableName} ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS idx_{tableName}_county_id_reference ON {tableName} (county_id, reference);
CREATE INDEX IF NOT EXISTS idx_{tableName}_created_at ON {tableName} (created_at ASC);
CREATE INDEX IF NOT EXISTS idx_{tableName}_claimed_at ON {tableName} (claimed_at ASC NULLS FIRST, created_at ASC);
```
- `id` is the handle workers get back and acknowledge by. `claimed_at` `NULL` = ready; a timestamp = an active lease.
- `UNIQUE (county_id, reference)` keeps a refresh from enqueuing duplicates; `county_id` is a county **part** id — a
  multi-part county spans several values, so a summary or progress check names every part
  (`Coding - GIS Administrative Data.md`).
- `attempts` counts **claims**, from `0` (with `DEFAULT 1`, `maxAttempts = 5` would allow only four).
- `PRIMARY KEY (id, county_id)` on an unpartitioned table is redundant (`id` is unique); look rows up and acknowledge by
  `id` alone.
- **Every path that reads or writes the queue — enqueue, claim, acknowledge — runs the DDL first**, not a
  `TableExistsAsync` guard: `to_regclass` knows nothing about columns, so on a table predating `claimed_at` the guard
  passed and the claim raised `42703` (DiGi.GIS.PostgreSQL#46, the deployed download task reported Failed). The DDL is
  all conditional, so this costs a catalog lookup. Exception: observation (§5).

## 3. Atomic lease claim
```sql
UPDATE {tableName}
SET claimed_at = now(),
    attempts = COALESCE(attempts, 0) + 1
WHERE id IN (
    SELECT id FROM {tableName}
    WHERE (claimed_at IS NULL OR claimed_at < now() - (@claimTimeoutMinutes * interval '1 minute'))
      AND COALESCE(attempts, 0) < @maxAttempts
    ORDER BY claimed_at ASC NULLS FIRST, created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT @count
)
RETURNING id, county_id, reference, subdivision_id;
```
- **Parenthesise the lease condition** — `AND` binds tighter than `OR`, so without them a never-claimed row skips the
  ceiling. The retirement `DELETE` currently hides this; a copy without it would not.
- `FOR UPDATE SKIP LOCKED` lets many machines claim concurrently without waiting or double work.
- **The order matches the claim index and is a fairness rule:** never-claimed rows first, an expired lease behind them.
  Ordered by `created_at` alone, an expired lease jumps to the head, and a worker failing on its first rows retries them
  forever ahead of the rest.
- Interval arithmetic is native (`@claimTimeoutMinutes * interval '1 minute'`), never string concatenation.
- **The lease must outlast the slowest batch:** an unrenewed lease expires on schedule, so `claimTimeoutMinutes` exceeds the
  worst-case time to process and store one batch of `count`; too short hands rows to a second worker mid-processing (§4)
  and burns attempts.
- Signature — static (taking `NpgsqlConnection?`) plus instance overloads:
  `GetNextBuilding2DReferencesAsync(NpgsqlConnection? npgsqlConnection, int count = 100, int claimTimeoutMinutes = 30, int maxAttempts = 5, int commandTimeout = 60, CancellationToken cancellationToken = default)`.
  Returns `null` when the queue cannot be reached (no connection, DDL failed, `count <= 0`, `maxAttempts <= 0`), an
  **empty list** when nothing is claimable; the controller maps both to 204, but a converter caller must not read `null`
  as "drained".

## 4. Acknowledgment, ownership and poison rows
- **Acknowledge:** `DELETE FROM {tableName} WHERE id = ANY(@ids);` (`NpgsqlDbType.Array | NpgsqlDbType.Bigint`), after
  running the DDL. Returns the count deleted; `-1` when the table cannot be prepared or the statement fails (logged) —
  `0` is a count, never a failure. The controller maps a negative result to 500.
- **Golden rule: never acknowledge before the target data is committed.** If storing fails or throws, skip it; the lease
  expires and the work is retried.
- **Acknowledgment is not owner-checked.** If A's lease expires and B claims the rows, A's late acknowledgment deletes B's
  claim; B stores again and its own acknowledgment deletes nothing. Therefore:
  - the processing must be **idempotent** (the orthophoto `UpdateAsync` upserts by `(county_id, reference)`; a target that
    appends — a log, a counter, an insert without a key — must not sit behind this queue as written);
  - where double work matters, return `claimed_at` from the claim and acknowledge with
    `WHERE id = ANY(@ids) AND claimed_at = @claimedAt`.
- **Re-enqueue during a claim:** with `ON CONFLICT (county_id, reference) DO NOTHING` the new entry is dropped and the
  worker's acknowledgment then removes the old row. Correct when an entry means "reprocess from the current source" and
  the worker reads its input when it runs (the orthophoto case). **Wrong** when the entry carries a payload or describes a
  later change: use `ON CONFLICT … DO UPDATE SET claimed_at = NULL, attempts = 0, …` with an owner-checked
  acknowledgment. Document the choice on the producer.
- **Poison rows** (DiGi.GIS.PostgreSQL#48): a reference that can never resolve would cycle forever. The claim method first
  retires exhausted rows, logging each at **Error** with partition + reference (a data defect worth a ticket; the log is
  on the server running the Web API, not the worker):
  ```sql
  DELETE FROM {tableName} WHERE COALESCE(attempts, 0) >= @maxAttempts RETURNING id, county_id, reference;
  ```
  `@maxAttempts` (default 5) is high enough for transient faults to clear, low enough to retire the hopeless; `COALESCE`
  keeps rows predating the column claimable. The `DELETE` scans the queue (no index on `attempts` — a partial index
  cannot follow the parameter); fine today, measure before a queue grows into the millions. **Retirement is not
  acknowledgment:** one discards provably failing work, the other confirms stored work; only acknowledgment belongs in the
  worker loop.

## 5. Non-destructive observation
The one path that keeps `TableExistsAsync` — observation must create nothing; `null` means no refresh ever ran.
`GetQueueSummariesByCountyIdsAsync(NpgsqlConnection?, IEnumerable<int>? countyIds, int commandTimeout = 600, CancellationToken)`
returns `List<OrtoDatasQueueResult>?`, one row per `county_id`:
```sql
SELECT county_id, COUNT(*),
       COUNT(*) FILTER (WHERE subdivision_id IS NOT NULL),
       COUNT(*) FILTER (WHERE COALESCE(attempts, 0) > 0),
       MIN(created_at), MAX(created_at)
FROM {tableName}
WHERE county_id = ANY(@countyIds)   -- clause omitted when countyIds is null
GROUP BY county_id ORDER BY county_id;
```
Report the **attempted** count (`AttemptedCount`) — without it a part failing over and over looks like one not reached yet.
An empty result or 404 means drained or never initialized.

**An empty queue is not completeness.** A reference never enqueued leaves no trace, a retired row left without its work,
and other paths write too. Measure the **target table** per county part against its source: `summariesbycountyids` (orthophotos),
`buildingdata/coveragebycountyid`, `terrain/coveragebycountyid`; a queue-less batch task (the acquisition-date backfill,
DiGi.GIS.PostgreSQL#134) is measured only by `ortodatas/acquisitioncoveragesbycountyids`. Name every part of a multi-part
county in either request.

## 6. Controller and worker
- `POST nextbuilding2dreferences` binds `count`, `claimtimeoutminutes`, `maxattempts` (`[Minimum(1)]`) and
  `commandtimeout` (`[Minimum(0)]`), answers 400 for invalid values or a missing converter, **204** for `null`/empty, and
  returns the list as `Content(Core.Convert.ToSystem_String(references), "application/json")` (never `Ok`,
  `Coding - WebAPI Contracts.md` §5). Route names follow `Name = $"{nameof(OrtoDatasController)}_{nameof(NextBuilding2DReferencesAsync)}"`.
- `POST acknowledgebuilding2dreferences` takes `[FromBody] IEnumerable<long>? ids` (400 when null/empty), answers 500 for a
  negative result, otherwise `Ok(count)`.
- Worker loop:
  ```csharp
  while (postResponse_References?.Result is List<Building2DReference> references && references.Count > 0)
  {
      cancellationToken.ThrowIfCancellationRequested();

      List<OrtoDatas> ortoDatas = await ProcessBatchAsync(references, cancellationToken);
      bool saved = await TargetConverter.UpdateAsync(ortoDatas);

      if (saved) // acknowledge only what was stored
      {
          List<long> ids = [.. references.Where(x => x.Id > 0).Select(x => x.Id)];
          if (ids.Count > 0)
          {
              await AcknowledgeAsync(ids, cancellationToken);
          }
      }

      postResponse_References = await FetchNextBatchAsync(cancellationToken);
  }
  ```

## 7. Checklist
- [ ] Schema has `claimed_at timestamptz` and `attempts INT NOT NULL DEFAULT 0`, each with its `ADD COLUMN IF NOT EXISTS`?
- [ ] Enqueue, claim and acknowledge run the DDL, not an existence check?
- [ ] `UNIQUE (county_id, reference)` with `county_id` a county **part** id?
- [ ] Claim index `(claimed_at ASC NULLS FIRST, created_at ASC)` and a claim ordered the same way?
- [ ] Claim uses `FOR UPDATE SKIP LOCKED`, native interval multiplication, increments `attempts`, parenthesised lease condition before the ceiling?
- [ ] Claim method takes `count`, `claimTimeoutMinutes`, `maxAttempts`, `commandTimeout`, token; controller binds `maxattempts`?
- [ ] `claimTimeoutMinutes` above the worst-case batch time?
- [ ] Acknowledge by `id = ANY(@ids)`, idempotent target or owner-checked on `claimed_at`?
- [ ] Re-enqueue during a claim covered (`DO NOTHING`) or reset (`DO UPDATE`), documented on the producer?
- [ ] Retirement before the claim, every retired reference logged at Error?
- [ ] Acknowledgment only after the storage write succeeded?
- [ ] Read-only observation reports attempted rows; completeness measured on the target per county part?
- [ ] XML documentation on every public method and endpoint?
