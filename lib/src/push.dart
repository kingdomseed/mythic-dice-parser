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
///
/// **Known limitation:** Re-rolled dice do not have scoring flags
/// (`success`, `failure`, etc.) re-applied. Scoring is an AST-level
/// operation, and push operates below the AST. Scoring flags from the
/// original roll are preserved on locked dice but absent on re-rolled dice.
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
    final shouldLock =
        die.locked ||
        die.dieType == DieType.singleVal ||
        die.totaled ||
        lockWhere(die);
    if (shouldLock) {
      newResults.add(RolledDie.copyWith(die, locked: true));
    } else {
      newDiscarded.add(RolledDie.copyWith(die, discarded: true));
      final rerolled = await diceResultRoller.reroll(die);
      newResults.addAll(
        rerolled.results.map(
          (r) => die.groupLabel != null
              ? RolledDie.copyWith(r, groupLabel: die.groupLabel)
              : r,
        ),
      );
    }
  }

  final newRollResult = RollResult(
    expression: '${summary.expression} (push)',
    opType: OpType.reroll,
    results: newResults,
    discarded: newDiscarded,
    left: summary.detailedResults,
  );

  return RollSummary(detailedResults: newRollResult);
}
