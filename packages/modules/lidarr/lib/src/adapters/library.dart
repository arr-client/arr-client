/// Lidarr's library.
library;

import 'dart:convert';

import 'package:core/core.dart';

import '../api/lidarr_api.dart';
import '../models/json_fields.dart';
import '../models/library_record.dart';
import '../models/media_record.dart';
import 'manage.dart';
import 'monitor_options.dart';

/// Artists, their albums and the albums' tracks, with the writes of
/// [LidarrLibraryWrites].
///
/// The state of an item depends on the download queue, so [list], [item] and
/// [children] read it too. If that read fails they fail and leave the cache as
/// it was: a queued album would otherwise be shown, and cached, as missing.
/// An item the server no longer has is removed from the cache.
///
/// A track is read and cached only as a child of its album.
final class LidarrLibraryAdapter implements LibraryProvider {
  /// Reads with [_api] into [_cache].
  LidarrLibraryAdapter(this._api, this._cache)
    : _writes = LidarrLibraryWrites(_api, _cache);

  final LidarrApi _api;
  final CacheScope _cache;
  final LidarrLibraryWrites _writes;

  @override
  MediaKind get itemKind => MediaKind.artist;

  @override
  List<MonitorOption> get monitorOptions => lidarrMonitorOptions;

  @override
  ServiceResult<List<LibraryItem>> list() async {
    final List<JsonObject> records;
    switch (await _api.artists()) {
      case Ok(:final value):
        records = value;
      case Err(:final error):
        return Err(error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    final downloading = {for (final item in queue) ?item.parent?.remoteId};
    return _reading(() async {
      final now = DateTime.now().toUtc();
      final items = <LibraryItem>[];
      final entries = <CacheEntry>[];
      for (final record in records) {
        final (artist, entry) = _artist(
          record,
          downloading: downloading.contains(record['id']),
          now: now,
        );
        items.add(artist);
        entries.add(entry);
      }
      await _cache.replace(MediaKind.artist, entries);
      return items;
    });
  }

  @override
  ServiceResult<LibraryItem> item(ItemRef ref) => switch (ref.kind) {
    MediaKind.artist => _oneArtist(ref),
    MediaKind.album => _oneAlbum(ref),
    _ => throw _notOfThisRead(ref),
  };

  /// The albums of an artist, or the tracks of an album.
  @override
  ServiceResult<List<LibraryItem>> children(ItemRef parent) =>
      switch (parent.kind) {
        MediaKind.artist => _albums(parent),
        MediaKind.album => _tracks(parent),
        _ => throw _notOfThisRead(parent),
      };

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedList() => _reading(() async {
    final snapshot = await _cache.read(MediaKind.artist);
    if (snapshot == null) return null;
    return Cached([
      for (final entry in snapshot.entries) _cachedArtist(entry),
    ], fetchedAt: snapshot.fetchedAt);
  });

  @override
  ServiceResult<Cached<LibraryItem>?> cachedItem(ItemRef ref) {
    if (ref.kind != MediaKind.artist && ref.kind != MediaKind.album) {
      throw _notOfThisRead(ref);
    }
    return _reading(() async {
      final entry = await _cache.entry(ref.kind, ref.remoteId);
      if (entry == null) return null;
      return Cached(
        entry.kind == MediaKind.artist
            ? _cachedArtist(entry)
            : _cachedAlbum(entry),
        fetchedAt: entry.fetchedAt,
      );
    });
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedChildren(ItemRef parent) {
    final kind = switch (parent.kind) {
      MediaKind.artist => MediaKind.album,
      MediaKind.album => MediaKind.track,
      _ => throw _notOfThisRead(parent),
    };
    return _reading(() async {
      final snapshot = await _cache.read(kind, parentRemoteId: parent.remoteId);
      if (snapshot == null) return null;
      final List<LibraryItem> items;
      if (kind == MediaKind.album) {
        items = [for (final entry in snapshot.entries) _cachedAlbum(entry)];
      } else {
        // The cached records of tracks do not name their album.
        final album = await _cache.entry(MediaKind.album, parent.remoteId);
        final title = album == null
            ? null
            : optionalText(_decode(album), 'title');
        items = [
          for (final entry in snapshot.entries)
            _cachedTrack(entry, parent, title),
        ];
      }
      return Cached(items, fetchedAt: snapshot.fetchedAt);
    });
  }

  @override
  ServiceResult<List<MediaFile>> files(ItemRef ref) {
    final read = switch (ref.kind) {
      MediaKind.artist => _api.artistFiles,
      MediaKind.album => _api.albumFiles,
      _ => throw _notOfThisRead(ref),
    };
    return _files(ref, read(ref.remoteId));
  }

  @override
  ServiceResult<List<ServerOption>> options() async {
    final result = await _api.options();
    if (result case Ok(:final value)) await _cache.replaceOptions(value);
    return result;
  }

  @override
  ServiceResult<Cached<List<ServerOption>>?> cachedOptions() async =>
      Ok(await _cache.readOptions());

  /// Lidarr provides no credits.
  @override
  ServiceResult<List<Credit>> credits(ItemRef ref) async => const Ok([]);

  @override
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored) =>
      _writes.setMonitored(target, monitored);

  @override
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) =>
      _writes.applyMonitorOption(ref, optionId);

  @override
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) =>
      _writes.edit(ref, changes);

