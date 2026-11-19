# Evidence: Coding — PostgreSQL Distributed Queue Processing

Dated incidents and measurements behind the rules of [the guideline](../Coding%20-%20PostgreSQL%20Distributed%20Queue%20Processing.md).
Read only when a rule is disputed or being changed.

## §4. Retirement predicate: `COALESCE` retired (DiGi.GIS.PostgreSQL#145, 2026-11-19)

The guideline's retirement statement carried this predicate until it was replaced by the plain
`attempts >= @maxAttempts`. The line is kept here, not deleted:

```sql
DELETE FROM {tableName} WHERE COALESCE(attempts, 0) >= @maxAttempts RETURNING id, county_id, reference;
```

- **Why it was wrong:** "`COALESCE` keeps rows predating the column claimable" — it does not need to:
  `ALTER TABLE {tableName} ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0` backfills every row that
  predates the column, so `attempts` is never null. The `COALESCE` hid the column from every index instead, and the
  retirement runs at the start of **every claim**.
- **The measurement the guideline asked for arrived:** "fine today, measure before a queue grows into the millions"
  — the queue reached 5.6 M rows and was no longer fine. Tray log 2026-11-18 11:08:38 (+01:00):
  `[ERR] GetNextBuilding2DReferencesAsync failed while retiring poison references` —
  `NpgsqlException: Exception while reading from stream` / `TimeoutException: Timeout during reading attempt` at the
  retire statement. The method returned `null`, so that claim round fetched nothing (`Count: 0`), and the 20 entries
  of county part 17371 (`created_at = 2026-04-20T09:52:56Z`, `AttemptedCount = 20`) were never retired.
- **Plans, development Storage database, 100 005 seeded entries (2026-11-19):**
  - before: `Seq Scan on orto_datas_building_2d_reference_update ... Filter: (COALESCE(attempts, 0) >= 5)` —
    unavoidable, no predicate with `COALESCE` can use an index;
  - after: `Index Scan using idx_orto_datas_building_2d_reference_update_attempts ... Index Cond: (attempts >= 5)`,
    `Buffers: shared hit=13`, `Execution Time: 0.039 ms` (fact `RetirePoisonReferencesCommandText_Plan`,
    `DiGi.GIS.PostgreSQL.xUnit`).
- **Behavior change shipped with it:** a failed retirement no longer returns `null` — it is logged at Error and the
  claim runs anyway (the claim's ceiling excludes the same rows), so `null` keeps meaning only "the queue could not
  be reached".
