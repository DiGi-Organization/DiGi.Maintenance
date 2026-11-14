---
name: github-sub-issues
description: "Use when splitting a feature into sub-issues - a tracking issue with the shared spec plus one self-contained sub-issue per repository, sibling order as blocked_by."
---

# AI Guidelines: GitHub Sub-Issues (Tracking-Issue Pattern)

Whenever the user asks for **sub-issues** or **sub-tasks** of a feature, use this pattern — never a flat pile of
independent issues. Canonical example, *External Components Area*: parent
[DiGi.GIS.PostgreSQL #83](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/83); children
[DiGi.GIS.IO #11](https://github.com/DiGi-Organization/DiGi.GIS.IO/issues/11) (column definitions) ·
[DiGi.GIS.PostgreSQL #82](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL/issues/82) (computation + task) ·
[DiGi.GIS.PostgreSQL.UI #12](https://github.com/DiGi-Organization/DiGi.GIS.PostgreSQL.UI/issues/12) (UI task).

## 1. When
The feature spans two or more repositories (or coordinated workstreams: definitions → computation → UI), the shared design
must survive as one source of truth, and one issue cannot hold both the design and every repository's scope. Single-repo,
single-workstream work stays a plain issue.

## 2. Roles
- **Tracking issue (parent)** — the feature: shared spec, data flow, decisions, end-to-end acceptance, the Sub-issues table;
  no implementation scope of its own. Lives in the repository owning the core logic/data flow.
- **Sub-issue (child)** — one repository's slice, implementable without reading the other repositories. One per repository.

## 3. Parent structure (in order, as #83)
1. `## Summary` — the feature (its **name** is the identifier children cite) and the new public artefacts.
2. Domain spec sections — what every child implements, stated once (tables, rules, a `## Data flow` code block).
3. `## Sub-issues` — mandatory:
   ```markdown
   | Repository | Issue | Scope |
   |---|---|---|
   | DiGi.GIS.IO | #11 | `External Components Area` category + 35 static `Column.External*` fields (+ helper) |
   | DiGi.GIS.PostgreSQL | #82 | `Modify.Update_ExternalComponentsArea` classification + background task |
   | DiGi.GIS.PostgreSQL.UI | #12 | UI wrapper task, options window, registration in `VisualBackgroundTasks.cs` |
   ```
   One row per child, **in dependency order**; bare `#number`; a one-line scope naming the key types/methods.
4. `## Decisions` — naming and collision calls, boundary ownership, explicit out-of-scope and follow-ups.
5. `## Acceptance criteria` — **end-to-end**, not per repository.

## 4. Child structure (in order, as #11/#82/#12)
1. `## Context` — first sentence always: *This is a sub-issue of the \<Feature Name\> tracking issue (\<parent
   repository\>).* (`(this repository)` when shared); then which part it owns and which sibling repository owns the rest.
2. `## Scope` (or `## Part 1 — …`) — this repository only: exact type names, paths, sketches, rules, constants.
   **Self-contained:** repeat implementable detail (name tables, thresholds, formulas) — never "see parent".
3. `## Tests` (`DiGi.Test`) — the `[Fact]` list with boundary cases, when the slice has logic.
4. `## Acceptance criteria` — local, each verifiable in this repository.

## 5. Wiring
Parent → children: the table. Child → parent and siblings: the `## Context` sentence. Child → a sibling it waits on, or
any issue → an external blocker: a GitHub **issue dependency** (`blocked_by`, `GitHub - Issues.md` §5). No comments are
needed for the parent/child wiring.

## 6. Creation workflow
1. Write the parent body first (UTF-8 no BOM, LF — `GitHub - Issues.md` §1).
2. Decompose: one child per repository, dependency order, each independently implementable, together covering the parent's
   acceptance without overlap.
3. Create the parent (mandatory labels and assignee) with placeholder table rows.
4. Create each child in its own repository with its **own** labels and assignee — tier `ai:` from its own scope
   (`GitHub - Labels.md` §3), never copied from the parent.
5. Fill the table with real numbers (`gh issue edit … --body-file …`); set `blocked_by` for every child waiting on a sibling
   and verify with the `blocking` GET.
6. Verify: every Context sentence names feature + parent repository; one row per child in order; children self-contained;
   every parent criterion covered by a child.

## 7. Lifecycle
The parent stays open while any child is open. Close children as they land (resolution comment, `GitHub - Issues.md` §3),
tick the parent's criteria as they close, close the parent last with a summary of every child and its commits.

## 8. Anti-patterns
A flat pile of issues · nesting beyond one level · one child spanning two repositories · a parent that is only links · a
child deferring implementable detail to the parent · copying the parent's labels or tier.
