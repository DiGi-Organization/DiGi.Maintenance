---
name: xml-documentation
description: "Use when reading a type's public API (documentation/API/ before .cs), adding missing XML doc comments, or auditing existing ones against current signatures - every public member documented, params in signature order, one summary, no blank lines (<para>), no docs on partial declarations, full summaries on overrides, issue citations."
---

# AI Guidelines: XML Documentation & Generated API Docs

## 1. Reading the generated API docs (before opening `.cs`)
`documentation/API/<AssemblyName>/` in each repository holds one Markdown file per namespace (`DiGi.Core.Classes.md`)
with exact signatures and `<summary>`s of every public member. Read it to learn a public API; open `.cs` only to edit it
or to read internal logic. Fallback when the folder is absent: the source and `bin/*.xml`. The docs regenerate on every
build — rebuild after changing a signature or a doc comment.

## 2. Rules for every doc comment
1. Touch `///` comments only — never code logic.
2. Every public constructor, property, method and enum value is documented: `<summary>`, every `<param>` (in signature
   order — reorder when parameters move, e.g. `CancellationToken` last), `<returns>`, `<typeparam>` — no CS1591/CS1573.
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
