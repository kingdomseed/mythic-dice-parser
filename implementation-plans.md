# Implementation Plans

**Date:** 2026-03-15
**Status:** Concrete, file-level plans for all remaining work
**Governing docs:** `draft spec.md` (spec), `spec-validation-report.md` (validated state)

### Decisions Recorded

- **Phases 1 & 2:** SKIP — already absorbed from upstream PRs. No optional Phase 2 cleanups (Random? convenience param, @Deprecated on static listeners, simultaneousRolls) are included in this plan. They can be revisited if needed.
- **`RollSummary` naming:** Keep as `RollSummary`. The spec uses `RollOutcome` but this is cosmetic. Renaming adds churn with no functional benefit. The `reroll()` method goes on `RollSummary` to match the existing codebase convention.
- **DiceRoller interface:** Keep `Stream<int>`. No change from current fork.

---

## Phase 0: Immediate Fixes (Do Now)

These are bugs and dead code discovered during validation. Zero design ambiguity.

### 0A: Fix `clearSummaryListeners()` bug

**File changed:** `lib/src/dice_expression.dart`

**What:** Line 32 reads `listeners.clear();` inside `clearSummaryListeners()`. This is a copy-paste bug. It should be `summaryListeners.clear();`.

**Exact diff:**
```dart
// BEFORE (line 31-33):
static void clearSummaryListeners() {
    listeners.clear();
}

// AFTER:
static void clearSummaryListeners() {
    summaryListeners.clear();
}
```

**Why:** `clearSummaryListeners()` currently destroys the `RollResult` listener list (including the `defaultListener` that logs results) instead of clearing the `RollSummary` listener list. Any code calling `clearSummaryListeners()` silently breaks `RollResult` listening.

**Test plan:**
- New test: register a summary listener, call `clearSummaryListeners()`, verify summary listener list is empty and `listeners` list is unchanged.
- New test: register a regular listener, call `clearSummaryListeners()`, verify regular listener is still present.

**Risks:** None. Surgical one-word fix.

### 0B: Delete dead code files

**Files removed:**
- `lib/src/ast.dart` — Old synchronous AST with `List<int>` results. Not imported by any active code.
- `lib/src/results.dart` — Old `RollResult`/`RollSummary`/`RollMetadata`/`RollScore` with `List<int>`. Only imported by `ast.dart`.

**Why:** These are the pre-PR-#6 implementation. They are completely superseded by `ast_core.dart`, `ast_ops.dart`, `ast_dice.dart`, `roll_result.dart`, `roll_summary.dart`, and `rolled_die.dart`. Neither file is exported from `lib/dart_dice_parser.dart` or imported by any active source file.

**Test plan:** Run full test suite after deletion. All tests should pass unchanged because no active code references these files.

**Risks:** None. Confirmed no imports via grep.

---

## Phase 3: Groups, Labels, Tags (NEW WORK)

This is the first phase of genuinely new feature work. It enables Year Zero Engine colored pools, labeled dice groups, and tag-based metadata passthrough.

### 3.1 Overview of Changes

The comma operator currently collapses each sub-expression into a `RolledDie.singleVal(result: sum, totaled: true)`, discarding individual die identity. For groups/labels to work, we need:

1. Grammar rules for `"Label:" <expr>` and `@key=value` tags
2. New AST node types to carry label/tag metadata
3. Reworked `CommaOp` to preserve individual die identity within groups
4. New fields on `RolledDie`: `groupLabel`, `tags`
5. New type `GroupResult` to collect per-group scoring
6. Extended `RollSummary` with a `groups` field

### 3.2 File Changes

#### 3.2.1 `lib/src/parser.dart` — Grammar extension

**What changes:** Add label and tag parsing rules to the PetitParser grammar.

**Grammar additions (concrete PetitParser rules):**

```dart
// Label: a quoted string followed by colon, before a sub-expression.
// Parses: "Attack:" or 'Attack:'
final labelParser = (char('"') & pattern('^"').star().flatten() & char('"') & char(':').trim())
    .map4((q1, label, q2, colon) => label);

// Tag: @key=value after a sub-expression. Value is alphanumeric (no spaces).
// Parses: @color=red
final tagParser = (char('@') & letter().plus().flatten() & char('=') & pattern('^ ,)').plus().flatten())
    .map4((at, key, eq, value) => MapEntry(key, value));

// Multiple tags
final tagsParser = tagParser.star();
```

**Where in the grammar:** The comma operator is currently defined at line 137:
```dart
..left(char(',').trim(), (a, op, b) => CommaOp(op, a, b));
```

The label and tag parsing must integrate with the comma-separated group structure. The approach:

1. Add a new group at the same precedence level as (or just below) the comma operator.
2. A "labeled expression" is: `labelParser.optional() & <existing-expr> & tagsParser`
3. The comma operator then combines labeled expressions.

**Concrete change to `parserBuilder`:**

Replace the comma line with a new group that handles labels, tags, and commas together. The key insight is that labels and tags wrap around sub-expressions at the comma-separated level:

```dart
// Replace the existing comma left-operator in the final builder.group() with:
builder.group()
  ..left(
    (char('#') & char('c').optional() & pattern('sf').optional() &
            pattern('<>').optional() & char('=').optional())
        .flatten().trim(),
    (a, op, b) => CountOp(op.toLowerCase(), a, b),
  )
  ..postfix(
    (char('s') & char('d').optional()).flatten().trim(),
    (a, op) => SortOp(op.toLowerCase(), a),
  );

// New group for labels, tags, and comma
builder.group()
  ..prefix(
    (char('"') & pattern('^"').star().flatten() & string('":').trim())
        .map((v) => v.$2),
    (label, a) => LabelOp(label, a),
  )
  ..postfix(
    (char('@') & letter().plus().flatten() & char('=') &
            pattern('^ ,)').plus().flatten())
        .plus().trim(),
    (a, tags) => TagOp(
      a,
      Map.fromEntries(tags.map((t) => MapEntry(t.$2, t.$4))),
    ),
  )
  ..left(char(',').trim(), (a, op, b) => CommaOp(op, a, b));
```

