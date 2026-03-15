import 'dice_expression.dart';
import 'dice_roller.dart';
import 'enums.dart';
import 'extensions.dart';
import 'roll_result.dart';
import 'rolled_die.dart';
import 'utils.dart';

/// All our operations will inherit from this class.
/// The `call()` method will be called by the parent node.
/// The `eval()` method is called from the node
abstract class DiceOp extends DiceExpression with LoggingMixin {
  // each child class should override this to implement their operation
  Future<RollResult> eval();

  // all children can share this call operator -- and it'll let us be consistent w/ regard to logging
  @override
  Future<RollResult> call() async {
    final result = await eval();
    logger.finer(() => '$result');
    return result;
  }
}

/// base class for unary operations
abstract class Unary extends DiceOp {
  Unary(this.name, this.left);

  final String name;
  final DiceExpression left;

  @override
  String toString() => '($left)$name';
}

/// base class for binary operations
abstract class Binary extends DiceOp {
  Binary(this.name, this.left, this.right);

  final String name;
  final DiceExpression left;
  final DiceExpression right;

  @override
  String toString() => '($left $name $right)';
}

class CommaOp extends Binary {
  CommaOp(super.name, super.left, super.right);

  @override
  Future<RollResult> eval() async {
    final lhs = await left();
    final rhs = await right();

    // Check if any child has labeled dice (from LabelOp)
    final hasLabels =
        lhs.results.any((d) => d.groupLabel != null) ||
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
  RollResult _evalLabeled(RollResult lhs, RollResult rhs) => RollResult(
    expression: toString(),
    opType: OpType.comma,
    results: [...lhs.results, ...rhs.results],
    discarded: [...lhs.discarded, ...rhs.discarded],
    left: lhs,
    right: rhs,
  );

  /// Existing behavior: collapse each sub-expression to a singleVal total.
  RollResult _evalTotalized(RollResult lhs, RollResult rhs) {
    final results = <RolledDie>[];
    final discarded = <RolledDie>[];

    discarded.addAll(lhs.discarded);
    discarded.addAll(rhs.discarded);

    if (lhs.opType == OpType.comma) {
      results.addAll(lhs.results);
    } else {
      results.add(
        RolledDie.singleVal(
          result: lhs.results.sum,
          from: lhs.results,
          totaled: true,
        ),
      );
      discarded.addAll(lhs.results.map(RolledDie.discard));
    }
    if (rhs.opType == OpType.comma) {
      results.addAll(rhs.results);
    } else {
      results.add(
        RolledDie.singleVal(
          result: rhs.results.sum,
          from: rhs.results,
          totaled: true,
        ),
      );
      discarded.addAll(rhs.results.map(RolledDie.discard));
    }

    return RollResult(
      expression: toString(),
      opType: OpType.comma,
      results: results,
      discarded: discarded,
      left: lhs,
      right: rhs,
    );
  }
}

/// multiply operation (flattens results)
class MultiplyOp extends Binary {
  MultiplyOp(super.name, super.left, super.right);

  @override
  Future<RollResult> eval() async => await left() * await right();
}

/// add operation
class AddOp extends Binary {
  AddOp(super.name, super.left, super.right);

  @override
  Future<RollResult> eval() async => await left() + await right();
}

/// subtraction operation
class SubOp extends Binary {
  SubOp(super.name, super.left, super.right);

  @override
  Future<RollResult> eval() async => await left() - await right();
}

/// base class for unary dice operations
abstract class UnaryDice extends Unary {
  UnaryDice(super.name, super.left, this.roller);

  final DiceResultRoller roller;

  @override
  String toString() => '($left$name)';
}

/// base class for binary dice expressions
abstract class BinaryDice extends Binary {
  BinaryDice(super.name, super.left, super.right, this.roller);

  final DiceResultRoller roller;
}

/// A value expression. The token we read from input will be a String,
/// it must parse as an int, and an empty string will return empty set.
class SimpleValue extends DiceExpression {
  SimpleValue(this.value)
    : _results = RollResult(
        expression: value,
        opType: OpType.value,
        results: value.isEmpty
            ? []
            : [RolledDie.singleVal(result: int.parse(value))],
      );

  final String value;
  final RollResult _results;

  @override
  Future<RollResult> call() async => _results;

  @override
  String toString() => value;
}

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
      discarded: result.discarded.map(
        (d) => RolledDie.copyWith(d, groupLabel: label),
      ),
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
      tags: {...?result.tags, ...tags},
    );
  }
}

class AggregateOp extends DiceOp {
  AggregateOp(this.subexpression);

  final DiceExpression subexpression;

  @override
  String toString() => '{$subexpression}';

  @override
  Future<RollResult> eval() async {
    final outcome = await subexpression();

    return RollResult(
      expression: toString(),
      opType: OpType.total,
      results: [
        RolledDie.singleVal(
          result: outcome.results.sum,
          from: outcome.results,
          totaled: true,
        ),
      ],
      discarded: [
        ...outcome.discarded,
        ...outcome.results.map(RolledDie.discard),
      ],
      left: outcome,
    );
  }
}
