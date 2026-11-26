import 'package:core/core.dart';

/// One item of the library, with what filtering and sorting compare, worked out
/// once: a library holds thousands.
final class LibraryEntry {
  LibraryEntry(this.item)
    : titleKey = item.title.toLowerCase(),
      sortKey = item.sortTitle.toLowerCase();

  final LibraryItem item;

  /// The title as the filter box compares it.
  final String titleKey;

  /// The title as the order compares it.
  final String sortKey;

  String get instanceId => item.ref.instanceId;
}