**IMPORTANT DESIGN NOTE:** The label prefix and tag postfix must be at the same precedence level as the comma operator or lower, so that `"Attack:" 2d6! @color=red, "Damage:" 1d8` parses as two comma-separated groups where the first group has a label and a tag.

**PRECEDENCE CHANGE ANALYSIS:** The current code has count, sort, and comma all in the SAME `builder.group()` (parser.dart lines 122-137). The proposed change splits them into two groups: count/sort in one, then labels/tags/comma in a new lower-precedence group. This makes comma lower precedence than count/sort. **Impact on existing expressions:** `(1d4,1d4p,1d4!,1d4!!)#s>=4` — currently comma and count are at the same level. With the split, the scoring `#s>=4` would bind tighter than comma, so each sub-expression gets scored individually before being comma-joined. This is actually the **desired behavior** for groups (each group should have its own scoring). Verify with tests that existing comma+scoring expressions produce the same results or document the intentional behavioral change.

**Parsing ambiguity analysis:**
- `"` does not conflict with any existing token (the grammar has no string literals).
- `@` does not conflict with any existing token.
- The label must use `"..."` quotes (not bare words) to avoid collision with dice identifiers like `dF`, `D66`, or future named die types.

#### 3.2.2 `lib/src/ast_core.dart` — New AST nodes and reworked CommaOp

**New classes added:**

```dart
/// Wraps a sub-expression with a label.
/// In the expression `"Attack:" 2d6!`, the label is "Attack" and the
/// sub-expression is `2d6!`.
class LabelOp extends Unary {
  LabelOp(this.label, DiceExpression child) : super('label', child);

  final String label;

  @override
  String toString() => '"$label:" $left';

  @override
  Future<RollResult> eval() async {
    final result = await left();
    // Stamp groupLabel onto all results
    return RollResult.fromRollResult(
      result,
      expression: toString(),
      opType: result.opType,
      results: result.results.map(
        (d) => RolledDie.copyWith(d, groupLabel: label),
      ),
      discarded: result.discarded,
    );
  }
}

/// Wraps a sub-expression with tags (key-value metadata).
/// In the expression `2d6 @color=red`, the tag is {color: red}.
/// Tags are stored on the RollResult node, NOT on individual RolledDie objects.
/// GroupResult picks them up when building groups from the result tree.
class TagOp extends Unary {
  TagOp(DiceExpression child, this.tags) : super('tag', child);

  final Map<String, String> tags;

  @override
  String toString() {
    final tagStr = tags.entries.map((e) => '@${e.key}=${e.value}').join(' ');
    return '$left $tagStr';
  }

  @override
  Future<RollResult> eval() async {
    final result = await left();
    // Store tags on the RollResult node (not individual dice).
    // GroupResult will pick these up from the result tree.
    return RollResult.fromRollResult(
      result,
      expression: toString(),
      opType: result.opType,
      tags: tags, // NEW: optional tags field on RollResult
    );
  }
}

// NOTE: RollResult needs a new optional `tags` field:
//   final Map<String, String>? tags;
// Added to constructor, fromRollResult factory, and props.
// This is a lightweight addition — RollResult already carries metadata.
```

**Reworked `CommaOp` — Conditional behavior:**

The current `CommaOp` (lines 48-96) collapses sub-expressions into `singleVal` totals. For groups/labels to work, we need to preserve individual `RolledDie` objects. However, unconditionally changing this breaks existing semantics for expressions like `(2d6,3d8)kh`.

**Decision: Conditional behavior based on whether labels are present.** If any child result contains dice with `groupLabel != null`, preserve individual die identity. If no labels are present, preserve the existing totalization behavior. This is zero-breakage for unlabeled expressions.

```dart
class CommaOp extends Binary {
  CommaOp(super.name, super.left, super.right);

  @override
  Future<RollResult> eval() async {
    final lhs = await left();
    final rhs = await right();

    // Check if any child has labeled dice (from LabelOp)
    final hasLabels = lhs.results.any((d) => d.groupLabel != null) ||
        rhs.results.any((d) => d.groupLabel != null);

    if (hasLabels) {
      // Labeled mode: preserve individual die identity within groups.
      return _evalLabeled(lhs, rhs);
    } else {
      // Unlabeled mode: existing totalization behavior (backward compatible).
      return _evalTotalized(lhs, rhs);
    }
  }

  /// New behavior for labeled groups: pass through individual dice.
  Future<RollResult> _evalLabeled(RollResult lhs, RollResult rhs) async {
    return RollResult(
      expression: toString(),
      opType: OpType.comma,
      results: [...lhs.results, ...rhs.results],
      discarded: [...lhs.discarded, ...rhs.discarded],
      left: lhs,
      right: rhs,
    );
  }

  /// Existing behavior: collapse each sub-expression to a singleVal total.
  Future<RollResult> _evalTotalized(RollResult lhs, RollResult rhs) async {
    // ... (current implementation, unchanged)
  }
}
```

**Impact analysis for downstream operators with labeled commas:**
- `"A:" 2d6, "B:" 1d8` with `kh` → keeps highest individual die across all groups. This is the expected behavior when dice have group identity.
- `1d4,1d6,1d8,1d10` (no labels) with `kh` → unchanged, keeps highest total sub-expression.
- Existing test `'scored comma', '(1d4,1d4p,1d4!,1d4!!)#s>=4'` → unchanged (no labels).

**Tests to add for the conditional behavior:**
```dart
test('unlabeled comma preserves totalization', () async {
  // Same behavior as current: each sub-expr collapsed to total
  final expr = DiceExpression.create('(2d6,3d8)kh', roller: RNGRoller(Random(1234)));
  final result = await expr.roll();
  // Verify results are singleVal totals, not individual dice
  expect(result.results.every((d) => d.dieType == DieType.singleVal), isTrue);
});

test('labeled comma preserves individual dice', () async {
  final expr = DiceExpression.create('"A:" 2d6, "B:" 1d8', roller: RNGRoller(Random(1234)));
  final result = await expr.roll();
  // Individual dice preserved, not collapsed
  expect(result.results.length, 3); // 2 + 1
  expect(result.results.any((d) => d.dieType == DieType.polyhedral), isTrue);
});

test('mixed comma with heterogeneous dice and kh', () async {
  // Before: (2d6,3d8)kh keeps highest sub-expression total
  // After: same (no labels, backward compatible)
  final expr = DiceExpression.create('(2d6,3d8)kh', roller: RNGRoller(Random(1234)));
  final initial = await expr.roll();
  // Results should still be totals
  expect(initial.results.length, 1);
});
```

