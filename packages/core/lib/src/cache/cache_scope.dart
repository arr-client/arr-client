import '../models/media_kind.dart';
import 'cache_entry.dart';
import 'cache_snapshot.dart';

/// The cache of one instance. It cannot reach another instance's entries.
abstract interface class CacheScope {
  /// All entries of [kind], or those of one parent. Null if never fetched,
  /// which differs from fetched and empty.
  Future<CacheSnapshot?> read(MediaKind kind, {int? parentRemoteId});

  /// One entry, or null if it is not cached.
  Future<CacheEntry?> entry(MediaKind kind, int remoteId);

  /// Stores a full fetch: entries of [kind] (under [parentRemoteId], if given)
  /// that are not in [entries] are removed.
  Future<void> replace(
    MediaKind kind,
    List<CacheEntry> entries, {
    int? parentRemoteId,
  });

  /// Adds or updates one entry.
  Future<void> put(CacheEntry entry);

  /// For an item the server no longer has.
  Future<void> remove(MediaKind kind, int remoteId);
}
