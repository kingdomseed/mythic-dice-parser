# Spec Validation Report

**Date:** 2026-03-15
**Spec Under Review:** `draft spec.md` (Draft v2)
**Codebase:** `kingdomseed/mythic-dice-parser` (current `main` branch)

---

## 1. Current Architecture (Section 1)

### 1.1 "How It Works Today"

**Claim:** The parser converts dice notation into a binary expression tree. Evaluation is bottom-up. Results flow upward as `RollResult` objects containing `List<int>`.

**INCORRECT.** The spec describes the **upstream `main`** branch, not the fork's current state. In the fork:

- `RollResult.results` is `IList<RolledDie>`, not `List<int>`. The PR #6 work is already merged.
- Evaluation is **async** (`Future<RollResult>`), not synchronous. The async conversion is already done.
- `DiceRoller` is already abstract with `Stream<int>` methods, not an internal `Random` wrapper.

The spec's Section 1 describes the **pre-PR-#6, pre-async** state. The fork has already moved past this.

### 1.2 Key Types (Current Release)

| Spec Claim | Verdict | Actual State |
|---|---|---|
| `DiceExpression.create(String, [Random])` | **INCORRECT** | `create(String input, {DiceRoller? roller})` -- accepts named `DiceRoller?`, not positional `Random?` |
| `DiceExpression.roll()` returns `RollSummary` | **CONFIRMED** (async) | Returns `Future<RollSummary>` |
| `RollResult` contains `results: List<int>` | **INCORRECT** | `results: IList<RolledDie>` |
| `RollResult` contains `metadata: Map` | **INCORRECT** | No `metadata` field. Has `discarded: IList<RolledDie>`, `left`/`right` tree refs, `opType`, `expression` |
| `RollSummary` contains `results: List<int>` | **INCORRECT** | `results: IList<RolledDie>` |
| `RollSummary` contains `metadata: Map` | **INCORRECT** | Has `successCount`, `failureCount`, `critSuccessCount`, `critFailureCount` as individual fields |
| `DiceRoller` is internal, wraps `Random` | **INCORRECT** | `DiceRoller` is an abstract class, publicly exported, with `Stream<int> roll()` and `Stream<T> rollVals<T>()` |

### 1.3 Data Flow

**INCORRECT.** The spec shows synchronous `DiceRoller(internal) -> Random` flow. The fork already has:
- `DiceRoller` (abstract) -> `RNGRoller` (wraps `Random`), `PreRolledDiceRoller`, `CallbackDiceRoller`
- `DiceResultRoller` wraps `DiceRoller` and returns `Future<RollResult>` with `RolledDie` objects
- All AST `eval()` methods are `Future<RollResult>`

---

## 2. Current Limitations (Section 2)

| Limitation | Verdict | Notes |
|---|---|---|
| **L1:** Results are plain integers | **ALREADY_DONE** | `RolledDie` objects exist with `result`, `nsides`, `dieType`, 15+ boolean state flags, `potentialValues`, `from` |
| **L2:** Synchronous-only evaluation | **ALREADY_DONE** | All `eval()` methods return `Future<RollResult>`. `roll()` returns `Future<RollSummary>`. `call()` returns `Future<RollResult>`. |
| **L3:** No pluggable DiceRoller | **ALREADY_DONE** | `DiceRoller` is abstract. `RNGRoller`, `PreRolledDiceRoller`, `CallbackDiceRoller` all exist. `DiceExpression.create()` accepts `DiceRoller?` parameter. |
| **L4:** No dice pool identity/grouping/tagging | **CONFIRMED** (still a limitation) | No label, tag, or `groupLabel` fields exist on `RolledDie`. Comma operator exists but produces flat results. |
| **L5:** Results always summed | **PARTIALLY_DONE** | `#s`/`#f`/`#cs`/`#cf` scoring exists and works at the `RolledDie` level (boolean flags). But `total` is always a sum. |
| **L6:** No re-roll-with-lock | **CONFIRMED** (still a limitation) | No `locked` field on `RolledDie`. No `reroll()` method on results. |
| **L7:** No named formulas | **CONFIRMED** (correctly identified as client concern) | |
| **L8:** No inline string labels | **CONFIRMED** (still a limitation) | Grammar has no string literal support. |
| **L9:** Custom faces limited to inline | **CONFIRMED** (still a limitation) | No `registerDieType()` exists. |
| **L10:** No dice bag | **CONFIRMED** (correctly identified as client concern) | |
| **L11:** No event model for progressive delivery | **CONFIRMED** (still a limitation) | Listener system exists but no "about to roll" events. |
| **L12:** No concurrency for parallel sub-expressions | **CONFIRMED** (still a limitation) | Binary ops evaluate left then right sequentially (`await left()` then `await right()`). No `Future.wait`. Note: upstream PR #7 had a `simultaneousRolls` flag for this; the fork does NOT have it. |
| **L13:** Roll method returns flattened RollSummary | **PARTIALLY_DONE** | `RollSummary` has `detailedResults: RollResult` which is the full tree. Accessible directly, not only via JSON. But the tree is still internal structure, not a cleaner public API. |
| **L14:** Static global listener registration | **CONFIRMED** (still a limitation) | `DiceExpression.listeners` and `summaryListeners` are static. Per-roll `onRoll`/`onSummary` callbacks exist on `roll()`. |