**Mitigation strategy:** Introduce the behavioral change, then update tests to match. The new behavior is strictly more useful (preserves die identity) and is required for labels/groups to work. Document the breaking change. The old "collapse to total" behavior can be recovered by wrapping sub-expressions in `{}` (the aggregate operator), e.g., `{2d6},{3d8}` produces totals.

#### 3.2.3 `lib/src/rolled_die.dart` — New fields

**Fields added to `RolledDie`:**

```dart
/// The group label this die belongs to (from "Label:" syntax).
/// null if no label was applied.
final String? groupLabel;
```

**NOTE (YAGNI decision):** Tags are NOT added to `RolledDie`. Tags are a group-level concept and belong only on `GroupResult`. Stamping tags on individual dice would require propagating them through every `copyWith` call in every AST operation (explode, compound, reroll, clamp, etc.) — excessive churn for a metadata passthrough. Instead, `TagOp` stores tags on the `RollResult` node (via a new optional field), and `GroupResult` picks them up when building groups from the result tree.

**Changes required:**

1. **Constructor:** Add `this.groupLabel` as optional named parameter.
2. **`copyWith` factory:** Add `String? groupLabel` parameter. Pass through: `groupLabel: groupLabel ?? other.groupLabel`.
3. **`props` getter:** Add `groupLabel` to the Equatable props list.
4. **`toJson()`:** Add `'groupLabel': groupLabel` entry (removed by `removeWhere` if null).
5. **`toString()`:** Optionally include group label in output for debugging.

**Exact constructor signature change:**
```dart
RolledDie({
  required this.result,
  required this.dieType,
  this.nsides = 0,
  Iterable<int> potentialValues = const IList.empty(),
  this.discarded = false,
  this.success = false,
  this.failure = false,
  this.critSuccess = false,
  this.critFailure = false,
  this.exploded = false,
  this.explosion = false,
  this.compoundedFinal = false,
  this.compounded = false,
  this.penetrated = false,
  this.penetrator = false,
  this.reroll = false,
  this.rerolled = false,
  this.clampCeiling = false,
  this.clampFloor = false,
  this.totaled = false,
  this.from = const IList.empty(),
  this.groupLabel,       // NEW
})
```

**NOTE: No `tags` field on `RolledDie`.** Per the YAGNI decision above, tags live on `RollResult.tags` only. The `groupLabel` field IS needed on `RolledDie` because it must survive through AST operations (keep/drop/explode) via `copyWith` propagation. Every existing `RolledDie.copyWith` call will automatically propagate `groupLabel` because the factory uses `groupLabel: groupLabel ?? other.groupLabel` — unknown fields default to the source die's value. Tags do not need per-die survival — they are harvested from the `RollResult` tree at `GroupResult` construction time via `_harvestTags()`.

**`copyWith` addition:**
```dart
factory RolledDie.copyWith(
  RolledDie other, {
  int? result,
  // ... existing params ...
  String? groupLabel,
}) => RolledDie(
  // ... existing fields ...
  groupLabel: groupLabel ?? other.groupLabel,
);
```

#### 3.2.4 `lib/src/group_result.dart` — NEW FILE

**Purpose:** Represents the result of a single labeled group within a comma-separated expression.

```dart
import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'extensions.dart';
import 'rolled_die.dart';

/// Result for a single labeled group within a comma-separated expression.
///
/// When the expression `"Attack:" 2d6!, "Damage:" 1d8` is rolled,
/// two [GroupResult]s are produced: one for "Attack" and one for "Damage".
class GroupResult extends Equatable {
  GroupResult({
    required this.label,
    required Iterable<RolledDie> results,
    required Iterable<RolledDie> discarded,
    this.tags,
  }) : results = IList(results),
       discarded = IList(discarded),
       total = IList(results).sum,
       successCount = IList(results).successCount,
       failureCount = IList(results).failureCount,
       critSuccessCount = IList(results).critSuccessCount,
       critFailureCount = IList(results).critFailureCount;

  /// The group's label (e.g., "Attack"). Empty string for anonymous groups.
  final String label;

  /// The active (non-discarded) results in this group.
  final IList<RolledDie> results;

  /// Dice discarded during evaluation of this group.
  final IList<RolledDie> discarded;

  /// Sum of results.
  final int total;

  final int successCount;
  final int failureCount;
  final int critSuccessCount;
  final int critFailureCount;

  /// Client-defined tags from @key=value syntax.
  final Map<String, String>? tags;

  @override
  List<Object?> get props => [
    label, results, discarded, total,
    successCount, failureCount, critSuccessCount, critFailureCount,
    tags,
  ];

  Map<String, dynamic> toJson() =>
      {
        'label': label,
        'total': total,
        'successCount': successCount,
        'failureCount': failureCount,
        'critSuccessCount': critSuccessCount,
        'critFailureCount': critFailureCount,
        'results': results.map((e) => e.toJson()).toList(growable: false),
        'discarded': discarded.map((e) => e.toJson()).toList(growable: false),
        'tags': tags,
      }..removeWhere(
        (k, v) =>
            v == null ||
            (v is Map && v.isEmpty) ||
            (v is Iterable && v.isEmpty) ||
            (v is int && v == 0) ||
            (v is bool && !v),
      );

  @override
  String toString() => 'GroupResult($label, total: $total, results: $results)';
}
```

#### 3.2.5 `lib/src/roll_summary.dart` — Add `groups` field

**What changes:** Add an optional `groups` field populated from the `detailedResults` tree when labels are present.

**New field:**
```dart
/// Per-group results, populated when the expression uses label syntax.
/// null when no labels/commas are used (plain expressions like "2d6+4").
final Map<String, GroupResult>? groups;
```

**Constructor change:** Add group-building logic that inspects the `detailedResults`:

