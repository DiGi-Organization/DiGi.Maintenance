---
name: coding-yolo
description: "Use when working on the YOLO Year Built detector - model.pt resolution and SHA-256, training data and scratch outside the workspace, chunked scratch, allowlisted runner deploy."
---

# AI Guidelines: YOLO Year Built Detector — Runner, Training & Deployment

> **Only the shipped detector `YOLO/models/model.pt` is deployment content. Training inputs, earlier weights and run
> scratch live in a training directory outside the workspace, and the runner extension is deployed from an allowlist —
> never a blocklist.**

## Checklist
Read this first; open a section only when its line applies to the change.
- `user files/` holds only the conf, prediction options and `model.pt`?
- Training/labelling options name an absolute `ScratchDirectory` and absolute inputs in the training directory?
- New imagery-writing code uses bounded chunk folders, never one flat per-county folder?
- After a deploy: ~212 files / 268 MB, `scratch*`, `logs`, `reports` under `Not deployed:`, no warning?
- New detector: `model.pt` replaced, old weights kept in the training directory, SHA-256 on the issue, year built
      re-measured with `YearBuiltPredictionEvaluationConsoleApp`?

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
