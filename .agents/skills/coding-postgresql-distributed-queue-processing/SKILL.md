---
name: coding-postgresql-distributed-queue-processing
description: "Use when designing or maintaining a claim/acknowledge update queue in PostgreSQL - FOR UPDATE SKIP LOCKED, attempts and poison-row retirement, lease vs batch time, ownership, observation vs coverage."
---

# AI Guidelines: PostgreSQL Distributed Queue Processing

**Reference implementation:** the orthophoto download queue `orto_datas_building_2d_reference_update` —
`OrtoDatasPostgreSQLConverter.UpdateBuilding2DReferencesAsync` (enqueue), `GetNextBuilding2DReferencesAsync` (retire +
claim), `AcknowledgeBuilding2DReferencesAsync`, `GetQueueSummariesByCountyIdsAsync`, and the
`nextbuilding2dreferences` / `acknowledgebuilding2dreferences` / `queuesummariesbycountyids` actions of
`OrtoDatasController`. **When this document and that code disagree, the code is the current state — fix the document.**

## Checklist
Read this first; open a section only when its line applies to the change.
- Schema has `claimed_at timestamptz` and `attempts INT NOT NULL DEFAULT 0`, each with its `ADD COLUMN IF NOT EXISTS`?
- Enqueue, claim and acknowledge run the DDL, not an existence check?
- `UNIQUE (county_id, reference)` with `county_id` a county **part** id?
- Claim index `(claimed_at ASC NULLS FIRST, created_at ASC)` and a claim ordered the same way?
- Claim uses `FOR UPDATE SKIP LOCKED`, native interval multiplication, increments `attempts`, parenthesised lease condition before the ceiling?
- Claim method takes `count`, `claimTimeoutMinutes`, `maxAttempts`, `commandTimeout`, token; controller binds `maxattempts`?
- `claimTimeoutMinutes` above the worst-case batch time?
- Acknowledge by `id = ANY(@ids)`, idempotent target or owner-checked on `claimed_at`?
- Re-enqueue during a claim covered (`DO NOTHING`) or reset (`DO UPDATE`), documented on the producer?
- Retirement before the claim, every retired reference logged at Error?
- Acknowledgment only after the storage write succeeded?
- Read-only observation reports attempted rows; completeness measured on the target per county part?
- XML documentation on every public method and endpoint?

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
