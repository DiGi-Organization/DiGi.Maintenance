---
name: coding-references
description: "Use when comparing, matching, keying or de-duplicating an IReference/IUniqueReference - == between two interface-typed references is a silent reference comparison, use Core.Query.Equals, accessors clone per call, and how to detect and fix existing occurrences."
---

# AI Guidelines: References (`IReference` / `IUniqueReference`)

> **NEVER compare two interface-typed references with `==` or `!=`. ALWAYS use `Core.Query.Equals(reference_1, reference_2)`.**

`==` between interface-typed operands compiles to **reference equality** and silently returns `false` for equal
references, with no warning.

## 1. Types
- **Interfaces** (`DiGi.Core/Interfaces/Reference/`): `IObject` → `IReference` → `ISerializableReference` →
  `IInstanceRelatedSerializableReference` → `IUniqueReference` (adds `TypeReference`, `UniqueId`); also
  `ITypeRelatedSerializableReference`, `IComplexReference`, `IExternalReference`.
- **Classes** (`DiGi.Core/Classes/Reference/`): `SerializableObject` → `SerializableReference` (defines `ToString()`,
  `Equals()`, `==`/`!=`) → `UniqueReference` (`GuidReference`, `UniqueIdReference`), `TypeReference`, `ComplexReference`,
  `ExternalReference` → `InstanceRelatedExternalReference<T>` → `UniqueExternalReference<T>` (implements `IUniqueReference`).
- **Never cast `IReference` to `SerializableReference`:** implementations may derive from `SerializableObject` directly
  (`GISModelAreal2DReference`) or implement `IReference` alone (`ListClusterReference`); `IUniqueReference` has two class
  branches.

## 2. Equality
`ToString()` is sealed and cached (type discriminator + `Segments`) and defines identity; `GetHashCode()` derives from it;
`Equals(IReference?)` requires matching runtime types and strings. `Dictionary<IUniqueReference, …>`, `HashSet<IReference>`,
`List.Contains`/`Find`/`Remove` are safe (they use `Equals`/`GetHashCode`).

| `==` operand static types | Binds to | Status |
|---|---|---|
| both interfaces | reference equality | **silent bug** |
| at least one concrete `SerializableReference` | `SerializableReference.operator ==` → `Equals` | correct |
| one side `null` | null check | correct |
| `.ToString()` on both | string comparison | correct (allocates) |

Operators cannot be added to the interfaces: interfaces contribute no `==` candidates, a helper-declared operator needs the
declaring type (CS0563), and static abstract interface operators need generic constraints and .NET 7+ (`DiGi.Core` is
`netstandard2.0`).

## 3. Clone-per-call accessors
Model reference properties (`face.UniqueReference`) return `Core.Query.Clone(field)` — a new instance per call, so
`face.UniqueReference == face.UniqueReference` is `false`. Hoist to a local before comparing; never use a returned instance
as an identity token.

| Intent | Code |
|---|---|
| Compare two references | `Core.Query.Equals(reference_1, reference_2)` (null-safe) |
| Concrete type access | `if (uniqueReference is GuidReference guidReference)` |
| Model object identity | compare the object `Guid` (references identify target data, not the container) |

## 4. Audit
```bash
rg --pcre2 -n -g '*.cs' -i '\b[A-Za-z0-9_]*uniqueReference[A-Za-z0-9_]*\s*(==|!=)\s*(?!null)[A-Za-z_(]'
rg --pcre2 -n -g '*.cs' '\b[A-Za-z0-9_]*[Rr]eference[A-Za-z0-9_]*\s*(==|!=)\s*(?!null)[A-Za-z_(]'
```
A hit is a bug **only if both operands are interface-typed**: `x.UniqueReference == face.UniqueReference` → bug;
`x.UniqueReference_From == guidReference` → fine (concrete right side); `face.UniqueReference != null` → fine.
```csharp
// INCORRECT — silent reference equality
int index = faces.FindIndex(x => x.UniqueReference == face.UniqueReference);

// CORRECT — hoist, compare with Core.Query.Equals
IUniqueReference? uniqueReference = face.UniqueReference;
int index = faces.FindIndex(x => Core.Query.Equals(x?.UniqueReference, uniqueReference));
```
