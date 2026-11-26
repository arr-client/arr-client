import 'item_ref.dart';
import 'quality.dart';

/// A blocked release.
final class BlocklistEntry {
  /// Creates a [BlocklistEntry].
  const BlocklistEntry({
    required this.id,
    required this.sourceTitle,
    required this.date,
    this.itemRef,
    this.quality,
    this.reason,
  });

  /// The server's id of the entry.
  final int id;

  /// The item the release was for.
  final ItemRef? itemRef;

  /// The release's title.
  final String sourceTitle;

  /// When it was blocked.
  final DateTime date;

  /// The release's quality.
  final Quality? quality;

  /// Why it was blocked.
  final String? reason;
}
