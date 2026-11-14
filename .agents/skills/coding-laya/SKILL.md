---
name: coding-laya
description: "Use when working on the Laya decision model - checkpoint identity by DirectorySHA256, fine-tune and calibrate, LAYA_MODELS_DIRECTORY and DeployLaya.ps1, host venv outside the synced directory."
---

# AI Guidelines: Laya Decision Model — Runner, Training & Deployment

Laya is not generative: one forward pass answers typed questions (`choice`, `score`, `noul`) about a state.

> **A checkpoint folder is identified by the SHA-256 of its whole content, so nothing is ever written inside a deployed
> one — no manifest, no calibration, no training output. Checkpoints are released outside the workspace, deployed by
> `DeployLaya.ps1` from an allowlist, and the Python environment is created on each host outside the synced software
> directory.**

## Checklist
Read this first; open a section only when its line applies to the change.
- Released checkpoints outside the workspace, nothing added inside after training?
- Fine-tuned **and** calibrated on the consumer's data, beating zero-shot and the deterministic baseline held-out?
- Deploy prints `skipped (unchanged)` for untouched models and nothing unexpected under `Not deployed:`?
- Host conf names the venv `python.exe`, the model folder and its calibration file; preflight passes?
- Venv outside the synced software directory?
- Host-reported `ModelSHA256` = manifest `directorySHA256` = the training record?

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
