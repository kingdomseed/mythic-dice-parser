# 8.0.0

## ⚠️⚠️ Breaking changes ⚠️⚠️

- `roll()` and all AST evaluation are now fully async (`Future<RollSummary>`)
- `RollResult.results` and `RollResult.discarded` are now `IList<RolledDie>` (immutable)
- `DiceExpression.create()` accepts a `DiceRoller` via the `roller:` named parameter instead of a positional `Random`
- `RollSummary` replaces the old metadata map with structured fields: `results`, `discarded`, `groups`, `detailedResults`
- Upgraded `petitparser` from ^6.1.0 to ^7.0.2

## 📈 Enhancements
- **Labeled groups:** `"Attack": 2d6, "Damage": 1d8` -- comma-separated labeled expressions produce `GroupResult` objects via `RollSummary.groups`
- **Tags:** `2d6 @type=fire @source=spell` -- attach key-value metadata to expressions, harvested into `GroupResult.tags`
- **Named die types:** `DiceExpression.registerDieType('fate', [-1,-1,0,0,1,1])` then use `4dfate` in expressions
- **Pluggable dice roller:** `DiceRoller` abstract class with three implementations:
  - `RNGRoller` -- wraps `Random` (default)
  - `PreRolledDiceRoller` -- feed in physical/external dice results
  - `CallbackDiceRoller` -- async on-demand prompts (3D dice, Bluetooth, manual entry)
- **Push/reroll:** `reroll(summary, lockWhere: ..., roller: ...)` re-rolls unlocked dice, preserving locked dice and group structure. Supports multi-push.
- **RolledDie enrichment:** `groupLabel`, `locked`, `totaled` fields. `toJson()` now includes `totaled`.
- **GroupResult:** per-group `total`, `successCount`, `failureCount`, `critSuccessCount`, `critFailureCount` (computed lazily), `discarded`, and `tags`
- **Immutable tags:** `RollResult.tags` and `GroupResult.tags` are now `Map.unmodifiable()`
- **Penetrating dice:** `4d6p` syntax

## 🛠️ Bug fixes
- `CommaOp.hasLabels` now checks both `.results` and `.discarded`, fixing a bug where all-discarded labeled groups lost their group identity
- `GroupResult` stats converted from redundant stored fields (6x `IList` wrapping) to lazy getters
- Removed dead `.plus()` from tag postfix parser -- `ExpressionBuilder.star()` handles multi-tag repetition

# 7.1.1
## 🛠️ Bug fixes
- fix typo in readme


# 7.1.0

## 📈 Enhancements
- upgrade to dart 3.6.0
- add roll notation to support defining your own values. `1d[val1,val2,val3]`
  For example, to roll 2 dice of primes under 20, use: `2d[2,3,5,7,11,13,17,19]` 


# 7.0.3

## 🛠️ Bug fixes
- Previously, `4d6 + 3d6 #s #f` would only count success/failures of the 3d6 rolls, since counting
  had higher priority than the plus operation. You could workaround that with parens `(4d6 + 3d6) #s #f`
  In 7.0.3 and later, the counting operations now have the lowest priority.

# 7.0.2
- remove demo code accidentally added

# 7.0.1
- remove direct dependency on `meta`

# 7.0.0

## ⚠️⚠️ Breaking changes ⚠️⚠️

The roll results have changed significantly. Now, there's a RollSummary object that includes
a tree of results from evaluating the dice expression. See the README for examples of how to
traverse the graph.

## 📈 Enhancements
- new API for registering roll listeners. see README.md
- analysis cleanup and dep upgrades

## 🛠️ Bug fixes
- propagate the roll metadata up to the top of the graph


# 6.0.2
- more readme fixes
- cleanup error handling / exceptions

# 6.0.1
- fix deprecation
- minor readme language changes

# 6.0.0
- dart 3.0 requirement
- upgrade deps

# 5.1.5
- clean up example documenation in README.md

# 5.1.4
- upgrade deps (lint)

# 5.1.3
- transfer repository to Adventuresmith org

# 5.1.2
- fix error messages with extraneous `'`
- make examples in README less abstract
- add method for json encoding roll result

# 5.1.1
- add syntax for exploding/compounding/reroll once
  - `4d6 !o`
  - `4d6 !!o`
  - `4d6 ro`
