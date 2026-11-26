// What the release, command, monitor, edit and delete tests (T087) share. They
// run through `SonarrModule().capability<T>`, so they fix what the module does
// and not how it is divided up (T090): `LibraryProvider`'s writes,
// `CommandProvider` and `ReleaseProvider`, bound to the shared Servarr client
// where it has the operation.
//
// What the module asks of Sonarr, below api/v3/, and nothing else:
//   releases      GET release?episodeId= for an episode,
//                 GET release?seriesId=&seasonNumber= for a season
//   grab          POST release {guid, indexerId}; for a release with
//                 `downloadAllowed` false also what its search was for,
//                 {episodeId} or {seriesId, seasonNumber}
//   search        POST command: EpisodeSearch {episodeIds}, SeasonSearch
//                 {seriesId, seasonNumber}, SeriesSearch {seriesId}
//   refresh       POST command RefreshSeries {seriesIds}, series only
//   rescan        POST command RescanSeries {seriesId}, series only
//   commandStatus GET command/{id}
//   setMonitored  series or season: GET series/{id}, PUT series/{id}
//                 episode: PUT episode/monitor {episodeIds, monitored}
//   monitor option
//                 POST seasonpass {series: [{id}], monitoringOptions: {monitor}}
//   edit          GET series/{id}, PUT series/{id}
//   bulkEdit      PUT series/editor
//   delete        DELETE series/{id}?deleteFiles=&addImportListExclusion=
//   deleteFile    DELETE episodefile/{id}
//
// A write is sent once. A target the server has no such operation for is a
// programming error: `ArgumentError`, thrown or as the future's error, with
// nothing sent. Never is it widened, say from a season to its series.
//
// A series found to be gone, by the read before an edit, by a delete or by a
// monitoring option, is `NotFound` and leaves the cache, as a deleted one does
// (story 2, scenario 6).
//
// Sonarr leaves the images of the seasons out of `GET series/{id}`, so any PUT
// of a series drops them on the server until its next refresh.
//
// The `manage_*` fixtures were recorded from another throwaway server of the
// same version and image, with two series and made-up episode files, and passed
// through tool/sanitize_fixture.dart; manage_series is the series as read
// before it was edited. The two release lists are those recorded for
// packages/servarr, from Sonarr with a made-up indexer. The answers to the
// writes are given as seen, but that of a grab, which repeats what was sent.
// A series the server does not have is answered with 500 and "Expected query to
// return 1 rows but returned 0" to a delete and to a season pass, and with 404
// to a read.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// What Sonarr says of a series it does not have, where it does not say 404.
const noSuchSeries = 'Expected query to return 1 rows but returned 0';

/// A [FakeSonarr] that also answers releases and commands, has the recorded
/// series 1 as read before an edit, and takes the writes of managing it.
class ManageServer extends FakeSonarr {
  /// What `GET series/1` answers; a test may change it.
  Map<String, Object?> item = record('manage_series');

  /// What `GET command/{id}` answers.
  Map<String, Object?> command = record('manage_command_done');

