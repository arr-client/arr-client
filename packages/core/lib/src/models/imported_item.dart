import 'item_ref.dart';
import 'quality.dart';

/// What was imported for one item.
final class ImportedItem {
  const ImportedItem({
    required this.title,
    required this.importedAt,
    this.itemRef,
    this.quality,
  });

  final ItemRef? itemRef;

  final String title;

  final DateTime importedAt;

  final Quality? quality;
}
