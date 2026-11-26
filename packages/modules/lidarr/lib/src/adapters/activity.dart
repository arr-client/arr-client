/// Lidarr's queue, history, blocklist and manual import. All of it is the
/// shared Servarr client's but the history of one item and how a file is
/// matched to an artist, an album, a release of it and tracks.
library;

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/lidarr_api.dart';
import '../models/json_fields.dart';

/// The download queue and manual import.
final class LidarrQueueAdapter implements QueueProvider {
  /// Reads and writes with [_api].
  LidarrQueueAdapter(this._api);

  final LidarrApi _api;

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

  /// A candidate without an artist is [Validation], and then nothing is
  /// written. Lidarr identifies the tracks of a file again, so those of the
  /// answer may not be those sent.
  @override
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates,
  ) async {
    if (!candidates.every((candidate) => candidate.matchedRef != null)) {
      return const Err(Validation([]));
    }
    return _api.shared.reprocess(candidates, mapping: _mapping);
  }

  /// A candidate without an artist, an album, tracks and a release of that
  /// album is [Validation], and then nothing is written. Only the server
  /// chooses a release, so a newly chosen album takes a [reprocess] first.
  ///
  /// The files the album has are never replaced.
  @override
  ServiceResult<Command> importFiles(
    List<ManualImportCandidate> candidates,
  ) async {
    if (!candidates.every(_isComplete)) return const Err(Validation([]));
    return _api.shared.importFiles(candidates, mapping: _mapping);
  }

  bool _isComplete(ManualImportCandidate candidate) =>
      candidate.matchedRef != null &&
      candidate.albumId != null &&
      candidate.trackIds.isNotEmpty &&
      _releaseId(candidate) != null;

  /// The release the server gave for the artist and album now chosen. One it
  /// gave for another album is not one of this album. Zero is none.
  int? _releaseId(ManualImportCandidate candidate) {
    final record = candidate.rawJson;
    final isOfMatch =
        objectIn(record, 'album')['id'] == candidate.albumId &&
        objectIn(record, 'artist')['id'] == candidate.matchedRef?.remoteId;
    return isOfMatch ? optionalPositive(record, 'albumReleaseId') : null;
  }

  ServarrImportMapping get _mapping => (match: _match, ids: _ids);

  ServarrMatch _match(JsonObject record) {
    final artistId = optionalPositive(objectIn(record, 'artist'), 'id');
    return (
      item: artistId == null ? null : _api.artistRef(artistId),
      episodeIds: const [],
    );
  }

  // The server throws for a release id of zero, so none is left out.
  JsonObject _ids(ManualImportCandidate candidate) => {
    'artistId': ?candidate.matchedRef?.remoteId,
    'albumId': ?candidate.albumId,
    'albumReleaseId': ?_releaseId(candidate),
    'trackIds': candidate.trackIds,
  };
}

/// The history, overall or of an artist or an album, and the blocklist.
final class LidarrHistoryAdapter implements HistoryProvider {
  /// Reads and writes with [_api].
  LidarrHistoryAdapter(this._api);

  final LidarrApi _api;

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) async {
    if (target == null) return _api.shared.history(page: page);
    final ref = target.item;
    if (ref.instanceId == _api.instanceId && target.seasonNumber == null) {
      switch (ref.kind) {
        case MediaKind.album:
          return _api.albumHistory(ref.remoteId, page: page);
        case MediaKind.artist:
          // Lidarr gives the history of an artist whole, as the first page.
          if (page != 1) {
            return Ok(ResultPage(items: const [], page: page, hasMore: false));
          }
          return switch (await _api.artistHistory(ref.remoteId)) {
            Ok(:final value) => Ok(
              ResultPage(items: value, page: page, hasMore: false),
            ),
            Err(:final error) => Err(error),
          };
        default:
      }
    }
    throw ArgumentError.value(ref.kind, 'kind', 'not an item of this read');
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
