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
  dart_dice_parser.dart       # Public API exports
  src/
    dice_expression.dart      # Main API: DiceExpression, DiceResultRoller
    parser.dart               # PetitParser-based dice notation parser
    ast.dart                  # Re-exports all AST classes
    ast_core.dart             # Base AST: DiceOp, Unary, Binary, SimpleValue
    ast_dice.dart             # Dice types: FudgeDice, D66Dice, PercentDice, CSVDice, PenetratingDice
    ast_ops.dart              # Operations: ExplodingDice, CompoundingDice, RerollDice, DropOp, CountOp, ClampOp
    dice_roller.dart          # RNG abstraction: DiceRoller, RNGRoller, PreRolledDiceRoller
    results.dart              # Result processing
    roll_result.dart          # Binary tree result nodes with traversal
    roll_summary.dart         # Top-level RollSummary output
    rolled_die.dart           # Immutable individual die roll representation
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
- **JSON:** `toJson()` methods on result types; empty/zero values omitted for clean output.
- **Exports:** Public API surface defined in `lib/dart_dice_parser.dart`. Only export what users need.

## Testing

- Single test file: `test/dart_dice_parser_test.dart`
- Uses seeded `Random(1234)` for deterministic results.
- `MockRandom` (via `mocktail`) for controlled random values.
- Helper functions: `seededRandTest()` and `staticRandTest()` for grouped assertions.
- Tests run on both VM and Chrome platforms.
- Coverage tracked via Codecov.

## Supported Dice Notation

Basic: `2d6`, `1d20`, `4dF`, `1d%`, `1D66`, `2d[2,3,5,7]`
Exploding/Compounding: `4d6!`, `5d6!!`, `4d6!>=4`, `5d6!!o`
Rerolling: `4d4r2`, `4d4ro<2`
Keep/Drop: `3d20kh`, `4d6-L`, `4d6->5`
Clamping: `4d20C<5`, `4d20C>15`
Counting: `4d6#`, `4d6#>3`, `2d20#cf#cs`
Arithmetic: `+`, `-`, `*`, parentheses
Penetrating: `4d6p`