**Key finding:** The spec says "PR #6 addresses L1" and "PR #7 addresses L2/L3" as future work. Both are **already absorbed into the fork**. The spec's framing of L1, L2, L3 as "current limitations" is outdated relative to the fork's actual state.

---

## 3. User Requests Mapping (Section 3)

**CONFIRMED** with caveat. The mapping table is logically correct in identifying which limitations block which user requests. However, since L1, L2, and L3 are already resolved in the fork, the actual blocking set for each request is smaller than the table implies.

For example:
- **3D animated dice** lists L2, L3, L11, L12. Since L2 and L3 are done, only L11 and L12 remain.
- **Bluetooth dice** lists L2, L3, L11. Only L11 remains.
- **Savage Worlds** lists L1. This is **already unblocked** in the fork.

---

## 4. Package vs Client (Section 4)

### 4.1 Responsibility Matrix

**CONFIRMED.** The responsibility assignments are sound and well-reasoned. The boundary principle (package parses/evaluates/structures; client renders/persists/animates) is appropriate.

### 4.3 "What This Means Concretely" -- Package Ships:

| Item | Verdict | Notes |
|---|---|---|
| `RolledDie` rich result objects | **ALREADY_DONE** | Exists with more flags than the spec lists (15+ booleans vs spec's ~6) |
| `DiceRoller` abstract + `DefaultDiceRoller` | **PARTIALLY_DONE** | `DiceRoller` is abstract but uses `Stream<int>` not `Future<List<int>>`. No class named `DefaultDiceRoller` -- the equivalent is `RNGRoller`. |
| Async `roll()` returning `Future<RollOutcome>` | **PARTIALLY_DONE** | `roll()` is async but returns `Future<RollSummary>`, not `Future<RollOutcome>`. No `RollOutcome` type exists. |
| Group/label grammar | **NOT_DONE** | No label/tag parsing in grammar |
| Tag passthrough | **NOT_DONE** | No tag fields on any types |
| Push support (`reroll()`) | **NOT_DONE** | No `locked` field, no `reroll()` method |
| Named die type registry | **NOT_DONE** | No `registerDieType()` |
| Per-roll callbacks | **ALREADY_DONE** | `roll(onRoll:, onSummary:)` exists |

---

## 5. Design Decisions D1-D9 (Section 5)

### D1: PR #6 Merge Strategy

**Decision:** Merge `roll-results-obj` wholesale.

**ALREADY_DONE.** The fork already contains all PR #6 work: `RolledDie`, `DieType`, split AST files (`ast_core.dart`, `ast_ops.dart`, `ast_dice.dart`), async conversion, comma support, sort, penetrating dice, aggregate `{}`. The `diceui` directory is NOT present in the fork (correctly excluded -- no coupling to core).

**Note:** The spec says "31 commits" but the analysis found 26 commits. Minor discrepancy, **UNVERIFIABLE** without direct upstream access, but not material.

### D2: DiceRoller Interface Shape

**Decision:** `Future<List<int>>` with `roll(ndice, nsides, min)` and `rollCustomFaces(ndice, faces)`.

**INCORRECT -- fork diverges from spec.** The fork's actual interface is:

```dart
abstract class DiceRoller {
  Stream<int> roll({required int ndice, required int nsides, int min = 1, DieType dieType = DieType.polyhedral});
  Stream<T> rollVals<T>(int ndice, List<T> vals, {DieType dieType = DieType.polyhedral});
}
```

Key differences:
1. **`Stream<int>` vs `Future<List<int>>`** -- The fork uses streams, collected via `.toList()` internally. The spec wants futures returning lists.
2. **`rollVals<T>` vs `rollCustomFaces`** -- The fork has a generic `rollVals<T>` instead of `rollCustomFaces` limited to `List<int>`.
3. **`DieType` parameter** -- The fork passes `DieType` to the roller (so the roller knows what kind of die it's rolling). The spec's interface does not include this.
4. **No `DefaultDiceRoller`** -- The fork has `RNGRoller` (equivalent name).
5. **`DiceResultRoller` layer** -- The fork has an additional `DiceResultRoller` class that wraps `DiceRoller` and returns `Future<RollResult>` with `RolledDie` objects. The AST nodes use `DiceResultRoller`, not `DiceRoller` directly.

**Assessment:** The fork's architecture is arguably **better** than the spec's proposal because:
- The `DieType` parameter lets rollers (e.g., 3D dice) know what shape to animate.
- The two-layer design (`DiceRoller` -> `DiceResultRoller`) cleanly separates "produce randomness" from "wrap in RolledDie".
- `Stream<int>` vs `Future<List<int>>` is functionally equivalent since streams are always collected before evaluation. However, `Stream` adds slight complexity. The spec's rationale for `Future<List<int>>` (engine always needs complete list before proceeding) is sound.

**Recommendation:** The fork's current interface works. Changing to `Future<List<int>>` is optional but would simplify the API. The `DieType` parameter is a genuinely useful addition the spec missed.

### D3: Sync Convenience Method

**Decision:** No sync convenience. One path: `Future`.

**ALREADY_DONE.** The fork has no sync path. `call()` returns `Future<RollResult>`, `roll()` returns `Future<RollSummary>`.

### D4: Backward Compatibility

**Decision:** Zero compatibility window.

**CONFIRMED.** Appropriate for a private fork.

### D5: PetitParser Version

**Decision:** Use PetitParser 6.1.0 per Steve's lead.

**CONFIRMED.** `pubspec.yaml` has `petitparser: ^6.1.0`. Comment in pubspec: `# TODO: upgrade to 7.0.0 once version constraints from stable flutter sdk don't barf`.

### D6: Label/Tag Grammar Design

**Decision:** Design grammar for `"Label:" NdN` and `@key=value` within comma-separated groups.

**NOT_DONE.** The comma operator exists in the grammar (parser.dart line 137), but no label or tag parsing exists. The comma operator currently creates `CommaOp` which collapses sub-expression results into `singleVal` totals. This is the structural prerequisite the spec mentions.

**Important observation:** The current `CommaOp` implementation totalizes each sub-expression (wraps in `RolledDie.singleVal(result: sum, totaled: true)`), which means individual die identity is lost when using commas. This behavior would need to change for the labeled groups feature to work properly (groups need to preserve individual die results).

### D7: Push Mechanic

**Decision:** Method on result object, not grammar syntax.

**NOT_DONE.** No `locked` field on `RolledDie`, no `reroll()` method on `RollSummary` or any result type.

### D8: Aggregation Strategy

**Decision:** Use existing `#s`/`#f`/`#cs`/`#cf` scoring. Extend with per-group scoring.

**PARTIALLY_DONE.** The scoring operators exist and work at the `RolledDie` level (boolean flags `success`, `failure`, `critSuccess`, `critFailure`). Per-group scoring requires groups (D6) which don't exist yet.

### D9: Named Die Type Registry

**Decision:** Static registry on `DiceExpression` for custom face sets.

**NOT_DONE.** No `registerDieType()` method. Grammar does not support `NdNAME` syntax.

---

## 6. Target Architecture (Section 6)

### 6.1-6.2 Architecture & Data Flow Diagrams

**PARTIALLY_DONE.** The target describes:

| Target Component | Status |
|---|---|
| PetitParser grammar with labels, tags, named types | Labels/tags/named types: **NOT_DONE**. All other grammar features: **DONE** |
| `DiceRoller` interface (abstract) | **DONE** (different shape than spec) |
| `DefaultDiceRoller` | **DONE** as `RNGRoller` |
| Client roller implementations slot | **DONE** (`PreRolledDiceRoller`, `CallbackDiceRoller` exist) |
| Async AST evaluation | **DONE** |
| Wrap ints -> RolledDie | **DONE** (in `DiceResultRoller`) |
| `RollOutcome` type with groups, reroll() | **NOT_DONE** (current return type is `RollSummary`) |
| `GroupResult` type | **NOT_DONE** |

### 6.3 Target Type System

| Target Type | Status | Notes |
|---|---|---|
| `DiceExpression` | **PARTIALLY_DONE** | `create()` and `roll()` exist. No `registerDieType()`. Returns `RollSummary` not `RollOutcome`. |
| `DiceRoller` (interface) | **DONE** (different shape) | `Stream<int>` methods, not `Future<List<int>>` |
| `DefaultDiceRoller` | **DONE** as `RNGRoller` | |
| `RolledDie` | **PARTIALLY_DONE** | Has `result`, `nsides`, `dieType`, `exploded`, `explosion`, `critSuccess`, `critFailure`, `discarded`. Missing: `groupLabel`, `locked`, `tags`. Has extras not in spec: `compounded`, `compoundedFinal`, `penetrated`, `penetrator`, `reroll`, `rerolled`, `clampCeiling`, `clampFloor`, `totaled`, `success`, `failure`, `from`, `potentialValues`. |
| `RollOutcome` | **NOT_DONE** | Does not exist. `RollSummary` is the closest equivalent. |
| `GroupResult` | **NOT_DONE** | Does not exist. |
| `DieType` enum | **PARTIALLY_DONE** | Has: `polyhedral`, `fudge`, `d66`, `nvals`, `singleVal`. Spec wants: `polyhedral`, `fudge`, `custom`, `percentile`, `d66`. Fork has `nvals` where spec says `custom`. Fork has `singleVal` (not in spec). Fork lacks `percentile` (percentile dice use `polyhedral` with nsides=100). |

---

## 7. Implementation Phases (Section 7)

### Phase 1: Merge PR #6

**ALREADY_DONE.** Every item in Phase 1 is present in the fork:

- `RollResult.results` is `IList<RolledDie>` (not `List<int>`)
- `RolledDie` carries `result`, `nsides`, `dieType`, all boolean flags
- `RollResult` splits active results from discarded
- `RollSummary` has `critSuccessCount`, `critFailureCount`
- Sorting (`s`, `sd`), comma-separated sub-expressions, penetrating dice: all in grammar
- AST refactored into `ast_core.dart`, `ast_ops.dart`, `ast_dice.dart`
- `DieType` enum exists (with slightly different values than spec lists)

**There is nothing to do for Phase 1.**

### Phase 2: Async + Pluggable DiceRoller

**ALREADY_DONE** with caveats:

| Phase 2 Item | Status |
|---|---|
| `DiceRoller` abstract class | **DONE** |
| `DefaultDiceRoller` wrapping `Random` | **DONE** as `RNGRoller` |
| All AST `evaluate()` async | **DONE** |
| `DiceExpression.create()` accepts `DiceRoller?` | **DONE** |
| `create()` still accepts `Random` for ergonomics | **NOT_DONE** -- only accepts `DiceRoller?` |
| `roll()` returns `Future<RollOutcome>` | **PARTIALLY_DONE** -- returns `Future<RollSummary>` (no rename) |
| Per-roll `onRoll` callback | **DONE** |
| Static listeners deprecated | **NOT_DONE** -- still active, no deprecation annotations |

**Remaining Phase 2 work:**
1. Optionally add `Random?` convenience parameter to `create()` (or decide this is unnecessary given `RNGRoller` exists)
2. Optionally rename `RollSummary` -> `RollOutcome` (breaking change -- weigh whether it's worth it)
3. Deprecate static listeners
4. Fix `simultaneousRolls` / `Future.wait` for parallel evaluation (if desired)

### Phase 3: Groups, Labels, Tags

**NOT_DONE.** All items are still needed:

1. Grammar extension for `"Label:" <expr>` syntax
2. Grammar extension for `@key=value` tag syntax
3. `groupLabel: String?` and `tags: Map<String, String>?` fields on `RolledDie`
4. `groups: Map<String, GroupResult>?` on result type
5. `GroupResult` class

**Important prerequisite issue:** The current `CommaOp` collapses sub-expression results into single-value totals. This needs reworking to preserve individual die results within groups.

### Phase 4: Push / Re-roll

**NOT_DONE.** All items are still needed:

1. `locked: bool` field on `RolledDie`
2. `reroll()` method on result type
3. Multi-push support
4. Group structure preservation across re-rolls

---

## 8. Call-Site & Testing Impact (Section 8)

### 8.1 Mythic GME App Integration Points

| Spec Claim | Verdict | Notes |
|---|---|---|
| `diceRandomProvider` returns `Random?` | **UNVERIFIABLE** | This is in the client app, not in the parser package |
| `DiceExpression.create(expr, random)` with positional `Random?` | **INCORRECT** | `create(String input, {DiceRoller? roller})` -- named `DiceRoller?` parameter |
| `expression.roll()` is sync | **INCORRECT** | Already async (`Future<RollSummary>`) |
| Phase 1: result type gains `RolledDie` objects | **ALREADY_DONE** | |
| Phase 2: `roll()` returns `Future<RollOutcome>`, add `await` | **PARTIALLY_DONE** | Already returns `Future<RollSummary>`. `await` is already required. |

### 8.2 Test Evolution

The spec's "BEFORE" code examples show synchronous `List<int>` results. **INCORRECT** for the fork. The fork's tests should already be async and use `RolledDie`. The spec's "AFTER Phase 1" and "AFTER Phase 2" examples are closer to the fork's current reality.

**CONFIRMED:** The test pattern in "AFTER Phase 2" with `await expr.roll()` and `result.results.map((d) => d.result)` matches the fork's current behavior.

---

## Bugs Found

### BUG: `clearSummaryListeners()` clears wrong list

**File:** `/home/user/mythic-dice-parser/lib/src/dice_expression.dart`, lines 31-33

```dart
static void clearSummaryListeners() {
    listeners.clear(); // BUG: should be summaryListeners.clear()
}
```

**CONFIRMED.** `clearSummaryListeners()` clears `listeners` (the `RollResult` listener list) instead of `summaryListeners`. This is a copy-paste bug.

### Dead Code: `ast.dart` and `results.dart`

**File:** `/home/user/mythic-dice-parser/lib/src/ast.dart`
**File:** `/home/user/mythic-dice-parser/lib/src/results.dart`

**CONFIRMED.** These files contain the old synchronous, `List<int>`-based implementation:
- `ast.dart` has synchronous `RollResult call()` (not `Future`), uses old `DiceRoller` (not `DiceResultRoller`), uses `List<int>` results, references `RollMetadata`/`RollScore` from `results.dart`
- `results.dart` has `RollResult` with `List<int> results`, `RollMetadata`, `RollScore`, `RollSummary` with `List<int> results` and `RollMetadata`

Neither file is imported by any active code:
- `ast.dart` is not imported anywhere
- `results.dart` is only imported by `ast.dart`

These files should be deleted. They are the pre-PR-#6 implementation left behind after the refactor.

### Not exported: `ast.dart` and `results.dart` types

The library barrel file (`dart_dice_parser.dart`) correctly does NOT export these dead files. It exports the active implementations.

---

## Summary of Interface Shape Mismatch

The most significant architectural discrepancy between the spec and the fork:

| Aspect | Spec Proposes | Fork Has |
|---|---|---|
| Roller return type | `Future<List<int>>` | `Stream<int>` |
| Roller method names | `roll()`, `rollCustomFaces()` | `roll()`, `rollVals<T>()` |
| Roller params | `ndice`, `nsides`, `min` | `ndice`, `nsides`, `min`, `dieType` |
| Roller wrapping | Engine wraps ints -> RolledDie | `DiceResultRoller` wraps -> `Future<RollResult>` with `RolledDie` |
| Public result type | `RollOutcome` (new) | `RollSummary` (existing) |
| Result grouping | `groups: Map<String, GroupResult>?` | Not present |
| Die lock/push | `locked: bool`, `reroll()` | Not present |

**The fork's two-layer design (`DiceRoller` -> `DiceResultRoller`) is architecturally sound and more capable than the spec's single-layer proposal.** The spec's `Future<List<int>>` return type is simpler for implementors of custom rollers, but the fork's approach passes `DieType` to the roller (useful for 3D dice animation). This is a deliberate design choice, not a deficiency.

---

## FINALIZED_SPEC: What Actually Needs to Be Done

Given the fork's current state, here is the corrected scope of remaining work:

### Immediate Fixes (No Phase -- Do Now)

1. **Fix `clearSummaryListeners()` bug** in `dice_expression.dart`: change `listeners.clear()` to `summaryListeners.clear()`.

2. **Delete dead code files:** Remove `lib/src/ast.dart` and `lib/src/results.dart`. They contain the old synchronous `List<int>` implementation and are not imported by any active code.

### Phase 1: SKIP -- Already Done

All PR #6 work is absorbed. `RolledDie`, `DieType`, split AST, async conversion, comma support, sort, penetrating dice, aggregate `{}` -- all present.

### Phase 2: SKIP (Mostly) -- Already Done

The async conversion and pluggable roller are complete. Remaining optional cleanup:

1. **Optional:** Add `Random?` convenience parameter to `DiceExpression.create()` that wraps in `RNGRoller` internally (reduces friction for simple use cases).
2. **Optional:** Add `@Deprecated` annotations to static `registerListener()` and `registerSummaryListener()` methods.
3. **Optional:** Rename `RollSummary` -> `RollOutcome` if desired to signal the API evolution. This is cosmetic.
4. **Decision needed:** Whether to add `simultaneousRolls` / `Future.wait` for parallel binary op evaluation (PR #7 had this, fork does not).

### Phase 3: Groups, Labels, Tags -- NEEDED

This is genuinely new work. Scope:

1. **Grammar extension:** Add `"Label:" <expr>` parsing within comma-separated groups. Add `@key=value` tag syntax after sub-expressions.
2. **New fields on `RolledDie`:** `groupLabel: String?`, `tags: Map<String, String>?`
3. **New type:** `GroupResult` with label, results, discarded, total, scoring counts, tags.
4. **Extend result type:** Add `groups: Map<String, GroupResult>?` to `RollSummary` (or `RollOutcome` if renamed).
5. **Rework `CommaOp`:** Currently collapses sub-expression results into `singleVal` totals, losing individual die identity. Must preserve individual `RolledDie` objects within groups for this feature to work.
6. **Backward compatibility:** Expressions without labels must produce results with `groups == null`.

### Phase 4: Push / Re-roll -- NEEDED

This is genuinely new work. Scope:

1. **New field on `RolledDie`:** `locked: bool` (default `false`).
2. **New method on result type:** `reroll({required bool Function(RolledDie) lockWhere, required DiceRoller roller})` returning a new result.
3. **Preserve group structure** across re-rolls.
4. **Support multi-push** (calling reroll on the result of a previous reroll).

### Named Die Type Registry (D9) -- NEEDED (Phase 3+)

1. Add `DiceExpression.registerDieType(String name, List<int> faces)` static method.
2. Extend PetitParser grammar to resolve `NdNAME` where NAME is a registered identifier.
3. Resolve potential parsing ambiguity with existing `NdN` numeric patterns and special cases (`dF`, `d%`, `D66`).

### DiceRoller Interface Decision -- NEEDS RESOLUTION

The spec proposes `Future<List<int>>` but the fork has `Stream<int>`. Options:

1. **Keep `Stream<int>`** -- No code changes needed. Slightly more complex for custom roller implementors but functionally equivalent.
2. **Change to `Future<List<int>>`** -- Simpler interface for custom rollers. Would require updating `RNGRoller`, `PreRolledDiceRoller`, `CallbackDiceRoller`, and all call sites in `DiceResultRoller`. The `DieType` parameter should be kept regardless (the spec missed this but it's useful).

**Recommendation:** Keep `Stream<int>` for now. It works. The migration cost is real and the benefit is marginal. If custom roller implementors complain about streams, change it then.
