import 'cache_entry.dart';

/// Cached entries and their age.
final class CacheSnapshot {
  const CacheSnapshot({required this.entries, required this.fetchedAt});

  final List<CacheEntry> entries;

  /// When the entries were last fetched as a whole.
  final DateTime fetchedAt;
}
