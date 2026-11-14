---
name: xml-documentation
description: "Use when reading a public API (documentation/API before .cs) or adding or auditing XML doc comments - every public member, params in signature order, one summary, no docs on partial declarations."
---

# AI Guidelines: XML Documentation & Generated API Docs

## 1. Reading the generated API docs (before opening `.cs`)
`documentation/API/<AssemblyName>/` in each repository holds one Markdown file per namespace (`DiGi.Core.Classes.md`)
with exact signatures and `<summary>`s of every public member. Read it to learn a public API; open `.cs` only to edit it
or to read internal logic. Fallback when the folder is absent: the source and `bin/*.xml`. The docs regenerate on every
build — rebuild after changing a signature or a doc comment. A namespace page runs to hundreds of kilobytes: look a
member up instead of reading the page —
`DiGi.Maintenance/Scripts/GetApi.ps1 -Assembly "DiGi.Core" -Match "Query\.Clone"` prints `signature  // summary` per match.

## 2. Rules for every doc comment
1. Touch `///` comments only — never code logic.
2. Every public constructor, property, method and enum value is documented: `<summary>`, every `<param>` (in signature
   order — reorder when parameters move, e.g. `CancellationToken` last), `<returns>`, `<typeparam>` — no CS1591/CS1573.
   The build reports only CS1573 (a parameter without its tag): CS1591 (a member without any comment) is switched off
   in `.editorconfig` (`Coding - Project Setup.md` §4), so a missing comment is yours to catch.
3. Exactly one `<summary>` per member; overwrite a stale one, never append a second.
4. No blank or bare `///` lines inside a block (breaks Visual Studio tooltips); paragraph breaks are `<para>` (preferred
   over `<remarks>`):
   ```csharp
   /// <summary>
   /// Calculates total volume of selected elements.
   /// <para>Operation may take time on large models.</para>
   /// </summary>
   ```
5. Do not document a `partial` class declaration itself — only its members.
6. An override gets its own full `<summary>` (the norm), not `<inheritdoc/>`.
7. Refer to a parameter from prose with `<paramref name="x"/>`; a `<param>` inside a `<summary>` reads as a duplicate tag.
8. Cite the issue a non-obvious rule comes from as `(DiGi.Repo#N)` — in `//` comments too, which explain *why* in full
   sentences.
9. Use the sibling `LibraryName.xml` beside a referenced `LibraryName.dll` for exact external terminology.
10. Output the updated files only, no conversational text.

## 3. Modes
- **Create:** add the missing tags; leave existing correct docs untouched.
- **Audit:** additionally rewrite stale summaries, delete `<param>`s of removed parameters, add new ones and reorder to the
  current signature; enforce explicit typing (no `var`) in any code example touched.

Bulk generation may be delegated to an `lm_studio` tool where the agent has one (OpenCode's `xml-doc-*` agents);
otherwise edit directly.
