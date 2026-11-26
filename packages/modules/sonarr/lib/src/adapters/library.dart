/// Sonarr's library reads, the history of its items and its queue.
///
/// Operations that change something, and the routes to screens, are not built
/// yet; calling one is a programming error.
library;

import 'dart:convert';

import 'package:core/core.dart';

import '../api/sonarr_api.dart';
import '../models/episode_record.dart';
import '../models/json_fields.dart';
import '../models/media_record.dart';
import '../models/series_record.dart';

/// Series and their episodes.
///
/// The state of an item depends on the download queue, so [list], [item] and
/// [children] read it too. If that read fails they fail and leave the cache as
/// it was: a queued episode would otherwise be shown, and cached, as missing.
/// An item the server no longer has is removed from the cache.
final class SonarrLibraryAdapter implements LibraryProvider {
  /// Reads with [_api] into [_cache].
  SonarrLibraryAdapter(this._api, this._cache);

  final SonarrApi _api;
  final CacheScope _cache;

  @override
  MediaKind get itemKind => MediaKind.series;

  @override
  List<MonitorOption> get monitorOptions => const [];

  @override
  ServiceResult<List<LibraryItem>> list() async {
    final List<JsonObject> records;
    switch (await _api.allSeries()) {
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
        final (series, entry) = _series(
          record,
          downloading: downloading.contains(record['id']),
          now: now,
        );
        items.add(series);
        entries.add(entry);
      }
      await _cache.replace(MediaKind.series, entries);
      return items;
    });
  }

  @override
  ServiceResult<LibraryItem> item(ItemRef ref) => switch (ref.kind) {
    MediaKind.series => _oneSeries(ref),
    MediaKind.episode => _oneEpisode(ref),
    _ => throw _notOfSonarr(ref),
  };

  /// The episodes of a series.
  @override
  ServiceResult<List<LibraryItem>> children(ItemRef parent) async {
    if (parent.kind != MediaKind.series) throw _notOfSonarr(parent);
    final id = parent.remoteId;
    final List<JsonObject> records;
    switch (await _api.episodes(id)) {
      case Ok(:final value):
        records = value;
      case Err(:final error):
        return Err(error);
    }
    // After the episodes: a series that is gone gets an empty list of them,
    // and only this read says that it is gone.
    final JsonObject series;
    switch (await _api.series(id)) {
      case Ok(:final value):
        series = value;
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
      // Kept with its episodes, whose cached records do not name it.
      final (read, seriesEntry) = _series(
        series,
        downloading: queue.any((item) => item.parent == parent),
        now: now,
      );
      final items = <LibraryItem>[];
      final entries = <CacheEntry>[];
      for (final record in records) {
        final (episode, entry) = _episode(
          record,
          series: parent,
          seriesTitle: read.title,
          downloading: downloading.contains(record['id']),
          now: now,
        );
        items.add(episode);
        entries.add(entry);
      }
      await _cache.put(seriesEntry);
      await _cache.replace(MediaKind.episode, entries, parentRemoteId: id);
      return items;
    });
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedList() => _reading(() async {
    final snapshot = await _cache.read(MediaKind.series);
    if (snapshot == null) return null;
    return Cached([
      for (final entry in snapshot.entries) _cachedSeries(entry),
    ], fetchedAt: snapshot.fetchedAt);
  });

  @override
  ServiceResult<Cached<LibraryItem>?> cachedItem(ItemRef ref) {
    if (ref.kind != MediaKind.series && ref.kind != MediaKind.episode) {
      throw _notOfSonarr(ref);
    }
    return _reading(() async {
      final entry = await _cache.entry(ref.kind, ref.remoteId);
      if (entry == null) return null;
      final LibraryItem item;
      if (entry.kind == MediaKind.series) {
        item = _cachedSeries(entry);
      } else {
        final record = _decode(entry);
        item = _cachedEpisode(
          entry,
          record,
          // One read on its own has its series embedded.
          switch (record['series']) {
            {'title': final String title} => title,
            _ => await _cachedTitle(entry.parentRemoteId),
          },
        );
      }
      return Cached(item, fetchedAt: entry.fetchedAt);
    });
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedChildren(ItemRef parent) {
    if (parent.kind != MediaKind.series) throw _notOfSonarr(parent);
    return _reading(() async {
      final snapshot = await _cache.read(
        MediaKind.episode,
        parentRemoteId: parent.remoteId,
      );
      if (snapshot == null) return null;
      final title = await _cachedTitle(parent.remoteId);
      return Cached([
        for (final entry in snapshot.entries)
          _cachedEpisode(entry, _decode(entry), title),
      ], fetchedAt: snapshot.fetchedAt);
    });
  }

  @override
  ServiceResult<List<MediaFile>> files(ItemRef ref) async {
    switch (ref.kind) {
      case MediaKind.series:
        return switch (await _api.episodeFiles(ref.remoteId)) {
          Ok(:final value) => _reading(
            () async => value.map(readFile).toList(),
          ),
          Err(:final error) => _gone(ref, error),
        };
      case MediaKind.episode:
        return switch (await _api.episode(ref.remoteId)) {
          Ok(:final value) => _reading(
            () async => [
              if (value['episodeFile'] case final JsonObject file)
                readFile(file),
            ],
          ),
          Err(:final error) => _gone(ref, error),
        };
      default:
        throw _notOfSonarr(ref);
    }
  }

  @override
  ServiceResult<List<ServerOption>> options() => _api.options();

  /// Sonarr provides no cast.
  @override
  ServiceResult<List<Credit>> credits(ItemRef ref) async => const Ok([]);

  @override
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored) =>
      throw UnimplementedError();

  @override
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) =>
      throw UnimplementedError();

  @override
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) =>
      throw UnimplementedError();

  @override
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) =>
      throw UnimplementedError();

  @override
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) => throw UnimplementedError();

  @override
  ServiceResult<void> deleteFile(MediaFile file) => throw UnimplementedError();

  @override
  ModuleRoute detailRoute(ItemRef ref) => throw UnimplementedError();

  ServiceResult<LibraryItem> _oneSeries(ItemRef ref) async {
    final JsonObject record;
    switch (await _api.series(ref.remoteId)) {
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
      final (series, entry) = _series(
        record,
        downloading: queue.any((item) => item.parent == ref),
        now: DateTime.now().toUtc(),
      );
      await _cache.put(entry);
      return series;
    });
  }

  ServiceResult<LibraryItem> _oneEpisode(ItemRef ref) async {
    final JsonObject record;
    switch (await _api.episode(ref.remoteId)) {
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
      final (episode, entry) = _episode(
        record,
        series: _api.seriesRef(requireInt(record, 'seriesId')),
        seriesTitle: switch (record['series']) {
          {'title': final String title} => title,
          _ => null,
        },
        downloading: queue.any((item) => item.itemRef == ref),
        now: DateTime.now().toUtc(),
      );
      await _cache.put(entry);
      return episode;
    });
  }

  /// The queue, for the states of items.
  ServiceResult<List<QueueItem>> _queue() async => switch (await _api.queue()) {
    // NotFound would say that the item asked for is gone.
    Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
    final result => result,
  };

  /// A series and what the cache keeps of it.
  (Series, CacheEntry) _series(
    JsonObject record, {
    required bool downloading,
    required DateTime now,
  }) {
    final id = requireInt(record, 'id');
    final series = readSeries(
      record,
      _api.seriesRef(id),
      seriesState(record, downloading: downloading),
    );
    return (series, _entry(series, record, now: now));
  }

  /// An episode and what the cache keeps of it.
  (Episode, CacheEntry) _episode(
    JsonObject record, {
    required ItemRef series,
    required String? seriesTitle,
    required bool downloading,
    required DateTime now,
  }) {
    final episode = readEpisode(
      record,
      ref: _api.episodeRef(requireInt(record, 'id')),
      series: series,
      seriesTitle: seriesTitle,
      state: episodeState(record, downloading: downloading, now: now),
    );
    return (episode, _entry(episode, record, now: now));
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
  Series _cachedSeries(CacheEntry entry) =>
      readSeries(_decode(entry), _api.seriesRef(entry.remoteId), entry.state);

  Episode _cachedEpisode(
    CacheEntry entry,
    JsonObject record,
    String? seriesTitle,
  ) => readEpisode(
    record,
    ref: _api.episodeRef(entry.remoteId),
    series: _api.seriesRef(
      entry.parentRemoteId ?? requireInt(record, 'seriesId'),
    ),
    seriesTitle: seriesTitle,
    state: entry.state,
  );

  Future<String?> _cachedTitle(int? seriesId) async {
    if (seriesId == null) return null;
    final entry = await _cache.entry(MediaKind.series, seriesId);
    return entry == null ? null : optionalText(_decode(entry), 'title');
  }

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

/// The history of a series, a season or an episode. The overall history and
/// the history actions are not built yet.
final class SonarrHistoryAdapter implements HistoryProvider {
  /// Reads with [_api].
  SonarrHistoryAdapter(this._api);

  final SonarrApi _api;

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) async {
    if (target == null) throw UnimplementedError();
    final ref = target.item;
    switch (ref.kind) {
      case MediaKind.episode:
        return _api.episodeHistory(ref.remoteId, page: page);
      case MediaKind.series:
        // Sonarr gives the history of a series whole, as the first page.
        if (page != 1) {
          return Ok(ResultPage(items: const [], page: page, hasMore: false));
        }
        final result = await _api.seriesHistory(
          ref.remoteId,
          seasonNumber: target.seasonNumber,
        );
        return switch (result) {
          Ok(:final value) => Ok(
            ResultPage(items: value, page: page, hasMore: false),
          ),
          Err(:final error) => Err(error),
        };
      default:
        throw _notOfSonarr(ref);
    }
  }

  @override
  ServiceResult<void> markFailed(int eventId) => throw UnimplementedError();

  @override
  ServiceResult<List<HistoryEvent>> eventsSince(DateTime since) =>
      throw UnimplementedError();

  @override
  ServiceResult<ResultPage<BlocklistEntry>> blocklist({int page = 1}) =>
      throw UnimplementedError();

  @override
  ServiceResult<void> unblock(List<int> entryIds) => throw UnimplementedError();
}

/// The download queue.
final class SonarrQueueAdapter implements QueueProvider {
  /// Reads with [_api].
  SonarrQueueAdapter(this._api);

  final SonarrApi _api;

  @override
  ServiceResult<List<QueueItem>> queue() => _api.queue();

  @override
  ServiceResult<void> remove(int queueId, RemoveOptions options) =>
      throw UnimplementedError();

  @override
  ServiceResult<void> removeMany(List<int> queueIds, RemoveOptions options) =>
      throw UnimplementedError();

  @override
  ServiceResult<void> grabNow(int queueId) => throw UnimplementedError();

  @override
  ServiceResult<List<ManualImportCandidate>> importCandidates(QueueItem item) =>
      throw UnimplementedError();

  @override
  ServiceResult<ImportChoices> importChoices() => throw UnimplementedError();

  @override
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates,
  ) => throw UnimplementedError();

  @override
  ServiceResult<Command> importFiles(List<ManualImportCandidate> candidates) =>
      throw UnimplementedError();
}

ArgumentError _notOfSonarr(ItemRef ref) =>
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
