// What the activity tests (T069) share, and the API they expect of
// `package:servarr/servarr.dart` (T072). The records are those of
// `package:core`.
//
//   /// What a manual import record is matched to. `item` is the movie, series,
//   /// artist or author; `episodeIds` is empty but for a series.
//   typedef ServarrMatch = ({ItemRef? item, List<int> episodeIds});
//
//   /// What is a service's own in a manual import.
//   typedef ServarrImportMapping = ({
//     ServarrMatch Function(JsonObject record) match,
//     JsonObject Function(ManualImportCandidate candidate) ids,
//   });
//
//   // Further members of ServarrClient:
//   ServiceResult<void> remove(int queueId, RemoveOptions options);
//   ServiceResult<void> removeMany(List<int> queueIds, RemoveOptions options);
//   ServiceResult<void> grabNow(int queueId);
//   ServiceResult<void> markFailed(int eventId);
//   ServiceResult<List<HistoryEvent>> eventsSince(DateTime since);
//   ServiceResult<ResultPage<BlocklistEntry>> blocklist({int page = 1});
//   ServiceResult<void> unblock(List<int> entryIds);
//   ServiceResult<List<ManualImportCandidate>> importCandidates(
//     QueueItem item, {
//     required ServarrImportMapping mapping,
//   });
//   ServiceResult<ImportChoices> importChoices();
//   ServiceResult<List<ManualImportCandidate>> reprocess(
//     List<ManualImportCandidate> candidates, {
//     required ServarrImportMapping mapping,
//   });
//   ServiceResult<Command> importFiles(
//     List<ManualImportCandidate> candidates, {
//     required ServarrImportMapping mapping,
//   });
//
// The constructor of ServarrClient does not change. `refs` is also given each
// record of `history/since` and `blocklist`.
//
// A write is sent once, whatever happens, and a failure of `http.send`, an
// unknown outcome included, is returned unchanged. What a successful write
// answers is not read, but for `reprocess` and `importFiles`.
//
// Fixtures of these tests: recorded in a later run than the others (see
// support.dart), from the same versions, with qBittorrent as download client,
// releases pushed to the server and a web seed for their data, and passed
// through tool/sanitize_fixture.dart. manualimport and manualimport_reprocess
// are of a further run, its downloads added to qBittorrent with their data in
// place; the corrected quality was sent as its whole definition. The bodies
// that answer a write hold nothing, so the tests give them as they were seen.

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import 'support.dart';

ItemRef itemRef(MediaKind kind, int id) =>
    ItemRef(instanceId: instanceId, kind: kind, remoteId: id);

/// A candidate names its movie or series by an object; a reprocessed Sonarr
/// candidate names its series by `seriesId` only.
ServarrImportMapping mapping(Service service) => service == radarr
    ? (
        match: (record) => (
          item: switch (record['movie']) {
            {'id': final int id} => itemRef(MediaKind.movie, id),
            _ => null,
          },
          episodeIds: const <int>[],
        ),
        ids: (candidate) => {'movieId': ?candidate.matchedRef?.remoteId},
      )
    : (
        match: (record) => (
          item: switch (record) {
            {'seriesId': final int id} ||
            {'series': {'id': final int id}} => itemRef(MediaKind.series, id),
            _ => null,
          },
          episodeIds: [
            if (record['episodes'] case final List<Object?> episodes)
              for (final episode in episodes)
                if (episode case {'id': final int id}) id,
          ],
        ),
        ids: (candidate) => {
          'seriesId': ?candidate.matchedRef?.remoteId,
          'seasonNumber': ?candidate.rawJson['seasonNumber'],
          'episodeIds': candidate.episodeIds,
        },
      );

/// Answers [path] below `api/v3/` with [reply] and anything else with a 404.
FakeServer only(String path, Reply reply) => FakeServer(
  (request) => request.path == 'api/v3/$path' ? reply : const Reply(404, ''),
);

/// A queue entry that waits for a manual import.
QueueItem waiting({String? downloadId = 'ABCDEF01'}) => QueueItem(
  id: 1,
  title: 'Some.Release-GRP',
  status: QueueStatus.completed,
  trackedState: TrackedState.importBlocked,
  severity: QueueSeverity.warning,
  progress: 1,
  sizeLeft: 0,
  protocol: DownloadProtocol.torrent,
  downloadId: downloadId,
  needsManualImport: true,
);
