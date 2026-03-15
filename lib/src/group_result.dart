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
