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

## 1. Marker interfaces (`/Interfaces`)
`I<Project>Object : DiGi.Core.Interfaces.IObject` and
`I<Project>SerializableObject : I<Project>Object, DiGi.Core.Interfaces.ISerializableObject`; every serializable class
implements the latter.

## 2. Backing fields
`private readonly`, tagged `[JsonInclude, JsonPropertyName(nameof(Property))]` — always `nameof`, never a literal.

## 3. Exactly three constructors, in this order
- **Primary** `(param1, param2)` — assigns fields, no `base(...)` call.
- **Copy** `ClassName(ClassName? source) : base(source)`:
  - primitives/strings by value; a primitive list: `source.list == null ? null : new List<T>(source.list)`;
  - a list of `SerializableObject`s: iterate and `if (Core.Query.Clone(item) is ItemType item_Temp) list.Add(item_Temp);` —
    never cast `IEnumerable<T>.Clone<T>()` into an `IList<T>` field (nullable-element mismatch);
  - one nested object: `field = Core.Query.Clone(source.field);`.
- **JSON** `ClassName(JsonObject? jsonObject) : base(jsonObject) { }`.

Constructors only assign and clone; validation and cleanup belong in a `Create` factory (`Coding - General.md` §2).

## 4. Properties
`[JsonIgnore]`, get-only, returning the field (the field attribute does the serialization).

## 5. Dates are `DateTimeOffset`
Never `DateTime`: `DateTimeKind.Unspecified` drifts with the machine's UTC offset and fails `SerializationCheck`.

## 6. A `JsonValue` has two implementations — hash and compare by JSON kind
`Create.JsonNode` builds CLR-backed values (`JsonValue.Create(object)`); `JsonNode.Parse` builds element-backed ones.
They answer differently:
- `TryGetValue<T>` on a CLR-backed value is `Value is T`: a boxed `short`, `float`, `decimal`, `char`, `DateTimeOffset` or
  `Guid` fails `TryGetValue<int/long/double/string>`, while the parsed form of the same value succeeds.
- `GetValue<object>()` on a parsed value returns the `JsonElement`; an `object` dispatch then silently falls to
  `JsonElement.ToString()`.
- A whole-number `double` serializes as `5` and parses back as `int`.

Any identity, hash or equality derived from a `JsonNode` switches on `GetValueKind()` and reads the JSON-level value
(`ToJsonString()` for numbers, the decoded string for strings). Reference: `DiGi.Core.Query.UniqueHash(JsonNode)`, fact
`UniqueId_JsonObjectRoundTrip`. Numbers hash over their JSON text — shortest round-trip on .NET Core 3.0+, `G15` on .NET
Framework, the one cross-runtime split user code cannot close.
- **An `object` member holding a number** comes back from the text round trip as `double` (`UniqueValueRuleData(2010)` no
  longer `Equals` itself after a reload), and `Clone()` throws `InvalidOperationException: A value of type 'System.Object'
  cannot be converted to a 'System.Double'` ([DiGi.Core#6](https://github.com/DiGi-Organization/DiGi.Core/issues/6)).
  Until #6 ships: never key or compare such a member with `Equals` (use an invariant, width-agnostic key,
  `Coding - General.md` §1.19); `SerializationCheck` the type with a string value and mark the deferred numeric check
  `TODO [ObjectMemberClone]`.

## 7. Serializer traps that raise no error
`Query.SerializableMemberInfos` walks `BaseType` with `NonPublic | Public | Instance`; `SerializationMethodCollection` keys
the result by member name. Each trap below deserializes "successfully" with a member missing or changed:
- **Setters run in JSON document order**, not declaration order. No setter may depend on another; make a payload
  self-describing (the point-cloud reference blob repeats the count the coordinate blob carries).
- **Members de-duplicate by name across the hierarchy and the derived one wins**; a `[JsonIgnore]` at any level removes
  same-named base members too. Give derived members names that collide with nothing above.
- **A base `[JsonInclude]` property with `private set` never deserializes on a derived type** (its `SetMethod` is `null`
  there): `Typology.SubTypologies` came back empty from every `Clone` once `Typology` became generic. Use `protected set`
  or a `[JsonInclude]` private field (fields are collected only from their declaring type); `private set` only on a
  sealed class.
- **A property without a setter is written but skipped on read** — array-backed payloads travel through a settable
  single-string property.
- **A dictionary is rebuilt with `Activator.CreateInstance(type, dictionary)`**: keys travel as JSON names (a
  `Dictionary<object, T>` key `int 2010` returns as `"2010"`) and the type's default comparer returns (an ordinal
  `SortedDictionary<string, T>` turns culture-sensitive). Key by string; prefer `Dictionary<string, T>`.
