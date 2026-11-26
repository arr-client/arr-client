// What the activity and manual import tests (T071) share. They run through
// `SonarrModule().capability<T>`, so they fix what the module does and not how
// it is divided up (T074): `QueueProvider` and `HistoryProvider` are complete,
// bound to the shared Servarr client.
//
// How Sonarr names the match of a manual import record:
//   matchedRef  the series of `series.id`, or of `seriesId` where, as in the
//               answer to a reprocessing, there is no `series`
//   episodeIds  the id of each of `episodes`; none where the field is left out
// and how a candidate's match is sent back:
//   seriesId      from matchedRef
//   seasonNumber  from rawJson, if it has one
//   episodeIds    from the candidate
//
// A candidate without a series or without episodes is never sent: `reprocess`
// and `importFiles` give `Validation` and write nothing, whatever else is in
// the list. Of the recorded server, a reprocessing without a series is answered
// with 404 "Series with ID 0 does not exist" and the import command fails with
// the same exception; with a series and no episodes the command logs an
// exception, imports nothing and still reports success.
//
// The `activity_*` fixtures were recorded in a later run than those of
// support.dart, from the same version, with qBittorrent as download client,
// releases pushed to the server and their data put in place, and passed
// through tool/sanitize_fixture.dart. All but one queue entry and two grabs of
// a season pack were cut from the queue and the histories before that. The
// reprocessing was asked to correct the first file to episode 21, Bluray-1080p
// and German. The bodies that answer the other writes are given as seen, but
// that of a grab, which was only seen to be refused. Written by hand: a file
// of two episodes, and the failures of the writes.

import 'dart:convert';

import 'package:core/core.dart';

import 'support.dart';

/// The recorded downloads.
const unmatchedDownload = 'ABCDEF0000000000000000000000000000000001';
const noEpisodesDownload = 'ABCDEF0000000000000000000000000000000003';
const pairDownload = 'ABCDEF0000000000000000000000000000000004';

const _manualImports = {
  unmatchedDownload: 'activity_manualimport_unmatched',
  noEpisodesDownload: 'activity_manualimport_no_episodes',
  pairDownload: 'activity_manualimport',
};

/// A [FakeSonarr] that also answers activity and manual import, from lists a
/// test may change, and takes their writes.
class ActivityServer extends FakeSonarr {
  ActivityServer() {
    queue
      ..clear()
      ..addAll(pageRecords('activity_queue'));
  }

  /// The overall history, newest first.
  final events = pageRecords('activity_history');

  /// What `history/since` answers, oldest first as the server sends it.
  final eventsAfter = records('activity_history_since');

  final blocked = pageRecords('activity_blocklist');

  /// If set, every write gets this.
  Result<ServiceResponse, HttpError>? writeAnswer;

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final path = request.path.replaceFirst('api/v3/', '');
    final answer = request.method == HttpMethod.get
        ? _read(path, request.query)
        : writeAnswer ?? _written(request.method, path);
    if (answer == null) return super.send(request);
    requests.add(request);
    return always ?? overrides[path] ?? answer;
  }

  Result<ServiceResponse, HttpError>? _read(
    String path,
    Map<String, List<String>> query,
  ) => switch (path) {
    // The history of one episode is support.dart's.
    'history' when !query.containsKey('episodeId') => _page(events, query),
    'history/since' => _json(eventsAfter),
    'blocklist' => _page(blocked, query),
    'manualimport' => _json(
      switch (_manualImports[query['downloadId']?.single]) {
        final name? => records(name),
        null => const <Object>[],
      },
    ),
    'qualitydefinition' => _json(records('activity_qualitydefinition')),
    'language' => _json(records('activity_language')),
    _ => null,
  };

  Result<ServiceResponse, HttpError>? _written(HttpMethod method, String path) {
    if (method == HttpMethod.delete) {
      if (path == 'queue/bulk') return FakeSonarr.body('{}', write: true);
      if (RegExp(r'^(queue/\d+|blocklist/(\d+|bulk))$').hasMatch(path)) {
        return FakeSonarr.body('', write: true);
      }
    }
    if (method == HttpMethod.post) {
      if (RegExp(r'^(queue/grab|history/failed)/\d+$').hasMatch(path)) {
        return FakeSonarr.body('{}', write: true);
      }
      if (path == 'manualimport') {
        return _json(records('activity_manualimport_reprocess'));
      }
      if (path == 'command') {
        return _json(record('activity_command_manualimport'), status: 201);
      }
    }
    return null;
  }

  Result<ServiceResponse, HttpError> _page(
    List<Map<String, Object?>> all,
    Map<String, List<String>> query,
  ) {
    final page = int.parse(query['page']?.single ?? '1');
    final size = int.parse(query['pageSize']?.single ?? '10');
    return _json({
      'page': page,
      'pageSize': size,
      'totalRecords': all.length,
      'records': all.skip((page - 1) * size).take(size).toList(),
    });
  }

  Result<ServiceResponse, HttpError> _json(Object? json, {int status = 200}) =>
      FakeSonarr.body(jsonEncode(json), status: status);
}

/// The module against an [ActivityServer].
class ActivityHarness extends Harness {
  ActivityHarness() : this._(ActivityServer());

  ActivityHarness._(this.activity) : super(server: activity);

  final ActivityServer activity;

  /// The requests, each as its method and path.
  List<String> get asked => [
    for (final request in activity.requests)
      '${request.method.name} ${request.path}',
  ];
}

/// How a request appears in [ActivityHarness.asked].
String line(HttpMethod method, String path) => '${method.name} api/v3/$path';

/// The body of [request] as the server would receive it.
Object? sentBody(ServiceRequest request) =>
    jsonDecode(jsonEncode((request.body! as JsonBody).value));