```dart
RollSummary({required this.detailedResults})
  : total = detailedResults.results.sum,
    results = IList(detailedResults.results),
    discarded = IList(detailedResults.discarded),
    expression = detailedResults.expression,
    successCount = detailedResults.results.successCount,
    failureCount = detailedResults.results.failureCount,
    critSuccessCount = detailedResults.results.critSuccessCount,
    critFailureCount = detailedResults.results.critFailureCount,
    groups = _buildGroups(detailedResults);

static Map<String, GroupResult>? _buildGroups(RollResult detailedResults) {
  // Only build groups when the expression used labels.
  final hasLabels = detailedResults.results.any((d) => d.groupLabel != null);
  if (!hasLabels) return null;

  // Group results by their groupLabel
  final grouped = <String, List<RolledDie>>{};
  final groupedDiscarded = <String, List<RolledDie>>{};

  for (final die in detailedResults.results) {
    final label = die.groupLabel ?? '';
    grouped.putIfAbsent(label, () => []).add(die);
  }
  for (final die in detailedResults.discarded) {
    final label = die.groupLabel ?? '';
    groupedDiscarded.putIfAbsent(label, () => []).add(die);
  }

  // Harvest tags from the RollResult tree (set by TagOp on RollResult nodes).
  // Walk the tree to find nodes with non-null tags and associate them with
  // the correct group label by checking the groupLabel on their results.
  final groupTags = <String, Map<String, String>>{};
  _harvestTags(detailedResults, groupTags);

  return {
    for (final label in grouped.keys)
      label: GroupResult(
        label: label,
        results: grouped[label]!,
        discarded: groupedDiscarded[label] ?? [],
        tags: groupTags[label],
      ),
  };
}

/// Walk the RollResult tree to find TagOp-produced nodes with tags.
/// Associate tags with group labels by inspecting the results of
/// each tagged node.
static void _harvestTags(
  RollResult node,
  Map<String, Map<String, String>> groupTags,
) {
  if (node.tags != null && node.tags!.isNotEmpty) {
    // Find the group label from this node's results
    final label = node.results
        .map((d) => d.groupLabel)
        .firstWhere((l) => l != null, orElse: () => null) ?? '';
    groupTags.putIfAbsent(label, () => {}).addAll(node.tags!);
  }
  if (node.left != null) _harvestTags(node.left!, groupTags);
  if (node.right != null) _harvestTags(node.right!, groupTags);
}
```

**`props` update:** Add `groups` to the Equatable props list.

**`toJson()` update:** Add `'groups': groups?.map((k, v) => MapEntry(k, v.toJson()))`.

**`toString()` update:** If `groups != null`, append group summaries.

#### 3.2.6 `lib/dart_dice_parser.dart` — Export new file

**What changes:** Add export for new `group_result.dart`:

```dart
export 'src/group_result.dart';
```

### 3.3 Test Plan

#### Tests that will BREAK (due to CommaOp rework):

The following tests rely on the current `CommaOp` behavior of collapsing sub-expressions to `singleVal` totals:

1. **`'sorted comma', '(1d4,1d6,1d8,1d10) s'`** — expects `expectedResults: [2, 4, 5, 9]`. With the change, results will be the raw die values, not totals. Since each sub-expression is a single die, the values should be identical. **Likely still passes.**

2. **`'unsorted comma', '(1d4,1d6,1d8,1d10)'`** — expects `expectedResults: [4, 2, 5, 9]`. Same reasoning as above. **Likely still passes** because each sub-expression is a single die.

3. **`'scored comma', '(1d4,1d4p,1d4!,1d4!!)#s>=4'`** — expects `expectedResults: [4, 4, 3, 3]`. These are the totals of each sub-expression. With the change, penetrating/exploding sub-expressions may produce multiple dice. The penetrating `1d4p` and exploding `1d4!` and compounding `1d4!!` could produce different raw result lists. **Will likely break.** Need to verify with seeded random and update expected values.

#### New tests needed:

1. **Labeled expression basic parsing:**
   ```dart
   test('labeled dice groups', () async {
     final expr = DiceExpression.create(
       '"Attack:" 2d6, "Damage:" 1d8',
       roller: RNGRoller(Random(1234)),
     );
     final result = await expr.roll();
     expect(result.groups, isNotNull);
     expect(result.groups!.keys, containsAll(['Attack', 'Damage']));
     expect(result.groups!['Attack']!.results.length, 2);
     expect(result.groups!['Attack']!.results.every((d) => d.nsides == 6), isTrue);
     expect(result.groups!['Damage']!.results.length, 1);
     expect(result.groups!['Damage']!.results.every((d) => d.nsides == 8), isTrue);
   });
   ```

2. **Tags passthrough:**
   ```dart
   test('tags pass through to results', () async {
     final expr = DiceExpression.create(
       '"Skill:" 3d6 @color=white, "Gear:" 2d6 @color=black',
       roller: RNGRoller(Random(1234)),
     );
     final result = await expr.roll();
     expect(result.groups!['Skill']!.tags, equals({'color': 'white'}));
     expect(result.groups!['Gear']!.tags, equals({'color': 'black'}));
   });
   ```

3. **No labels produces null groups:**
   ```dart
   test('plain expression has null groups', () async {
     final expr = DiceExpression.create('2d6+4', roller: RNGRoller(Random(1234)));
     final result = await expr.roll();
     expect(result.groups, isNull);
   });
   ```

4. **Per-group scoring:**
   ```dart
   test('per-group scoring', () async {
     final expr = DiceExpression.create(
       '"Skill:" 3d6 #s>=5, "Gear:" 2d6 #s>=5',
       roller: RNGRoller(Random(1234)),
     );
     final result = await expr.roll();
     expect(result.groups!['Skill']!.successCount, isNonNegative);
     expect(result.groups!['Gear']!.successCount, isNonNegative);
   });
   ```

5. **Anonymous comma (no labels) preserves totalization:**
   ```dart
   test('unlabeled comma preserves totalization behavior', () async {
     final expr = DiceExpression.create('2d6, 1d8', roller: RNGRoller(Random(1234)));
     final result = await expr.roll();
     // No labels → conditional CommaOp uses _evalTotalized → 2 singleVal totals
     expect(result.results.length, 2);
     expect(result.results.every((d) => d.dieType == DieType.singleVal), isTrue);
     // groups is null because no labels
     expect(result.groups, isNull);
   });
   ```