  @override
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) =>
      _writes.bulkEdit(refs, changes);

  @override
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) => _writes.delete(
    ref,
    deleteFiles: deleteFiles,
    addImportExclusion: addImportExclusion,
  );

  @override
  ServiceResult<void> deleteFile(MediaFile file) => _writes.deleteFile(file);

  @override
  ModuleRoute detailRoute(ItemRef ref) => throw UnimplementedError('T118');

  ServiceResult<List<MediaFile>> _files(
    ItemRef ref,
    ServiceResult<List<JsonObject>> answer,
  ) async => switch (await answer) {
    Ok(:final value) => _reading(() async => value.map(readFile).toList()),
    Err(:final error) => _gone(ref, error),
  };

  ServiceResult<LibraryItem> _oneArtist(ItemRef ref) async {
    final JsonObject record;
    switch (await _api.artist(ref.remoteId)) {
      case Ok(:final value):
        record = value;
      case Err(:final error):
        return _gone(ref, error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    return _reading(() async {
      final (artist, entry) = _artist(
        record,
        downloading: queue.any((item) => item.parent == ref),
        now: DateTime.now().toUtc(),
      );
      await _cache.put(entry);
      return artist;
    });
  }

  ServiceResult<LibraryItem> _oneAlbum(ItemRef ref) async {
    final JsonObject record;
    switch (await _api.album(ref.remoteId)) {
      case Ok(:final value):
        record = value;
      case Err(:final error):
        return _gone(ref, error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    return _reading(() async {
      final (album, entry) = _album(
        record,
        artistName: embeddedArtistName(record),
        downloading: queue.any((item) => item.itemRef == ref),
        now: DateTime.now().toUtc(),
      );
      await _cache.put(entry);
      return album;
    });
  }

  ServiceResult<List<LibraryItem>> _albums(ItemRef parent) async {
    final id = parent.remoteId;
    final List<JsonObject> records;
    switch (await _api.albums(id)) {
      case Ok(:final value):
        records = value;
      case Err(:final error):
        return Err(error);
    }
    // After the albums: an artist that is gone gets an empty list of them, and
    // only this read says that it is gone.
    final JsonObject artist;
    switch (await _api.artist(id)) {
      case Ok(:final value):
        artist = value;
      case Err(:final error):
        return _gone(parent, error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    final downloading = {for (final item in queue) ?item.itemRef?.remoteId};
    return _reading(() async {
      final now = DateTime.now().toUtc();
      final (read, artistEntry) = _artist(
        artist,
        downloading: queue.any((item) => item.parent == parent),
        now: now,
      );
      final items = <LibraryItem>[];
      final entries = <CacheEntry>[];
      for (final record in records) {
        final (album, entry) = _album(
          record,
          artistName: read.title,
          downloading: downloading.contains(record['id']),
          now: now,
        );
        items.add(album);
        entries.add(entry);
      }
      await _cache.put(artistEntry);
      await _cache.replace(MediaKind.album, entries, parentRemoteId: id);
      return items;
    });
  }

  ServiceResult<List<LibraryItem>> _tracks(ItemRef parent) async {
    final id = parent.remoteId;
    final List<JsonObject> records;
    switch (await _api.tracks(id)) {
      case Ok(:final value):
        records = value;
      case Err(:final error):
        return Err(error);
    }
    // After the tracks, as for the albums of an artist. It also says whether
    // they are wanted.
    final JsonObject album;
    switch (await _api.album(id)) {
      case Ok(:final value):
        album = value;
      case Err(:final error):
        return _gone(parent, error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    final queued = queue.any((item) => item.itemRef == parent);
    return _reading(() async {
      final now = DateTime.now().toUtc();
      // Kept with its tracks, whose cached records do not name it.
      final (read, albumEntry) = _album(
        album,
        artistName: embeddedArtistName(album),
        downloading: queued,
        now: now,
      );
      final items = <LibraryItem>[];
      final entries = <CacheEntry>[];
      for (final record in records) {
        final track = readTrack(
          record,
          ref: _api.trackRef(requireInt(record, 'id')),
          album: parent,
          albumTitle: read.title,
          monitored: read.monitored,
          state: trackState(
            record,
            album: album,
            albumQueued: queued,
            now: now,
          ),
        );
        items.add(track);
        entries.add(_entry(track, record, now: now));
      }
      await _cache.put(albumEntry);
      await _cache.replace(MediaKind.track, entries, parentRemoteId: id);
      return items;
    });
  }

  /// The queue, for the states of items.
  ServiceResult<List<QueueItem>> _queue() async => switch (await _api.queue()) {
    // NotFound would say that the item asked for is gone.
    Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
    final result => result,
  };

  /// An artist and what the cache keeps of it.
  (Artist, CacheEntry) _artist(
    JsonObject record, {
    required bool downloading,
    required DateTime now,
  }) {
    final artist = readArtist(
      record,
      _api.artistRef(requireInt(record, 'id')),
      containerState(record, downloading: downloading),
    );
    return (artist, _entry(artist, record, now: now));
  }

  /// An album and what the cache keeps of it.
  (Album, CacheEntry) _album(
    JsonObject record, {
    required String? artistName,
    required bool downloading,
    required DateTime now,
  }) {
    final album = readAlbum(
      record,
      ref: _api.albumRef(requireInt(record, 'id')),
      artist: _api.artistRef(requireInt(record, 'artistId')),
      artistName: artistName,
      state: containerState(record, downloading: downloading),
    );
    return (album, _entry(album, record, now: now));
  }

  CacheEntry _entry(
    LibraryItem item,
    JsonObject record, {
    required DateTime now,
  }) => CacheEntry(
    instanceId: item.ref.instanceId,
    kind: item.ref.kind,
    remoteId: item.ref.remoteId,
    parentRemoteId: item.parent?.remoteId,
    sortTitle: item.sortTitle,
    state: item.state,
    monitored: item.monitored,
    qualityProfileId: item.qualityProfileId,
    tagIds: item.tagIds.toList(),
    addedAt: item.addedAt,
    rawJson: jsonEncode(record),
    fetchedAt: now,
  );

  // The state is the one found when fetched: the queue is not cached.
  Artist _cachedArtist(CacheEntry entry) =>
      readArtist(_decode(entry), _api.artistRef(entry.remoteId), entry.state);

  Album _cachedAlbum(CacheEntry entry) {
    final record = _decode(entry);
    return readAlbum(
      record,
      ref: _api.albumRef(entry.remoteId),
      artist: _api.artistRef(
        entry.parentRemoteId ?? requireInt(record, 'artistId'),
      ),
      artistName: embeddedArtistName(record),
      state: entry.state,
    );
  }

  // Whether it is monitored is its album's, as found when fetched.
  Track _cachedTrack(CacheEntry entry, ItemRef album, String? albumTitle) =>
      readTrack(
        _decode(entry),
        ref: _api.trackRef(entry.remoteId),
        album: album,
        albumTitle: albumTitle,
        monitored: entry.monitored,
        state: entry.state,
      );

  JsonObject _decode(CacheEntry entry) => asObject(jsonDecode(entry.rawJson));

  /// A failed read of [ref], which leaves the cache if it no longer exists.
  Future<Result<T, ServiceFailure>> _gone<T>(
    ItemRef ref,
    ServiceFailure failure,
  ) async {
    if (failure is NotFound) await _cache.remove(ref.kind, ref.remoteId);
    return Err(failure);
  }
}

ArgumentError _notOfThisRead(ItemRef ref) =>
    ArgumentError.value(ref.kind, 'kind', 'not an item of this read');

/// What [read] makes of records, which may be of a shape it cannot understand.
Future<Result<T, ServiceFailure>> _reading<T>(Future<T> Function() read) async {
  try {
    return Ok(await read());
  } on FormatException {
    // The exception may quote a record, so it goes no further.
    return const Err(MalformedResponse());
  }
}
