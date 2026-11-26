import 'dart:convert';

import 'package:core/core.dart';

import '../api/radarr_api.dart';
import '../models/credit_record.dart';
import '../models/media_file_record.dart';
import '../models/movie_record.dart';

/// The movies of one Radarr instance.
///
/// A movie's state depends on the download queue, so [list] and [item] read it
/// too. If that read fails they fail and leave the cache as it was: a queued
/// movie would otherwise be shown, and cached, as missing.
final class RadarrLibraryAdapter implements LibraryProvider {
  /// Reads through [_api] and caches in the cache of [_context].
  RadarrLibraryAdapter(this._api, this._context);

  final RadarrApi _api;
  final InstanceContext _context;

  @override
  MediaKind get itemKind => MediaKind.movie;

  // Monitoring a movie is a toggle only.
  @override
  List<MonitorOption> get monitorOptions => const [];

  @override
  ServiceResult<List<LibraryItem>> list() async {
    final List<JsonObject> records;
    switch (await _api.movies()) {
      case Ok(:final value):
        records = value;
      case Err(:final error):
        return Err(error);
    }
    final Set<int> queued;
    switch (await _queuedMovies()) {
      case Ok(:final value):
        queued = value;
      case Err(:final error):
        return Err(error);
    }
    final fetchedAt = DateTime.now().toUtc();
    final fetched = _decode(
      () => [for (final record in records) _fetched(record, queued, fetchedAt)],
    );
    switch (fetched) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        await _context.cache.replace(MediaKind.movie, [
          for (final (_, entry) in value) entry,
        ]);
        return Ok([for (final (movie, _) in value) movie]);
    }
  }

  @override
  ServiceResult<LibraryItem> item(ItemRef ref) async {
    final JsonObject record;
    switch (await _api.movie(ref.remoteId)) {
      case Ok(:final value):
        record = value;
      case Err(:final error):
        if (error is NotFound) {
          await _context.cache.remove(MediaKind.movie, ref.remoteId);
        }
        return Err(error);
    }
    final Set<int> queued;
    switch (await _queuedMovies()) {
      case Ok(:final value):
        queued = value;
      case Err(:final error):
        return Err(error);
    }
    switch (_decode(() => _fetched(record, queued, DateTime.now().toUtc()))) {
      case Err(:final error):
        return Err(error);
      case Ok(value: (final movie, final entry)):
        await _context.cache.put(entry);
        return Ok(movie);
    }
  }

  // A movie has no children.
  @override
  ServiceResult<List<LibraryItem>> children(ItemRef parent) async =>
      const Ok([]);

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedList() async {
    final snapshot = await _context.cache.read(MediaKind.movie);
    if (snapshot == null) return const Ok(null);
    return _decode(
      () => Cached([
        for (final entry in snapshot.entries) _cached(entry),
      ], fetchedAt: snapshot.fetchedAt),
    );
  }

  @override
  ServiceResult<Cached<LibraryItem>?> cachedItem(ItemRef ref) async {
    final entry = await _context.cache.entry(MediaKind.movie, ref.remoteId);
    if (entry == null) return const Ok(null);
    return _decode(() => Cached(_cached(entry), fetchedAt: entry.fetchedAt));
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedChildren(
    ItemRef parent,
  ) async => const Ok(null);

  @override
  ServiceResult<List<MediaFile>> files(ItemRef ref) async =>
      switch (await _api.movieFiles(ref.remoteId)) {
        Ok(:final value) => _decode(() => value.map(readMediaFile).toList()),
        Err(:final error) => Err(error),
      };

  @override
  ServiceResult<List<ServerOption>> options() => _api.options();

  @override
  ServiceResult<List<Credit>> credits(ItemRef ref) async =>
      switch (await _api.credits(ref.remoteId)) {
        Ok(:final value) => _decode(() => value.map(readCredit).toList()),
        Err(:final error) => Err(error),
      };

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

  /// The movies that have a download in the queue.
  ServiceResult<Set<int>> _queuedMovies() async => switch (await _api.queue()) {
    Ok(:final value) => Ok({
      for (final download in value) ?download.itemRef?.remoteId,
    }),
    // NotFound would say that the movie asked for is gone.
    Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
    Err(:final error) => Err(error),
  };

  /// A record from the server, and what the cache keeps of it.
  (Movie, CacheEntry) _fetched(
    JsonObject record,
    Set<int> queued,
    DateTime fetchedAt,
  ) {
    final movie = readMovie(
      record,
      instanceId: _context.instance.id,
      state: movieState(record, downloading: queued.contains(record['id'])),
    );
    return (
      movie,
      CacheEntry(
        instanceId: movie.ref.instanceId,
        kind: movie.ref.kind,
        remoteId: movie.ref.remoteId,
        sortTitle: movie.sortTitle,
        state: movie.state,
        monitored: movie.monitored,
        qualityProfileId: movie.qualityProfileId,
        tagIds: movie.tagIds.toList(),
        addedAt: movie.addedAt,
        rawJson: jsonEncode(record),
        fetchedAt: fetchedAt,
      ),
    );
  }

  /// The movie of [entry], in the state it had when it was fetched.
  Movie _cached(CacheEntry entry) => switch (jsonDecode(entry.rawJson)) {
    final JsonObject record => readMovie(
      record,
      instanceId: entry.instanceId,
      state: entry.state,
    ),
    _ => throw const FormatException('Not an object'),
  };
}

/// The history of single movies. The overall history and the history actions
/// are not implemented yet.
final class RadarrHistoryAdapter implements HistoryProvider {
  /// Reads through [_api].
  RadarrHistoryAdapter(this._api);

  final RadarrApi _api;

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) async {
    if (target == null) throw UnimplementedError();
    // The server gives a movie's history whole, as the first page.
    if (page != 1) {
      return Ok(ResultPage(items: const [], page: page, hasMore: false));
    }
    return switch (await _api.movieHistory(target.item.remoteId)) {
      Ok(:final value) => Ok(
        ResultPage(items: value, page: page, hasMore: false),
      ),
      Err(:final error) => Err(error),
    };
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

/// The download queue. The queue actions and manual import are not implemented
/// yet.
final class RadarrQueueAdapter implements QueueProvider {
  /// Reads through [_api].
  RadarrQueueAdapter(this._api);

  final RadarrApi _api;

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

/// What [read] returns, or [MalformedResponse] for a record it cannot
/// understand.
Result<T, ServiceFailure> _decode<T>(T Function() read) {
  try {
    return Ok(read());
  } on FormatException {
    // The exception may quote the record, so it goes no further.
    return const Err(MalformedResponse());
  }
}
