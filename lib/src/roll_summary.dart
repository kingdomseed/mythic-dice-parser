import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'extensions.dart';
import 'group_result.dart';
import 'roll_result.dart';
import 'rolled_die.dart';

/// [RollSummary] is the final result of rolling a dice expression.
/// It rolls up the metadata of sub-expressions, and includes a `detailResults`
/// if the caller wants to do something interesting to display the result graph.
///
/// A [RollResult] is modeled as a binary tree. The dice expression
/// is parsed into an AST, and when rolled the results reflect the structure of
/// that AST.
///
/// In general, users will only care about the root node of the tree.
/// But, depending on the information you want from the evaluated dice rolls,
/// you may need to traverse the tree to inspect all the events.

class RollSummary extends Equatable {
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

  final RollResult detailedResults;

  /// sum of [results]
  late final int total;
  late final int successCount;
  late final int failureCount;
  late final int critSuccessCount;
  late final int critFailureCount;

  /// the parsed expression
  late final String expression;

  /// the results of the evaluating the expression
  late final IList<RolledDie> results;

  /// the dice we lost along the way
  late final IList<RolledDie> discarded;

  /// Per-group results, populated when the expression uses label syntax.
  /// null when no labels/commas are used (plain expressions like "2d6+4").
  final Map<String, GroupResult>? groups;

  @override
  List<Object?> get props => [
    total,
    successCount,
    failureCount,
    critSuccessCount,
    critFailureCount,
    expression,
    results,
    discarded,
    groups,
  ];

  @override
  String toString() {
    final buffer = StringBuffer(
      '$expression ===> RollSummary(total: $total, results: ${results.toString(false)}',
    );
    if (discarded.isNotEmpty) {
      buffer.write(', discarded: ${discarded.toString(false)}');
    }
    final params = {
      'successCount': successCount,
      'failureCount': failureCount,
      'critSuccessCount': critSuccessCount,
      'critFailureCount': critFailureCount,
    }..removeWhere((k, v) => v == 0);

    if (params.isNotEmpty) {
      buffer.write(', ');
      buffer.writeAll(
        params.entries.map((entry) => '${entry.key}: ${entry.value}'),
        ', ',
      );
    }

    buffer.write(')');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() =>
      {
        'expression': expression,
        'total': total,
        'successCount': successCount,
        'failureCount': failureCount,
        'critSuccessCount': critSuccessCount,
        'critFailureCount': critFailureCount,
        'results': results.map((e) => e.toJson()).toList(growable: false),
        'discarded': discarded.map((e) => e.toJson()).toList(growable: false),
        'detailedResults': detailedResults.toJson(),
        'groups': groups?.map((k, v) => MapEntry(k, v.toJson())),
      }..removeWhere(
        (k, v) =>
            v == null ||
            (v is Map && v.isEmpty) ||
            (v is Iterable && v.isEmpty) ||
            (v is int && v == 0) ||
            (v is bool && !v),
      );

  String toStringPretty() {
    final buffer = StringBuffer();
    buffer
      ..write(toString())
      ..write('\n')
      ..write(detailedResults.toStringPretty(indent: '  '));

    return buffer.toString();
  }

  static Map<String, GroupResult>? _buildGroups(RollResult detailedResults) {
    // Only build groups when the expression used labels.
    final hasLabels =
        detailedResults.results.any((d) => d.groupLabel != null) ||
        detailedResults.discarded.any((d) => d.groupLabel != null);
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
    final groupTags = <String, Map<String, String>>{};
    _harvestTags(detailedResults, groupTags);

    final allLabels = {...grouped.keys, ...groupedDiscarded.keys};
    return {
      for (final label in allLabels)
        label: GroupResult(
          label: label,
          results: grouped[label] ?? [],
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
      // Find all distinct group labels from this node's results AND
      // discarded dice. When all dice are discarded (e.g., keep-0),
      // results is empty but discarded carries the labels.
      final labels = {
        ...node.results.map((d) => d.groupLabel).whereType<String>(),
        ...node.discarded.map((d) => d.groupLabel).whereType<String>(),
      };
      if (labels.isEmpty) {
        // No labels found; assign to the anonymous group.
        groupTags.putIfAbsent('', () => {}).addAll(node.tags!);
      } else {
        for (final label in labels) {
          groupTags.putIfAbsent(label, () => {}).addAll(node.tags!);
        }
      }
    }
    if (node.left != null) _harvestTags(node.left!, groupTags);
    if (node.right != null) _harvestTags(node.right!, groupTags);
  }
}
