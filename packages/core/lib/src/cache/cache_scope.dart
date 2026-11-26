import '../models/item_ref.dart';
import '../models/media_kind.dart';
import '../models/server_option.dart';
import 'cache_entry.dart';
import 'cache_snapshot.dart';
import 'cached.dart';

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

  /// For an item the server no longer has. It is announced on [removals],
  /// whether it was cached or not.
  Future<void> remove(MediaKind kind, int remoteId);

  /// The items of this instance given to [remove], once they have left the
  /// cache, so that what holds them in memory can drop them too.
  Stream<ItemRef> get removals;

  /// The server's options as last stored; null if never.
  Future<Cached<List<ServerOption>>?> readOptions();

  /// Stores the server's options, all of them.
  Future<void> replaceOptions(List<ServerOption> options);
}
