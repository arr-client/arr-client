/// Sonarr's queue, history, blocklist and manual import. All of it is the
/// shared Servarr client's but the history of one item and how a file is
/// matched to a series and its episodes.
library;

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/sonarr_api.dart';
import '../models/json_fields.dart';

/// The download queue and manual import.
final class SonarrQueueAdapter implements QueueProvider {
  /// Reads and writes with [_api].
  SonarrQueueAdapter(this._api);

  final SonarrApi _api;

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
      _api.shared.importCandidates(item, mapping: _mapping);

  @override
  ServiceResult<ImportChoices> importChoices() => _api.shared.importChoices();

  /// A candidate without a series or without episodes is [Validation], and
  /// then nothing is written.
  @override
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates,
  ) async {
    if (!candidates.every(_isMatched)) return const Err(Validation([]));
    return _api.shared.reprocess(candidates, mapping: _mapping);
  }

  /// Refuses the candidates [reprocess] does.
  @override
  ServiceResult<Command> importFiles(
    List<ManualImportCandidate> candidates,
  ) async {
    if (!candidates.every(_isMatched)) return const Err(Validation([]));
    return _api.shared.importFiles(candidates, mapping: _mapping);
  }

  // The server throws for a file without a series. Without episodes it reports
  // success and imports nothing.
  bool _isMatched(ManualImportCandidate candidate) =>
      candidate.matchedRef != null && candidate.episodeIds.isNotEmpty;

  ServarrImportMapping get _mapping => (match: _match, ids: _ids);

  ServarrMatch _match(JsonObject record) {
    // The answer to a reprocessing has `seriesId` and no `series`.
    final seriesId = switch (record['series']) {
      final JsonObject series => optionalPositive(series, 'id'),
      _ => optionalPositive(record, 'seriesId'),
    };
    return (
      item: seriesId == null ? null : _api.seriesRef(seriesId),
      episodeIds: [
        if (record['episodes'] case final Object episodes)
          for (final episode in asObjects(episodes)) requireInt(episode, 'id'),
      ],
    );
  }

  // The season is the record's, which need not be that of the episodes chosen.
  // The server does not read it where it is given episodes.
  JsonObject _ids(ManualImportCandidate candidate) => {
    'seriesId': ?candidate.matchedRef?.remoteId,
    'seasonNumber': ?candidate.rawJson['seasonNumber'],
    'episodeIds': candidate.episodeIds,
  };
}

/// The history, overall or of a series, a season or an episode, and the
/// blocklist.
final class SonarrHistoryAdapter implements HistoryProvider {
  /// Reads and writes with [_api].
  SonarrHistoryAdapter(this._api);

  final SonarrApi _api;

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) async {
    if (target == null) return _api.shared.history(page: page);
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
        throw ArgumentError.value(ref.kind, 'kind', 'not an item of this read');
    }
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
