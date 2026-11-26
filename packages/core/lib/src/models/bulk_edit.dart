import 'tag_change.dart';

/// A change to several items at once; null means unchanged.
final class BulkEdit {
  const BulkEdit({
    this.monitored,
    this.qualityProfileId,
    this.tagIds,
    this.tagChange = TagChange.add,
  });

  final bool? monitored;

  final int? qualityProfileId;

  final Set<int>? tagIds;

  /// Applies to [tagIds].
  final TagChange tagChange;
}