  /// If set, every write gets this.
  Result<ServiceResponse, HttpError>? writeAnswer;

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final path = request.path.replaceFirst('api/v3/', '');
    final read = request.method == HttpMethod.get;
    final answer = read
        ? overrides[path] ?? _read(path, request.query)
        : writeAnswer ?? _written(request, path);
    if (answer == null) {
      if (read) return super.send(request);
      fail('not a write of managing: ${request.method.name} $path');
    }
    requests.add(request);
    return always ?? answer;
  }

  Result<ServiceResponse, HttpError>? _read(
    String path,
    Map<String, List<String>> query,
  ) {
    if (path == 'series/1') return _json(item);
    if (path == 'release') {
      return _json(
        records(
          query.containsKey('seasonNumber')
              ? 'manage_releases_season'
              : 'manage_releases',
        ),
      );
    }
    if (path == 'command/${command['id']}') return _json(command);
    if (path == 'episodefile' && query['seriesId']?.single == '1') {
      return _json(records('manage_episodefile'));
    }
    return null;
  }

  Result<ServiceResponse, HttpError>? _written(
    ServiceRequest request,
    String path,
  ) {
    Result<ServiceResponse, HttpError> answer(String body, int status) =>
        FakeSonarr.body(body, status: status, write: true);

    switch (request.method) {
      case HttpMethod.post:
        if (path == 'release') {
          return answer(jsonEncode(sentBody(request)), 200);
        }
        if (path == 'seasonpass') return answer('{}', 202);
        if (path == 'command') {
          final name = (sentBody(request)! as Map<String, Object?>)['name'];
          return answer(jsonEncode(record(commandFixtures[name]!)), 201);
        }
      case HttpMethod.put:
        if (path == 'series/1') return answer(jsonEncode(item), 202);
        if (path == 'series/editor' || path == 'episode/monitor') {
          return answer('[]', 202);
        }
      case HttpMethod.delete:
        if (RegExp(r'^(series|episodefile)/\d+$').hasMatch(path)) {
          return answer('', 200);
        }
      default:
    }
    return null;
  }

  Result<ServiceResponse, HttpError> _json(Object? json) =>
      FakeSonarr.body(jsonEncode(json));
}

/// The recorded answer to each command.
const commandFixtures = {
  'EpisodeSearch': 'manage_command_search_episode',
  'SeasonSearch': 'manage_command_search_season',
  'SeriesSearch': 'manage_command_search_series',
  'RefreshSeries': 'manage_command_refresh',
  'RescanSeries': 'manage_command_rescan',
};

/// The module against a [ManageServer].
class ManageHarness extends Harness {
  ManageHarness() : this._(ManageServer());

  ManageHarness._(this.sonarr) : super(server: sonarr);

  final ManageServer sonarr;

  /// The requests, each as its method and path.
  List<String> get asked => [
    for (final request in sonarr.requests)
      '${request.method.name} ${request.path}',
  ];

  /// The ids of the series in the cache.
  Future<List<int>> cachedSeries() async => [
    for (final item in (await ok(library.cachedList()))!.value)
      item.ref.remoteId,
  ];
}

/// How a request appears in [ManageHarness.asked].
String line(HttpMethod method, String path) => '${method.name} api/v3/$path';

/// The body of [request] as the server would receive it.
Object? sentBody(ServiceRequest request) =>
    jsonDecode(jsonEncode((request.body! as JsonBody).value));

MediaTarget series([int id = 1]) => MediaTarget(seriesRef(id));

MediaTarget season(int number, [int id = 1]) =>
    MediaTarget(seriesRef(id), seasonNumber: number);

MediaTarget episode([int id = 31]) => MediaTarget(episodeRef(id));

/// A target that is not Sonarr's.
const movie = MediaTarget(
  ItemRef(instanceId: instanceId, kind: MediaKind.movie, remoteId: 1),
);

/// Asserts that [call] is a programming error. Nothing may have been sent,
/// which the caller checks.
Future<void> expectProgrammingError(Future<Object?> Function() call) =>
    expectLater(Future.sync(call), throwsArgumentError);

/// The failures every request can meet.
final transportFailures = <String, (Result<ServiceResponse, HttpError>, Type)>{
  'an unreachable server': (const Err(HttpError(Unreachable())), Unreachable),
  'a rejected key': (FakeSonarr.body('', status: 401), AuthFailed),
  'a refusal': (FakeSonarr.body('', status: 403), Forbidden),
  'a conflict': (FakeSonarr.body('', status: 409), Conflict),
  'rejected values': (FakeSonarr.body('[]', status: 400), Validation),
  'a server error': (
    FakeSonarr.body('{"message":"Example"}', status: 500),
    ServerError,
  ),
  'a login page': (
    FakeSonarr.body(
      '<!doctype html><title>Sign in</title>',
      contentType: 'text/html',
    ),
    ProxyInterception,
  ),
};

/// The failures of a write: those, and one that leaves it open whether the
/// server has the change.
final writeFailures = <String, (Result<ServiceResponse, HttpError>, Type)>{
  ...transportFailures,
  'an unknown outcome': (
    const Err(HttpError(OutcomeUnknown())),
    OutcomeUnknown,
  ),
};
