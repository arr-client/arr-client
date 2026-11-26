import 'item_ref.dart';
import 'quality.dart';

/// What was imported for one item.
final class ImportedItem {
  /// Creates an [ImportedItem].
  const ImportedItem({
    required this.title,
    required this.importedAt,
    this.itemRef,
    this.quality,
  });

  /// The item imported.
  final ItemRef? itemRef;

  /// Title to show.
  final String title;

  /// When, from the server.
  final DateTime importedAt;

  /// The imported quality.
  final Quality? quality;
}