- **`byte[]` is a JSON number array, never base64** (`"Bytes":[255,216,…]`). A SQL projection (`v->'Bytes'`) decodes with
  `DiGi.GIS.PostgreSQL.Convert.ToSystem_Bytes(JsonNode)`; `Convert.FromBase64String` throws. Seed fixtures from a real
  `ToJsonObject()`.
- **`Clone()` is a JSON round trip through the `JsonObject` constructor**, never the copy constructor (§9).

## 8. Options classes — the sanctioned mutable exception
`*Options : SerializableOptions` (36 of 39) use mutable
`[JsonInclude, JsonPropertyName(nameof(X))] public T X { get; set; } = default;` plus a hand-written copy constructor,
because an options window edits a copy and the task copies it back (`Coding - Background Tasks.md`). Do not convert them
to the readonly-field pattern. For a scope collection `null` means "everything", empty means "nothing" — keep the two
apart. Reference: `DiGi.Core/Classes/SerializableOptions.cs`, `PostgreSQLTerrainPointFillGapsOptions`.

## 9. The fact every serializable type gets
Build a realistic instance (a `null` optional field, at least one populated nested list/object), assert the
constructor's properties, round-trip the string form (`Convert.ToSystem_String(x)` →
`Convert.ToDiGi<T>(json)?.FirstOrDefault()`), then `Core.xUnit.Query.SerializationCheck(x)`; test `DateTimeOffset`
members across the round trip.
- **`SerializationCheck` sees only the members the instance populates, and never runs the copy constructor.** It compares
  the instance's JSON with the round-tripped JSON and with `Clone()`'s, and `Clone()` is the `JsonObject`-constructor path
  (§7); serialization is reflection-driven and never notices a default. Assert a `new T(source)` copy member by member:
  `YearBuiltPredictionPipelineOptions` gained `Radiuses`, missing from its copy constructor and its committed JSON, while
  the fact (setting only `Years`) stayed green; `UserYearBuilt`'s separate copy assertion is what fails
  (`Expected: AtOrBefore` / `Actual: Exact`) when a field is dropped.
- **Adding a member means populating it in the existing fact in the same change**, plus the copy assertion.

## Example (`/Classes/Holiday.cs`)

```csharp
using DiGi.Core.Classes;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace DiGi.EPW.Classes
{
    public class Holiday : SerializableObject, IEPWSerializableObject
    {
        [JsonInclude, JsonPropertyName(nameof(Name))]
        private readonly string? name;

        [JsonInclude, JsonPropertyName(nameof(Date))]
        private readonly string? date;

        public Holiday(string? name, string? date)
        {
            this.name = name;
            this.date = date;
        }

        public Holiday(Holiday? holiday) : base(holiday)
        {
            if (holiday != null)
            {
                name = holiday.name;
                date = holiday.date;
            }
        }

        public Holiday(JsonObject? jsonObject) : base(jsonObject) { }

        [JsonIgnore]
        public string? Name => name;

        [JsonIgnore]
        public string? Date => date;
    }
}
```

The `.csproj` needs a `DiGi.Core` `HintPath` reference and the solution's `System.Text.Json` `PackageReference` version.
