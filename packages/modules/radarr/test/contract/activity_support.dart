// What the activity and manual import tests (T070) share, and what they expect
// of the module (T073, `lib/src/adapters/activity.dart`). They go through the
// module's capabilities only, so there is no further API:
//
//   QueueProvider    every member
//   HistoryProvider  every member; `history(target:)` stays as it is
//
// Each is what `ServarrClient` of `package:servarr` does, with Radarr's mapping
// of a manual import:
//
//   match: the movie of a record, `movie.id`; none where the server cannot
//          match the file. No episode ids.
//   ids:   `movieId`, the id of the candidate's `matchedRef`.
//
// Radarr throws for a candidate without a movie: `POST manualimport` answers
// 404 "Movie with ID 0 does not exist", and the `ManualImport` command is
// accepted with a 201 and then fails. So `reprocess` and `importFiles` refuse,
// with `Validation`, any list that holds a candidate without `matchedRef`,
// whatever its `rawJson` names, and write nothing.
//
// Fixtures: recorded from a throwaway Radarr 7.0.3.10918 of the dev stack's
// image with qBittorrent as download client, releases pushed to the server and,
// where a download was to be complete, its data put in place beforehand; passed
// through tool/sanitize_fixture.dart in one run. In the order they were made:
// the queue, the candidates (a download of two files of movie 1, and one that
// matches no movie), the choices, the reprocessing of the first two with the
// first corrected to WEBDL-1080p and German, the import of the first, and then,
// after further actions, the history and the blocklist. The bodies that answer
// the other writes hold nothing, so they are given here as they were seen.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:radarr/radarr_module.dart';

import 'library_support.dart';

/// The download of two files, both matched to movie 1.
String get matchedDownload =>
    records(fixture('manualimport')).first['downloadId']! as String;

/// The download that matches no movie.
String get unmatchedDownload =>
    records(fixture('manualimport_unmatched')).single['downloadId']! as String;

/// The records of a recorded page.
List<Map<String, Object?>> pageRecords(String name) =>
    records((fixture(name)! as Map<String, Object?>)['records']);

/// A queue entry that waits for a manual import.
QueueItem waiting(String? downloadId) => QueueItem(
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

/// Radarr's queue, history, blocklist and manual import, answering from the
/// recordings. [answers] and [down] replace them, as in [FakeRadarr].
class ActivityRadarr extends FakeRadarr {
  /// Answers every write instead; reads are answered as recorded.
  Result<ServiceResponse, HttpError>? writesFail;

  /// The requests that change something.
  List<ServiceRequest> get writes => [
    for (final request in requests)
      if (request.method != HttpMethod.get) request,
  ];

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    final replaced =
        down ??
        (request.method == HttpMethod.get ? null : writesFail) ??
        answers[request.path];
    return replaced ??
        _recorded(request) ??
        failedAnswer(const NotFound(), status: 404);
  }

  Result<ServiceResponse, HttpError>? _recorded(ServiceRequest request) {
    final path = request.path.replaceFirst('api/v3/', '');
    final read = request.method == HttpMethod.get;
    final post = request.method == HttpMethod.post;
    final delete = request.method == HttpMethod.delete;
    if (read) {
      switch (path) {
        case 'queue':
          return jsonAnswer(fixture('queue_activity'));
        case 'history':
          return jsonAnswer(fixture('history_activity'));
        case 'history/since' || 'qualitydefinition' || 'language':
          return jsonAnswer(fixture(path.replaceAll('/', '_')));
        case 'blocklist':
          return jsonAnswer(fixture('blocklist'));
        case 'manualimport':
          final download = request.query['downloadId']?.single;
          if (download == matchedDownload) {
            return jsonAnswer(fixture('manualimport'));
          }
          if (download == unmatchedDownload) {
            return jsonAnswer(fixture('manualimport_unmatched'));
          }
      }
    } else if (post) {
      if (path == 'manualimport') {
        return jsonAnswer(fixture('manualimport_reprocess'));
      }
      if (path == 'command') {
        return Ok(
          ServiceResponse(
            statusCode: 201,
            bytes: utf8.encode(jsonEncode(fixture('command_manualimport'))),
            headers: const {
              'content-type': ['application/json; charset=utf-8'],
            },
          ),
        );
      }
      if (path.startsWith('queue/grab/') ||
          path.startsWith('history/failed/')) {
        return textAnswer('{}');
      }
    } else if (delete) {
      if (path == 'queue/bulk' || path == 'blocklist/bulk') {
        return textAnswer('{}');
      }
      if (path.startsWith('queue/') || path.startsWith('blocklist/')) {
        return textAnswer('');
      }
    }
    return null;
  }
}

/// The module's activity capabilities for one instance of [server], behind the
/// Radarr allow-list. Create it inside the test.
class Activity {
  Activity() : this._(ActivityRadarr());

  Activity._(this.server) : _harness = Harness(server);

  final ActivityRadarr server;
  final Harness _harness;

  QueueProvider get queue =>
      RadarrModule().capability<QueueProvider>(_harness.context)!;

  HistoryProvider get history => _harness.history;
}

/// What a request with a JSON body sends.
Object? sent(ServiceRequest request) => (request.body! as JsonBody).value;