6. **Labels with modifiers (explode, score, etc):**
   ```dart
   test('labeled with exploding', () async {
     final expr = DiceExpression.create(
       '"Attack:" 2d6!',
       roller: RNGRoller(Random(1234)),
     );
     final result = await expr.roll();
     expect(result.groups, isNotNull);
     expect(result.groups!['Attack']!.results, isNotEmpty);
   });
   ```

7. **Edge case: single labeled group (no comma):**
   ```dart
   test('single labeled group', () async {
     final expr = DiceExpression.create(
       '"Strength:" 4d6kh3',
       roller: RNGRoller(Random(1234)),
     );
     final result = await expr.roll();
     expect(result.groups, isNotNull);
     expect(result.groups!['Strength']!.results.length, 3);
   });
   ```

### 3.4 Risks & Open Items

1. **CommaOp behavioral change is BREAKING.** The current behavior of totalizing sub-expressions is used by existing tests and potentially by the Mythic GME client app. The migration path: `{expr}` (curly braces / `AggregateOp`) already produces a totalized single value. Document that `(2d6,3d8)` now preserves all 5 individual dice, and `{2d6},{3d8}` gives the old behavior of 2 totals.

2. **PetitParser precedence.** Labels and tags at comma-level precedence may interact unexpectedly with scoring operators (`#s`, `#f`). The scoring operators are in the same builder group as the comma. Need to verify that `"Skill:" 3d6 #s>=5, "Gear:" 2d6 #s>=5` parses as two comma-separated groups where each group has scoring applied before the comma joins them. This should work because scoring is `left` (binary) and comma is also `left`, so they're evaluated left-to-right. But `"` as a prefix at the same level as `#` needs careful testing.

3. **Quote character choice.** Using `"` for labels means the expression string itself needs careful escaping if passed from JSON or Dart string literals. Single quotes could be an alternative. **Decision: support both `"` and `'` as label delimiters** by using `pattern("\"'")` in the grammar.

4. **Empty labels.** What does `":" 2d6` mean? A label with an empty string. This is valid but weird. The grammar will allow it. Document that labels should be non-empty.

5. **Group label propagation through discarded dice.** When a labeled die is discarded (e.g., by `kh`), should the discarded copy retain its `groupLabel`? **Yes** -- the `RolledDie.discard()` factory calls `copyWith` which will propagate `groupLabel` automatically.

6. **Tag value limitations.** The grammar `pattern('^ ,)')` for tag values means values cannot contain spaces, commas, or closing parens. This is intentional -- tags are simple metadata, not rich strings. Document this limitation.

---

## Phase 4: Push / Re-roll Mechanic (NEW WORK)

### 4.1 Overview

The push mechanic (Year Zero Engine) allows the user to lock certain dice and re-roll the rest. This is a method on the result object, not a grammar feature. The user calls `reroll()` with a predicate that determines which dice to lock, and a roller to re-roll the unlocked dice.

### 4.2 File Changes

#### 4.2.1 `lib/src/rolled_die.dart` — Add `locked` field

**New field:**
```dart
/// Whether this die is locked (will not be re-rolled during a push).
/// Defaults to false. Set to true by RollSummary.reroll() for dice
/// matching the lock predicate.
final bool locked;
```

**Constructor change:** Add `this.locked = false` as optional named parameter.

**`copyWith` change:** Add `bool? locked` parameter, pass through: `locked: locked ?? other.locked`.

**`props` change:** Add `locked` to props list.

**`toJson()` change:** Add `'locked': locked`.

**`getDieStateGlyphs()` change:** Add lock glyph:
```dart
if (locked) {
  buffer.write('\u{1F512}'); // lock emoji, or use a simpler char
}
```

**`compareTo()` change:** Add `.if0(locked.compareTo(other.locked))`.

#### 4.2.2 `lib/src/push.dart` — New file for push/reroll functionality

