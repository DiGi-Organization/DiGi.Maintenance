# AI Token Optimization — Prompt Templates & Quality Checklist

Token-efficient prompt structures for the routine DiGi tasks. Each template names a script output and a guideline
checklist instead of pasting rules or files. The same content ships as workflow skills
(`files/skills/<name>/SKILL.md` → `.agents/skills`, `.claude/skills`), so with a skill-aware agent the short form is
enough: *"use digi-verify"*.

## 1. Structure every template follows
1. **Task** — one sentence, the repository and the issue (`DiGi.Repo#N`).
2. **Context by reference** — the guideline to read (its `## Checklist` first, a section only when a line applies) and
   the script that answers the factual question. Never paste a guideline, a namespace page or a log.
3. **Scope** — the files or members to touch; what is out of scope.
4. **Done means** — the script outputs that must be clean.

## 2. Templates

### Implement or change C# (skill `digi-verify`)
```text
Task: <what> in <Repo> (<Repo>#<n>).
Read: Checklist of "Coding - General.md"; plus "<Coding - Topic>.md" Checklist if the change touches <topic>.
API: look members up with GetApi.ps1 -Assembly "<Assembly>" -Match "<regex>" - do not open namespace pages.
Scope: <files/members>. Out of scope: <...>.
Done: CheckGuidelineRules.ps1 -Repo <Repo> -Changed clean (or each hit justified);
      TestSummary.ps1 -Library <lib.csproj> -Project <lib.xUnit> all passed; new public members have XML docs.
```

### Review a change
```text
Task: review the uncommitted change in <Repo>.
Run: CheckGuidelineRules.ps1 -Repo <Repo> -Changed, then read only `git diff` (not whole files).
Check against: Checklist of "Coding - General.md" (+ the topic guideline the diff touches).
Report: findings as file:line - rule (guideline §) - fix. No summary of what the code does.
```

### Add a serializable type
```text
Task: add <Type> to <Repo>/Classes.
Read: Checklist and Example of "Coding - Serialization.md".
Done: three constructors, [JsonInclude] readonly fields; one fact with SerializationCheck AND a member-by-member
      new <Type>(source) assertion; TestSummary.ps1 green.
```

### XML documentation pass
```text
Task: document the public members of <file or namespace> in <Repo>. Touch /// comments only.
Read: "XML Documentation.md" (short, read whole).
Input: GetApi.ps1 -Assembly "<Assembly>" -Match "<Namespace>\." lists the members and their current summaries.
Done: every public member has <summary>, <param> in signature order, <returns>; build has no CS1573.
```

### After changing a public surface
```text
Task: confirm nothing downstream broke after <change> in <Repo>.
Run: BuildAll.ps1 -Configuration Debug -Summary  (prints FAIL/WARN solutions only).
Report: the failing solutions with their diagnostics; fix the .csproj or the caller per "Coding - Host Dependencies.md" §6.
```

### Before a commit, pull or sweep (skill `digi-status`)
```text
Run: StatusAllRepos.ps1. Act per the Checklist of "GitHub - Branches and Commits.md":
     commit on the active version branch, explicit paths, no push unless asked.
```

### Issues (skill `digi-issue`)
```text
Task: <list | read | create | close> issue(s) <filter or Repo#n>.
Run: FilterIssues.ps1 <-Repo/-Labels/-Search/-Issue n -Detail>. Read -Full only for the issue being worked on.
Rules: Checklist of "GitHub - Issues.md" - verify premises first; Type + Priority + ai: labels, assignee
       ZiolkowskiJakub; blocked issues are not started.
```

### Guideline change (skill `digi-guideline-change`)
```text
Task: <add | edit | split | rename | remove> guideline "<File>.md".
Read: Checklist of "Maintenance - AI Guidelines Propagation.md" (it is short: §1.7-1.9 and §2).
Done: Guidelines.json entry correct; CheckGuidelineLossless.ps1 -BaseRef HEAD green;
      UpdateAgents.ps1 run once (decide -NoCommit first); MeasureAgentContext.ps1 totals not grown without a reason.
```

## 3. Quality guardrail — what compression must never strip
Run through this before accepting any change that shortens a prompt, a guideline or a script output.

| Guard | How it is verified |
|---|---|
| No rule, identifier, issue reference, measurement or section number lost from a guideline | `CheckGuidelineLossless.ps1 -BaseRef <commit>` exits 0 |
| `File.md §n` citations in code still resolve | section headings unchanged (same check); moved sections leave a pointer |
| Explicit types (no `var`), block-scoped namespaces, `new()`, `[]` | the build (`TreatWarningsAsErrors`, template `.editorconfig`) — never rely on the prompt alone |
| English identifiers and comments; naming by type (`pointNode_Base`, `point3Ds`) | stays in the always-loaded rules; reviewed by the LLM — no script judges it |
| XML documentation on every public member, params in signature order | CS1573 in the build; a missing comment (CS1591 is off) is checked from `GetApi.ps1` output showing an empty summary |
| Serialization contract (three constructors, `_type` stability, copy-constructor fact) | `SerializationCheck` fact plus the direct copy assertion; `TestSummary.ps1` |
| GIS keying (county `id`, not `code`; `fallbackByReference: true`) | always-loaded trap line + Checklist of `Coding - GIS Administrative Data.md`; never summarised away |
| BIM/host metadata: `HintPath` closure, `deps.json`, Grasshopper `ComponentGuid` | `CheckHostDependencies.ps1`; the routed guideline's Checklist |
| A script summary hides nothing that fails | `BuildAll.ps1 -Summary` and `TestSummary.ps1` print every error and warning diagnostic and keep the tool's exit code |
| A checklist line states the rule, not only a topic | review when adding one: could an agent comply having read only that line? |
| The always-loaded set did not grow silently | `MeasureAgentContext.ps1` before and after |