- add syntax for success, failure, as well as crit success & failure.
  - `4d6 #s=6`
  - plain `#` counts results and transforms the expression from rolls into a count.
  - but `#s`, `#f`, `#cs`, `#cf` only add metadata to the roll result, and can be chained together.
    - `9d6! -= 3 #s>=5#f1#cs` -- roll 9d6 with exploding, drop any threes, count >=5 as success, 1s as failures, and 6 as critical success

# 5.1.0
- make RollResult aggregate _all_ results for whole AST

# 5.0.0
- add compounding dice: `5d6!!`
- add keep high/low: `2d20k`
- add reroll: `10d4 r<=2`
- allow exploding/compounding dice to have an rhs expression (>=,<=,=,<,>)
- remove `!!` as 'limited explosion' (make it compounding, like Roll20 dice notation)
- fix syntax for exploding dice (2d6!, not 2d!6). 
- remove exploding method from DiceRoller -- now it's part of the AST. 
- dice rolls return RollResult
- clean up redundant parser config

# 4.1.0
- cleanup examples
- add syntax for `>=` and `<=` for counts, drop, clamp
- remove redundancy in parser defintion

# 4.0.6
- allow subtraction

# 4.0.5
- remove unused dev dependency

# 4.0.4
- fix typo in unit test

# 4.0.3
- increase test coverage -- test rollN and stats.

# 4.0.1
- add github actions, remove circleci
- add codecov

# 4.0.0
- cleanup petitparser usage -- generate AST so that parsing the dice expression can be separate from rolling dice.

# 3.1.0
- remove subtraction
- clean up add/mult -- don't collapse lists to ints
  - `[1,4,5] + 2` => `[1,4,5,2]`
  - `[1,4,5] * 2` => `[2,8,10]`
- remove subtraction -- like division, too many corner cases
- clean up error handling -- throw less often, less complex if/else statements.

# 3.0.3
- update linter and fix analysis 

# 3.0.2
- fix circleci build

# 3.0.1
- minor analysis cleanup (dead code)

# 3.0.0
- upgrade deps & null safety
- more error handling

# 2.0.1
- downgrade petitparser

# 2.0.0
- library upgrades including sdk >2.7.0

# 1.4.2
- use unmodifiable view return types

# 1.4.1
- fix return types of stats objects

# 1.4.0
- replace use of stats library w/ implementation of welford's algorithm.
  see http://alias-i.com/lingpipe/docs/api/com/aliasi/stats/OnlineNormalEstimator.html
- make DiceParser.rollN an async generator returning stream of results

# 1.3.6
- allow lowercase for `-H`, `-L`, `C>`, `C<`

# 1.3.5
- back off petitparser dependency -- back off to 2.2.1,
  so that we don't have dependency on Dart 2.3.0
  (current stable flutter is 2.3.0-dev)

# 1.3.4
- make code more idiomatic

# 1.3.3
- make log fields non-public

# 1.3.2
- upgrade mockito dep

# 1.3.0
- add drop equals/less-than/greater-than
- add cap/clamp
- add counting operation
- add exploding dice

# 1.2.2
- more logging and error handling cleanup

# 1.2.1
- more logging and error handling cleanup

# 1.2.0
- add dice stats to the parser
- logging & error handling cleanup

# 1.1.2
- more tests and cleanup examples

# 1.1.1
- fix typo in readme

# 1.1.0
- add drop high/low parsing

# 1.0.2
- fix readme example

# 1.0.1
- fix readme issues

# 1.0.0
- bump min dart SDK to 2.2.2
- cleanup parser code
- cleanup analysis problems
- add percentile and D66 dice
- handle missing A or X in AdX
- flesh out API docs

# 0.2.2
- reformat

# 0.2.1
- upgrade some dependencies

# 0.2.0
- upgrade to dart 2

# 0.1.2

- move args to dev_dependency, since it's just for the example

# 0.1.1

- added contributing/code-of-conduct docs

# 0.1.0

- change DiceRoller to output information about individual rolls, instead of just returning the sum.

# 0.0.6

- remove dependency on quiver, since not heavily using it

# 0.0.5

- various fixes as I figure out what I'm doing with Dart
- empty/null checking with quiver.strings

# 0.0.1

- Initial version, created by Steve Christensen

