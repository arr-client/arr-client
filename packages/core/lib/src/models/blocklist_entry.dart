import 'item_ref.dart';
import 'quality.dart';

/// A blocked release.
final class BlocklistEntry {
  const BlocklistEntry({
    required this.id,
    required this.sourceTitle,
    required this.date,
    this.itemRef,
    this.quality,
    this.reason,
  });

  final int id;

  final ItemRef? itemRef;

  final String sourceTitle;

  final DateTime date;

  final Quality? quality;

  final String? reason;
}
