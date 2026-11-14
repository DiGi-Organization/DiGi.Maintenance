---
name: coding-serialization
description: "Use when creating or changing a SerializableObject or *Options type, or debugging a JSON round trip - three constructors, [JsonInclude] fields, DateTimeOffset, serializer traps, SerializationCheck plus copy-constructor facts."
---

# AI Guidelines: Serialization (`SerializableObject` / `ISerializableObject`)

A `/Classes` type needing JSON persistence, cloning or polymorphic deserialization inherits
`DiGi.Core.Classes.SerializableObject`. Item numbers are stable: `Coding - General.md` §5.n means item n here.

## Checklist
Read this first; open a section only when its line applies to the change (the complete pattern is the Example at the end).
- The class implements `I<Project>SerializableObject` (§1).
- Fields `private readonly` with `[JsonInclude, JsonPropertyName(nameof(Property))]` (§2); properties `[JsonIgnore]` get-only (§4).
- Exactly three constructors in order: primary, copy `ClassName(ClassName? source) : base(source)` cloning nested objects with `Core.Query.Clone`, JSON `ClassName(JsonObject? jsonObject) : base(jsonObject) { }` (§3).
- Dates are `DateTimeOffset`, never `DateTime` (§5).
- Hash or compare a `JsonNode` by `GetValueKind()`; an `object` member holding a number reloads as `double` — never `Equals` it, mark `TODO [ObjectMemberClone]` (§6).
- Silent serializer traps: setters run in document order, same-named members de-duplicate (derived wins), base `private set` never deserializes on a derived type, no setter = skipped on read, dictionaries keyed by string, `byte[]` is a number array, `Clone()` is a JSON round trip (§7).
- `*Options : SerializableOptions` stay mutable with a hand-written copy constructor; `null` scope = everything, empty = nothing (§8).
- The fact: realistic instance, string round trip, `Core.xUnit.Query.SerializationCheck(x)` **plus** a member-by-member `new T(source)` assertion; a new member is populated in the existing fact in the same change (§9).

**Sections (rules in full, code, traps):** [guideline.md](guideline.md) - before changing code a checklist line covers, read the section it names.
