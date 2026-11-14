---
name: digi-api
description: "Use when you need the signature or summary of a DiGi type or member - look it up in the generated API docs with GetApi.ps1 instead of opening a namespace page or a .cs file."
---

# Look up a public API

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File "DiGi.Maintenance/Scripts/GetApi.ps1" -Assembly "DiGi.Core" -Match "Query\.Clone"
```
- `-Assembly` is the folder under `documentation/API` (an unknown name lists the near matches).
- `-Match` is a regular expression on the fully qualified member name: `"Query\.Clone"` (a method and its
  overloads), `"Classes\.SerializableObject\."` (the members of a type), `"\.IReference$"` (one type).
- Output per member: its name, then `signature  // summary`. `-Max` caps the list (default 40).

A namespace page of `documentation/API` runs to hundreds of kilobytes - never read one whole. Open the `.cs` file
only to edit it or to read internal logic. The docs are as fresh as the last build of the assembly: after changing
a signature or a doc comment, rebuild before looking it up again.