**Architecture decision:** `reroll()` is a standalone top-level function in a new file, NOT a method on `RollSummary`. This preserves `RollSummary` as a pure data class (matching Steve's pattern where it is purely declarative). The push function lives in a separate file that depends on both the result layer and the roller layer, avoiding a dependency cycle.

**New file: `lib/src/push.dart`**

```dart
import 'dice_roller.dart';
import 'enums.dart';
import 'roll_result.dart';
import 'roll_summary.dart';
import 'rolled_die.dart';

/// Re-roll unlocked dice from a previous [RollSummary].
///
/// [lockWhere] determines which dice to lock (true = lock, false = re-roll).
/// Locked dice appear in the new result unchanged, with `locked: true`.
/// Unlocked dice are re-rolled using [roller].
/// `singleVal` and `totaled` dice are auto-locked (constants like +3).
///
/// Can be called multiple times on successive results (multi-push).
///
/// Returns a new [RollSummary] — does NOT mutate the original.
Future<RollSummary> reroll(
  RollSummary summary, {
  required bool Function(RolledDie) lockWhere,
  required DiceRoller roller,
}) async {
  final diceResultRoller = DiceResultRoller(roller);
  final newResults = <RolledDie>[];
  final newDiscarded = <RolledDie>[...summary.discarded];

  for (final die in summary.results) {
    // Auto-lock singleVal/totaled dice -- these are constants (e.g., +3)
    // that should never be re-rolled. Also respect already-locked dice
    // and the caller's lock predicate.
    final shouldLock = die.locked ||
        die.dieType == DieType.singleVal ||
        die.totaled ||
        lockWhere(die);
    if (shouldLock) {
      newResults.add(RolledDie.copyWith(die, locked: true));
    } else {
      newDiscarded.add(RolledDie.copyWith(die, discarded: true));
      final rerolled = await diceResultRoller.reroll(die);
      newResults.addAll(rerolled.results);
    }
  }

  final newRollResult = RollResult(
    expression: '${summary.expression} (push)',
    opType: OpType.reroll,
    results: newResults,
    discarded: newDiscarded,
  );

  return RollSummary(detailedResults: newRollResult);
}
```

**Export:** Add `export 'src/push.dart';` to `lib/dart_dice_parser.dart`.

**DESIGN NOTE:** `DiceResultRoller.reroll(RolledDie)` already knows how to re-roll based on `DieType` (polyhedral, fudge, d66, nvals). Each die is re-rolled with the correct die type and number of sides, preserving its identity.

**Group preservation:** Locked and re-rolled dice retain their `groupLabel` through `copyWith`. The new `RollSummary` constructor will rebuild the `groups` map from the new result set. Group structure is automatically preserved across pushes.

**Known limitation — scoring not re-applied:** Re-rolled dice come from `DiceResultRoller.reroll()` which produces plain dice without scoring flags. For YZE, the client must re-apply scoring logic post-push. This is documented as a Phase 4 limitation with a concrete follow-up: consider an optional scoring predicate parameter on `reroll()` in a future iteration.

#### 4.2.3 `lib/src/enums.dart` — No changes needed

The existing `OpType.reroll` value is already present and can be reused for the push result's opType.

### 4.3 Test Plan

#### New tests needed:

1. **Basic push:**
   ```dart
   test('push locks matching dice and re-rolls others', () async {
     final expr = DiceExpression.create('5d6', roller: RNGRoller(Random(1234)));
     final initial = await expr.roll();

     final pushed = await reroll(initial,
       lockWhere: (die) => die.result == 6 || die.result == 1,
       roller: RNGRoller(Random(9999)),
     );

     // Same number of results
     expect(pushed.results.length, initial.results.length);

     // Locked dice are unchanged
     for (final d in pushed.results.where((d) => d.locked)) {
       expect(d.result == 6 || d.result == 1, isTrue);
     }
   });
   ```

2. **Multi-push (push the result of a push):**
   ```dart
   test('multi-push preserves previously locked dice', () async {
     final expr = DiceExpression.create('5d6', roller: RNGRoller(Random(1234)));
     final initial = await expr.roll();

     final push1 = await reroll(initial,
       lockWhere: (die) => die.result == 6,
       roller: RNGRoller(Random(42)),
     );

     final push2 = await reroll(push1,
       lockWhere: (die) => die.result == 1,
       roller: RNGRoller(Random(99)),
     );

     // Dice locked in push1 remain locked in push2
     final lockedFromPush1 = push2.results.where((d) => d.locked && d.result == 6);
     expect(lockedFromPush1, isNotEmpty);
   });
   ```

3. **Push preserves group structure:**
   ```dart
   test('push preserves group labels', () async {
     final expr = DiceExpression.create(
       '"Skill:" 3d6, "Gear:" 2d6',
       roller: RNGRoller(Random(1234)),
     );
     final initial = await expr.roll();

     final pushed = await reroll(initial,
       lockWhere: (die) => die.result >= 5,
       roller: RNGRoller(Random(42)),
     );

     expect(pushed.groups, isNotNull);
     expect(pushed.groups!.keys, containsAll(['Skill', 'Gear']));
   });
   ```

4. **Push with custom roller:**
   ```dart
   test('push uses provided roller', () async {
     final expr = DiceExpression.create('3d6', roller: PreRolledDiceRoller([1, 2, 3]));
     final initial = await expr.roll();

     // All dice are not 6, so none locked by this predicate
     final pushed = await reroll(initial,
       lockWhere: (die) => die.result == 6,
       roller: PreRolledDiceRoller([4, 5, 6]),
     );

     expect(pushed.results.map((d) => d.result), unorderedEquals([4, 5, 6]));
   });
   ```

5. **Push with all locked (no re-rolls):**
   ```dart
   test('push with all dice locked returns identical result', () async {
     final expr = DiceExpression.create('3d6', roller: RNGRoller(Random(1234)));
     final initial = await expr.roll();

     final pushed = await reroll(initial,
       lockWhere: (die) => true, // lock everything
       roller: RNGRoller(Random(42)),
     );

     expect(
       pushed.results.map((d) => d.result),
       equals(initial.results.map((d) => d.result)),
     );
     expect(pushed.results.every((d) => d.locked), isTrue);
   });
   ```

6. **Push with none locked (re-roll everything):**
   ```dart
   test('push with no dice locked re-rolls all', () async {
     final expr = DiceExpression.create('3d6', roller: RNGRoller(Random(1234)));
     final initial = await expr.roll();

     final pushed = await reroll(initial,
       lockWhere: (die) => false, // lock nothing
       roller: RNGRoller(Random(42)),
     );

     expect(pushed.results.length, initial.results.length);
     expect(pushed.results.every((d) => !d.locked), isTrue);
   });
   ```

7. **Push on singleVal/totaled dice:**
   ```dart
   test('push on totaled dice preserves them', () async {
     // singleVal dice (from arithmetic) should be handled gracefully
     final expr = DiceExpression.create('2d6+3', roller: RNGRoller(Random(1234)));
     final initial = await expr.roll();

     final pushed = await reroll(initial,
       lockWhere: (die) => die.dieType == DieType.singleVal,
       roller: RNGRoller(Random(42)),
     );

     expect(pushed.results, isNotEmpty);
   });
   ```

8. **Push with exploded dice (result count may change):**
   ```dart
   test('push with exploded dice may change result count', () async {
     // Roll with exploding dice
     final expr = DiceExpression.create('3d6!', roller: RNGRoller(Random(1234)));
     final initial = await expr.roll();
     final initialCount = initial.results.length;

     final pushed = await reroll(initial,
       lockWhere: (die) => false, // re-roll everything
       roller: RNGRoller(Random(42)),
     );

     // Result count may differ -- explosion is not re-applied
     expect(pushed.results.length, isPositive);
     // But every die should be a valid d6
     expect(pushed.results.every((d) => d.nsides == 6), isTrue);
   });
   ```

9. **Heterogeneous labeled comma groups with scoring:**
   ```dart
   test('labeled groups with per-group scoring', () async {
     final expr = DiceExpression.create(
       '"A:" 2d6 #s>=5, "B:" 2d8 #s>=5',
       roller: RNGRoller(Random(1234)),
     );
     final result = await expr.roll();
     expect(result.groups, isNotNull);
     expect(result.groups!['A'], isNotNull);
     expect(result.groups!['B'], isNotNull);
   });
   ```

### 4.4 Risks & Open Items

1. **`DiceResultRoller.reroll()` behavior for `singleVal` dice.** The current `reroll()` method in `DiceResultRoller` returns a `RollResult` with a single `singleVal` die for `singleVal` dieType. This is correct -- a constant value like `+3` should not be re-rolled meaningfully. The push `lockWhere` predicate should lock these automatically, or the caller should handle it. Document that `singleVal` dice (from arithmetic like `+3`) are always effectively locked.

2. **Result count may change across pushes for exploding/compounding dice.** If a die originally exploded (producing extra dice), re-rolling it produces a fresh roll that may or may not explode. The result count could change. **This is acceptable** -- the push mechanic re-rolls individual dice, and explosion is a property of the original expression context that is lost during push. Document this limitation. For full fidelity, the caller could re-evaluate the entire expression, which is outside the push mechanic's scope.

3. **The `reroll()` method creates a synthetic `RollResult` without the full AST tree.** The `detailedResults` field of the new `RollSummary` will have a flat structure (no left/right subtree). This is intentional -- the push result is not a re-evaluation of the AST, it's a modification of the previous result. The `expression` field will say `"(original expr) (push)"` to distinguish it.

4. **Interaction with scoring operators.** If the original result had scoring flags (`success`, `failure`, etc.), those flags are preserved on locked dice but NOT recalculated on re-rolled dice. The re-rolled dice come from `DiceResultRoller.reroll()` which produces plain dice without scoring. The caller would need to re-apply scoring operators if desired. **This is a known limitation** -- scoring is an AST-level operation, and push operates below the AST. Document this: "Push re-rolls individual dice but does not re-evaluate scoring. Scoring flags from the original roll are preserved on locked dice but absent on re-rolled dice."

---

## Named Die Type Registry (D9)

### 5.1 Overview

A simple static registry on `DiceExpression` that maps string names to face lists. The grammar is extended to resolve `NdNAME` where `NAME` is a registered identifier.

### 5.2 File Changes

#### 5.2.1 `lib/src/dice_expression.dart` — Registry methods

**New static field and methods:**

```dart
/// Registry of custom die types. Maps name -> face values.
/// Populated by client at startup via [registerDieType].
static final Map<String, List<int>> _dieTypeRegistry = {};

/// Register a named die type for use in expressions.
///
/// After registration, expressions can reference the die by name:
/// ```dart
/// DiceExpression.registerDieType('fate', [-1, -1, 0, 0, 1, 1]);
/// final expr = DiceExpression.create('4dfate');
/// ```
static void registerDieType(String name, List<int> faces) {
  if (faces.isEmpty) {
    throw ArgumentError('Die type faces must be non-empty');
  }
  _dieTypeRegistry[name.toLowerCase()] = List.unmodifiable(faces);
}

/// Unregister a named die type.
static void unregisterDieType(String name) {
  _dieTypeRegistry.remove(name.toLowerCase());
}

/// Clear all registered die types.
static void clearDieTypes() {
  _dieTypeRegistry.clear();
}

/// Look up a registered die type. Returns null if not found.
/// Used internally by the parser.
static List<int>? getDieType(String name) {
  return _dieTypeRegistry[name.toLowerCase()];
}
```

#### 5.2.2 `lib/src/parser.dart` — Grammar extension for named die types

**What changes:** Add a new postfix rule in the special dice group (where `dF`, `D66`, `d%` are) that matches `d<name>` where `<name>` is a registered identifier.

**Concrete rule:**

```dart
// In the special dice group (after dF, D66, d%, d[...], penetrating):
..postfix(
  seq2(
    char('d').trim(),
    letter().plus().flatten().trim(),
  ).where((v) {
    // Only match if the name is a registered die type
    // and is NOT one of the built-in special names (F, %).
    final name = v.$2.toLowerCase();
    return name != 'f' && DiceExpression.getDieType(name) != null;
  }),
  (a, op) {
    final name = op.$2.toLowerCase();
    final faces = DiceExpression.getDieType(name)!;
    return NamedDice(op.toString(), a, roller, name, IList(faces));
  },
)
```

**CRITICAL: Parsing ambiguity.** The `d<name>` rule must be checked AFTER `dF`, `D66`, `d%` to avoid intercepting those. Since these are all in the same builder group as postfix operators, PetitParser tries them in order. Place the named die rule AFTER the built-in special dice rules.

Additionally, `d<name>` where name starts with a digit would conflict with `d<number>` (standard dice). Since `letter().plus()` requires the name to start with a letter, this conflict is avoided.

**Potential issue:** `dp` for penetrating dice. The penetrating dice rule matches `d<digits>p<digits?>`. Since the named type rule requires `letter().plus()` and the penetrating rule starts with `d<digit>`, there's no conflict UNLESS someone registers a die type starting with a digit (which `letter().plus()` prevents).

However, there IS a conflict with `dF` and `d%` -- these are already handled as higher-priority postfix rules in the same group, so they'll match first. Good.

**Remaining concern:** `d<name>` could match part of an expression like `d6` if somehow the `6` is parsed as a name. But `letter().plus()` requires at least one letter, and `6` is a digit, so no conflict.

#### 5.2.3 `lib/src/ast_dice.dart` — New `NamedDice` class

**New class:**

```dart
/// Roll dice with faces from a named die type registry.
/// NOTE: `super.roller` is a `DiceResultRoller` (not `DiceRoller`), matching
/// the `UnaryDice` constructor signature. The parser passes its `roller`
/// variable which is already a `DiceResultRoller`.
class NamedDice extends UnaryDice {
  NamedDice(super.op, super.left, super.roller, this.dieName, this.faces);

  final String dieName;
  final IList<int> faces;

  @override
  String toString() => '(${left}d$dieName)';

  @override
  Future<RollResult> eval() async {
    final lhs = await left();
    final ndice = lhs.totalOrDefault(() => 1);

    final roll = await roller.rollVals(ndice, faces);

    return RollResult.fromRollResult(
      roll,
      expression: toString(),
      opType: OpType.rollVals,
      left: lhs,
    );
  }
}
```

#### 5.2.4 `lib/src/parser.dart` — Import addition

Add `import 'dice_expression.dart';` if not already present (it is already imported).

### 5.3 Test Plan

1. **Register and use named die type:**
   ```dart
   test('named die type', () async {
     DiceExpression.registerDieType('fate', [-1, -1, 0, 0, 1, 1]);
     addTearDown(() => DiceExpression.unregisterDieType('fate'));

     final expr = DiceExpression.create('4dfate', roller: RNGRoller(Random(1234)));
     final result = await expr.roll();
     expect(result.results.length, 4);
     expect(result.results.every((d) => [-1, 0, 1].contains(d.result)), isTrue);
   });
   ```

2. **Named type is case-insensitive:**
   ```dart
   test('named die type case insensitive', () async {
     DiceExpression.registerDieType('Ability', [1, 1, 2, 2, 3, 3, 4]);
     addTearDown(() => DiceExpression.unregisterDieType('ability'));

     final expr = DiceExpression.create('2dAbility', roller: RNGRoller(Random(1234)));
     final result = await expr.roll();
     expect(result.results.length, 2);
   });
   ```

3. **Unregistered name fails to parse:**
   ```dart
   test('unregistered die type throws FormatException', () {
     expect(
       () => DiceExpression.create('2dunknown').roll(),
       throwsFormatException,
     );
   });
   ```

4. **Named type does not conflict with dF:**
   ```dart
   test('dF still works after registering named types', () async {
     DiceExpression.registerDieType('fire', [1, 2, 3]);
     addTearDown(() => DiceExpression.unregisterDieType('fire'));

     final expr = DiceExpression.create('4dF', roller: RNGRoller(Random(1234)));
     final result = await expr.roll();
     expect(result.results.every((d) => d.dieType == DieType.fudge), isTrue);
   });
   ```

5. **Register empty faces throws:**
   ```dart
   test('registering empty faces throws', () {
     expect(
       () => DiceExpression.registerDieType('empty', []),
       throwsArgumentError,
     );
   });
   ```

6. **Clear registry:**
   ```dart
   test('clearDieTypes removes all registered types', () {
     DiceExpression.registerDieType('test1', [1, 2]);
     DiceExpression.registerDieType('test2', [3, 4]);
     DiceExpression.clearDieTypes();

     expect(
       () => DiceExpression.create('2dtest1').roll(),
       throwsFormatException,
     );
   });
   ```

### 5.4 Risks & Open Items

1. **Parser re-creation per expression.** `DiceExpression.create()` calls `parserBuilder()` each time. The `.where()` clause on the named die postfix checks the registry at parse time. This means registering a die type AFTER creating an expression won't affect already-parsed expressions. This is correct and expected behavior.

2. **PetitParser `.where()` semantics.** The `.where()` combinator in PetitParser rejects the match if the predicate returns false, allowing the parser to try other alternatives. This is the correct way to conditionally match named die types. However, if no other rule matches `d<letters>`, the parse will fail with a generic error. This is acceptable -- the user gets a `FormatException` for an unregistered name.

3. **Performance.** The registry lookup happens during parsing, not evaluation. Since parsing is already O(n) and the registry is a `Map`, the additional cost is negligible.

4. **Thread safety.** The registry is a static mutable `Map`. In a single-isolate Dart application (typical for Flutter), this is fine. If used across isolates, each isolate has its own static state. No issue.

5. **Name collision with future grammar extensions.** If a future version adds new special dice syntax (like `dX` for some purpose), it could conflict with a registered name `x`. The `.where()` guard and ordering (built-in rules first) mitigate this. Document that certain names are reserved: `f`, `F` (fudge), `%` (percent).

---

## Implementation Order

1. **Phase 0A:** Fix `clearSummaryListeners()` bug (5 minutes)
2. **Phase 0B:** Delete dead code files (5 minutes)
3. **Phase 3:** Groups, Labels, Tags (largest piece of work)
   - 3a: Add `groupLabel` field to `RolledDie` **(MUST be first — 3b depends on this field existing)**
   - 3b: Add `LabelOp` and `TagOp` AST nodes (calls `RolledDie.copyWith` with `groupLabel`/`tags`)
   - 3c: Rework `CommaOp` to preserve die identity
   - 3d: Add grammar rules for labels and tags
   - 3e: Create `GroupResult` class
   - 3f: Extend `RollSummary` with `groups` field
   - 3g: Update barrel export
   - 3h: Fix broken tests, write new tests
4. **D9:** Named Die Type Registry (can be done in parallel with Phase 3)
   - D9a: Add registry methods to `DiceExpression`
   - D9b: Add `NamedDice` AST node
   - D9c: Add grammar rule
   - D9d: Write tests
5. **Phase 4:** Push / Re-roll
   - 4a: Add `locked` field to `RolledDie`
   - 4b: Create `lib/src/push.dart` with standalone `reroll()` function
   - 4c: Export from `lib/dart_dice_parser.dart`
   - 4d: Write tests

---

## Summary of All Files Touched

| File | Phase | Action | Description |
|------|-------|--------|-------------|
| `lib/src/dice_expression.dart` | 0A, D9 | MODIFY | Fix clearSummaryListeners bug; add die type registry |
| `lib/src/ast.dart` | 0B | DELETE | Dead code |
| `lib/src/results.dart` | 0B | DELETE | Dead code |
| `lib/src/rolled_die.dart` | 3, 4 | MODIFY | Add groupLabel, tags, locked fields |
| `lib/src/ast_core.dart` | 3 | MODIFY | Rework CommaOp; add LabelOp, TagOp |
| `lib/src/parser.dart` | 3, D9 | MODIFY | Add label/tag/named-type grammar rules |
| `lib/src/group_result.dart` | 3 | CREATE | GroupResult class |
| `lib/src/roll_summary.dart` | 3 | MODIFY | Add groups field |
| `lib/src/push.dart` | 4 | CREATE | Standalone reroll() function |
| `lib/src/roll_result.dart` | 3 | MODIFY | Add optional tags field |
| `lib/src/ast_dice.dart` | D9 | MODIFY | Add NamedDice class |
| `lib/dart_dice_parser.dart` | 3 | MODIFY | Export group_result.dart |
| `test/dart_dice_parser_test.dart` | 3, 4, D9 | MODIFY | Fix broken comma tests; add new test groups |
