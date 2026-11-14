---
name: digi-guideline-change
description: "Use when adding, editing, splitting, renaming or removing an AI Guideline - edit the source and Guidelines.json, prove nothing was lost, regenerate, measure the context cost."
---

# Change an AI Guideline

Source of truth: `DiGi.Maintenance/documentation/AI Guidelines/`. Never edit a generated `.agents/skills` file or a
block between `<!-- guidelines:begin -->` and `<!-- guidelines:end -->`. Read the Checklist of
`Maintenance - AI Guidelines Propagation.md` first. From `DiGi.Maintenance/Scripts`:

1. **Edit the guideline.** Layout: `## Checklist` first (one line per actionable rule, with its section), then the
   numbered sections (rule + one-clause why + code); dated incidents and measurements go to
   `Evidence/<same name>.md` under the same section number. Section numbers never change.
2. **New, renamed or removed file:** update its entry in `Guidelines.json` (`file`, `category`, `description`
   starting `Use when`, `route` = the `CLAUDE.md` task cell) and its row in `files/README - Coding Guidelines.md`.
3. **Prove nothing was lost** (code lines, backticked identifiers, issue references, dates, numbers, sections):
   ```powershell
   PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\CheckGuidelineLossless.ps1" -BaseRef HEAD -Name "<File>.md"
   ```
4. **Regenerate** - decide `-NoCommit` or committing before the run (a `-NoCommit` run followed by a committing
   run commits nothing):
   ```powershell
   PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1" -Repo "DiGi.Maintenance" -NoCommit   # review first
   PowerShell -NoProfile -ExecutionPolicy Bypass -File ".\UpdateAgents.ps1"                                      # every repository, commits
   ```
5. **Measure** what every session now pays: `.\MeasureAgentContext.ps1`. An always-loaded file that grew needs a
   reason.
