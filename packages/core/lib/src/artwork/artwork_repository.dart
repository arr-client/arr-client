import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The record of the cached files, a JSON file beside them.
///
/// Unlike its base it limits their total size, writes less often, and can be
/// retired so that nothing writes into a directory that is being deleted.
final class ArtworkRepository extends JsonCacheInfoRepository {
  /// Records in [file] files of at most [maximumBytes] together.
  ArtworkRepository(super.file, {required this._maximumBytes})
    : super.withFile();

  final int _maximumBytes;
  var _retired = false;

  /// Writes what is pending, and nothing afterwards.
  Future<void> retire() async {
    _retired = true;
    await close();
  }

  /// The least recently used files beyond [capacity] files or the size limit.
  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async {
    if (_retired) return [];
    final newestFirst = await getAllObjects()
      ..sort((a, b) => b.touched!.compareTo(a.touched!));
    var bytes = 0;
    var kept = 0;
    for (final object in newestFirst) {
      bytes += object.length ?? 0;
      if (kept == capacity || bytes > _maximumBytes) break;
      kept++;
    }
    return newestFirst.sublist(kept);
  }

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async =>
      _retired ? [] : await super.getOldObjects(maxAge);

  /// The cache manager writes an entry again each time it reads it, to note
  /// when it was used, and each write is the whole record. So a use soon after
  /// the last noted one is not written.
  @override
  Future<dynamic> updateOrInsert(CacheObject cacheObject) async {
    if (_retired) return null;
    final stored = await get(cacheObject.key);
    if (stored != null && _onlyUsedAgain(stored, cacheObject)) return stored;
    return super.updateOrInsert(cacheObject);
  }

  static bool _onlyUsedAgain(CacheObject stored, CacheObject next) =>
      next.id == stored.id &&
      next.relativePath == stored.relativePath &&
      next.validTill == stored.validTill &&
      next.length == stored.length &&
      DateTime.now().difference(stored.touched!) < const Duration(hours: 1);

  @override
  Future<int> delete(int id) async => _retired ? 0 : await super.delete(id);

  @override
  Future<int> deleteAll(Iterable<int> ids) async =>
      _retired ? 0 : await super.deleteAll(ids);
}
