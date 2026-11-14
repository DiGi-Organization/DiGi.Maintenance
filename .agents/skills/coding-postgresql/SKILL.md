---
name: coding-postgresql
description: "Use when writing Npgsql/PostgreSQL code - NULLS NOT DISTINCT keys, batching, forwarded timeouts and tokens, partition pruning, disposal, whitelisted identifiers, production only through the API, *_Test.conf databases."
---

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

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
