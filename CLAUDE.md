# CLAUDE.md

## Project Overview

**dart_dice_parser** — A Dart library for parsing and evaluating dice notation (e.g., `2d6+4`, `4d6!kh3`). Parses notation strings into an AST, evaluates them with configurable RNG, and returns detailed roll results with metadata.

- **Package name:** `dart_dice_parser`
- **Version:** 8.0.0
- **SDK requirement:** Dart >=3.8.0
- **Published on:** pub.dev

## Build & Development Commands

```bash
# Install dependencies
dart pub upgrade --no-precompile

# Format code (80-char line width enforced)
dart format .

# Check formatting without modifying
dart format --output=none --set-exit-if-changed .

# Static analysis (treats infos as fatal)
dart analyze --fatal-infos .

# Run tests on VM
dart test --platform vm

# Run tests on Chrome
dart test --platform chrome

# Run examples
dart run example/simple.dart
dart run example/main.dart -n 10 -o pretty '(3d6 + 3d6! + 3d6!!) #cs #cf #s #f'

# Generate coverage
dart pub global run coverage:test_with_coverage --branch-coverage
```

## CI Pipeline

Defined in `.github/workflows/dart.yml`. Runs on push/PR to main and weekly. Steps: format check → analyze → test (VM + Chrome) → examples → coverage upload to Codecov.

## Project Structure

```
lib/
  dart_dice_parser.dart       # Public API exports (barrel file)
  src/
    dice_expression.dart      # Main API: DiceExpression, named die registry
    parser.dart               # PetitParser-based dice notation parser
    ast_core.dart             # Core AST: DiceOp, Unary, Binary, SimpleValue, CommaOp, LabelOp, TagOp, AggregateOp
    ast_dice.dart             # Dice types: FudgeDice, D66Dice, PercentDice, CSVDice, PenetratingDice, NamedDice
    ast_ops.dart              # Operations: ExplodingDice, CompoundingDice, RerollDice, DropOp, CountOp, ClampOp, SortOp
    dice_roller.dart          # RNG abstraction: DiceRoller, RNGRoller, PreRolledDiceRoller, DiceResultRoller
    roll_result.dart          # Binary tree result nodes (tags field for @key=value metadata)
    roll_summary.dart         # Top-level RollSummary with groups support
    rolled_die.dart           # Immutable individual die roll representation (locked, groupLabel fields)
    group_result.dart         # Per-group results for labeled comma expressions
    push.dart                 # Standalone reroll() function for push/reroll mechanic
    enums.dart                # DieType, OpType, CountType
    extensions.dart           # Extension methods on IList<RolledDie>
    stats.dart                # StatsCollector (Welford's algorithm)
    utils.dart                # Logging mixin
test/
  dart_dice_parser_test.dart  # Single test file (~1165 lines)
example/
  simple.dart                 # Basic usage
  main.dart                   # CLI with arg parsing
```

## Architecture

- **Parser:** Built with `petitparser` (parser combinators). Entry point is `parserBuilder()` in `parser.dart`.
- **AST:** Parsed expressions become a binary tree of `DiceOp` nodes. Each node implements `call()` → `Future<RollResult>`.
- **Results:** `RollResult` is a tree node with `left`/`right` pointers, enabling introspection. `RollSummary` is the top-level output.
- **Groups:** Comma-separated labeled expressions (`"Attack:" 2d6, "Damage:" 1d8`) produce `GroupResult` objects accessible via `RollSummary.groups`.
- **Push/Reroll:** Standalone `reroll()` function in `push.dart` re-rolls unlocked dice from a `RollSummary`. Supports multi-push and auto-locks constants.
- **Named Die Types:** Static registry on `DiceExpression` maps names to face lists (e.g., `4dfate` after `registerDieType('fate', [-1,-1,0,0,1,1])`).
- **Tags:** `@key=value` syntax on expressions, stored on `RollResult` nodes and harvested into `GroupResult.tags`.
- **Immutability:** Extensive use of `fast_immutable_collections` (`IList`). All result objects are immutable value types.
- **Equality:** Uses `Equatable` mixin for value equality.

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `petitparser` | Parser combinator for dice notation |
| `fast_immutable_collections` | Immutable collections (`IList`) |
| `equatable` | Value equality |
| `collection` | Collection utilities |
| `logging` | Structured logging |
| `test` | Testing framework |
| `mocktail` | Mocking in tests |
| `lint` | Lint rules (`package:lint/package.yaml`) |

## Code Conventions

- **Naming:** PascalCase for classes, camelCase for methods/variables/constants, leading underscore for private members.
- **Formatting:** 80-character line width, `dart format` enforced.
- **Linting:** Strict mode (`strict-casts: true`, `strict-raw-types: true`). All infos treated as fatal in CI.
- **Async:** Core operations (`call()`, `roll()`, `stats()`) are async. Use `Future` and `Stream` for results.
- **Immutability:** Prefer `final` fields and immutable collections. Use `IList` from `fast_immutable_collections`.
- **Factory constructors:** Common pattern — e.g., `RolledDie.polyhedral()`, `RolledDie.singleVal()`, `RollResult.fromRollResult()`.
- **Operator overloading:** `+`, `-`, `*` defined on `RollResult`.
- **JSON:** `toJson()` methods on result types; empty/zero/null values omitted via `removeWhere` for clean output.
- **Exports:** Public API surface defined in `lib/dart_dice_parser.dart`. Only export what users need.
- **Separation of concerns:** Roller returns raw ints, AST interprets meaning. Push operates below the AST (no scoring re-application).

## Testing

- Single test file: `test/dart_dice_parser_test.dart`
- Uses seeded `Random(1234)` for deterministic results.
- `MockRandom` (via `mocktail`) for controlled random values.
- Helper functions: `seededRandTest()` and `staticRandTest()` for grouped assertions.
- Tests run on both VM and Chrome platforms.
- Coverage tracked via Codecov.

## Supported Dice Notation

Basic: `2d6`, `1d20`, `4dF`, `1d%`, `1D66`, `2d[2,3,5,7]`, `4dfate` (named)
Exploding/Compounding: `4d6!`, `5d6!!`, `4d6!>=4`, `5d6!!o`
Rerolling: `4d4r2`, `4d4ro<2`
Keep/Drop: `3d20kh`, `4d6-L`, `4d6->5`
Clamping: `4d20C<5`, `4d20C>15`
Counting: `4d6#`, `4d6#>3`, `2d20#cf#cs`
Arithmetic: `+`, `-`, `*`, parentheses
Penetrating: `4d6p`
Labels: `"Attack:" 2d6, "Damage:" 1d8`
Tags: `2d6 @type=fire @source=spell`
Sorting: `4d6s`, `4d6sd`
