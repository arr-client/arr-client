import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/radarr_api.dart';

/// The overall history, the history of single movies and the blocklist.
final class RadarrHistoryAdapter implements HistoryProvider {
  /// Reads and writes through [_api].
  RadarrHistoryAdapter(this._api);

  final RadarrApi _api;

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) async {
    if (target == null) return _api.shared.history(page: page);
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
  ServiceResult<void> markFailed(int eventId) =>
      _api.shared.markFailed(eventId);

  @override
  ServiceResult<List<HistoryEvent>> eventsSince(DateTime since) =>
      _api.shared.eventsSince(since);

  @override
  ServiceResult<ResultPage<BlocklistEntry>> blocklist({int page = 1}) =>
      _api.shared.blocklist(page: page);

  @override
  ServiceResult<void> unblock(List<int> entryIds) =>
      _api.shared.unblock(entryIds);
}

/// The download queue and manual import.
///
/// Radarr fails on a file without a movie, so [reprocess] and [importFiles]
/// write nothing and give [Validation] if any candidate has no `matchedRef`.
final class RadarrQueueAdapter implements QueueProvider {
  /// Reads and writes through [_api].
  RadarrQueueAdapter(this._api);

  final RadarrApi _api;

  @override
  ServiceResult<List<QueueItem>> queue() => _api.queue();

  @override
  ServiceResult<void> remove(int queueId, RemoveOptions options) =>
      _api.shared.remove(queueId, options);

  @override
  ServiceResult<void> removeMany(List<int> queueIds, RemoveOptions options) =>
      _api.shared.removeMany(queueIds, options);

  @override
  ServiceResult<void> grabNow(int queueId) => _api.shared.grabNow(queueId);

  @override
  ServiceResult<List<ManualImportCandidate>> importCandidates(QueueItem item) =>
      _api.shared.importCandidates(item, mapping: _importMapping);

  @override
  ServiceResult<ImportChoices> importChoices() => _api.shared.importChoices();

  @override
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates,
  ) async => _allHaveMovies(candidates)
      ? await _api.shared.reprocess(candidates, mapping: _importMapping)
      : const Err(Validation([]));

  @override
  ServiceResult<Command> importFiles(
    List<ManualImportCandidate> candidates,
  ) async => _allHaveMovies(candidates)
      ? await _api.shared.importFiles(candidates, mapping: _importMapping)
      : const Err(Validation([]));

  static bool _allHaveMovies(List<ManualImportCandidate> candidates) =>
      candidates.every((candidate) => candidate.matchedRef != null);

  ServarrImportMapping get _importMapping => (
    match: (record) => (
      item: switch (record['movie']) {
        // The ref the queue would give a record of this movie.
        {'id': final int id} => _api.shared.refs({'movieId': id}).item,
        _ => null,
      },
      episodeIds: const [],
    ),
    ids: (candidate) => {'movieId': ?candidate.matchedRef?.remoteId},
  );
}
