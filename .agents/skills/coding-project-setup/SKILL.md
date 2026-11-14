---
name: coding-project-setup
description: "Use when creating a project or repository from templates/ or changing build configuration - .gitignore, Directory.Build.props, analyzers and suppressions, .editorconfig overrides only under [*.cs], DIGI0001."
---

# AI Guidelines: Project Setup — Templates, New Repositories, `.editorconfig`, Build Props, Analyzers

## Checklist
Read this first; open a section only when its line applies to the change.
- Scaffold from `templates/` directly under the workspace root (relative `HintPath`s break one level deeper) (§1).
- New repository: replace `.gitignore` from the template before the first commit and prove `git check-ignore -v "user files/x"`; then the eight setup steps in order (§2).
- Build settings live only in `Directory.Build.props` (`LangVersion latest`, `TreatWarningsAsErrors`, `AnalysisLevel latest-recommended`); core libraries `netstandard2.0`; `System.Threading.Lock` only in net9+ (§3).
- An analyzer finding gets its behavior-preserving fix — never a silent culture switch, never `CA1822` on a public member, never a rename of a public or wire type; suppress at the site with a reason (§3 lists the fix per rule).
- `.editorconfig` is copied from the template; nothing but `root = true` above the first `[section]`; overrides under `[*.cs]`, a repository-only override in its own section below (§4). Check: `DiGi.Maintenance/Scripts/CheckGuidelineRules.ps1 -Repo <Repo>`.
- A Roslyn analyzer is two `netstandard2.0` projects and never references `Microsoft.CodeAnalysis.Workspaces` (§5).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
