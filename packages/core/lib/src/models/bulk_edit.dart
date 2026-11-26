import 'tag_change.dart';

/// A change to several items at once; null means unchanged.
final class BulkEdit {
  /// Creates a [BulkEdit].
  const BulkEdit({
    this.monitored,
    this.qualityProfileId,
    this.tagIds,
    this.tagChange = TagChange.add,
  });

  /// The new monitored flag.
  final bool? monitored;

  /// The new quality profile.
  final int? qualityProfileId;

  /// Tags to apply as [tagChange] says.
  final Set<int>? tagIds;

  /// Applies to [tagIds].
  final TagChange tagChange;
}
