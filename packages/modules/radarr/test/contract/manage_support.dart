// What the release, command, monitor, edit and delete tests (T086) share, and
// what they expect of the module (T089, lib/src/adapters/manage.dart).
//
// Everything is reached through `RadarrModule`, so how the adapters are laid out
// is free:
//
// - `capabilitiesFor` includes `CapabilityKind.release` and `.command`, and
//   `capability<ReleaseProvider>` and `capability<CommandProvider>` are built.
// - `LibraryProvider.setMonitored`, `applyMonitorOption`, `edit`, `bulkEdit`,
//   `delete` and `deleteFile` work. Radarr has no monitoring option.
// - A target is a movie of this instance, without a season. Anything else, and
//   any monitoring option, fails with `Validation` and sends nothing; in a list,
//   one such target stops the whole of it.
// - Nothing is sent unless asked for, a write is sent once, and a failure of
//   `http.send` is returned unchanged.
// - The answers to `delete` and `deleteFile` are empty and are not read.
// - A movie that was deleted leaves the cache.
//
// Fixtures (test/fixtures/7.0.3.10918/manage_*.json): recorded on 2026-11-26
// from a further throwaway Radarr 7.0.3.10918 in the dev stack's image, with a
// made-up Torznab and Newznab indexer serving the releases, a custom format
// that scores `PROPER` and no download client, and passed through
// tool/sanitize_fixture.dart. Three public titles were added; the first got a
// small made-up file, which a rescan imported.
//
//   manage_movie          `GET movie/1`: monitored, released, with that file
//   manage_releases       `GET release?movieId=1`, every one of them rejected
//   manage_releases_unmatched
//                         the same from another such server, whose indexer
//                         gave a release of another film: `downloadAllowed` is
//                         false and no movie is named
//   manage_command_search, _refresh, _rescan
//                         `POST command`, answered with 201
//   manage_command_status `GET command/9`, the search after it ended
//
// Seen on that server, and given by the tests as it was:
// - `POST release` without a download client answers 500.
// - Of the unmatched release, `POST release` with its guid and indexer alone
//   answers 404, "Unable to find matching movie"; with `movieId` as well it gets
//   as far as the download client.
// - `PUT movie/{id}` answers 202 with the movie, `PUT movie/editor` 200 with
//   the movies.
// - `DELETE movie/{id}` and `DELETE moviefile/{id}` answer 200 with nothing, and
//   404 for what is gone.
// - `addImportExclusion=true` adds the exclusion shortly after the answer.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import 'library_support.dart';

/// A success with [status] and [body], which is sent as it stands.
Result<ServiceResponse, HttpError> reply(String body, {int status = 200}) => Ok(
  ServiceResponse(
    statusCode: status,
    bytes: utf8.encode(body),
    headers: const {
      'content-type': ['application/json; charset=utf-8'],
    },
  ),
);

/// A success with [status] and [value] as JSON.
Result<ServiceResponse, HttpError> replyJson(
  Object? value, {
  int status = 200,
}) => reply(jsonEncode(value), status: status);

/// A fresh copy of the recorded object [name].
Map<String, Object?> manageObject(String name) =>
    fixture(name)! as Map<String, Object?>;

/// A Radarr that answers by method and path, such as `GET movie/1`, from
/// [routes], and anything else with a 404. The library's [FakeRadarr] answers a
/// path alike whatever the method.
class ManageRadarr extends FakeRadarr {
  /// The answers, by method and path below `api/v3/`.
  final routes = <String, Result<ServiceResponse, HttpError>>{};

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    return down ??
        routes[asked(request)] ??
        failedAnswer(const NotFound(), status: 404);
  }
}

/// [request] as a key of [ManageRadarr.routes].
String asked(ServiceRequest request) =>
    '${request.method.name.toUpperCase()} '
    '${request.path.replaceFirst('api/v3/', '')}';

/// What [request] sends, as the server would read it.
Object? sentBody(ServiceRequest request) =>
    jsonDecode(jsonEncode((request.body! as JsonBody).value));

/// A [Harness] whose server answers by method.
class ManageHarness extends Harness {
  ManageHarness() : super(ManageRadarr());

  ManageRadarr get radarr => server as ManageRadarr;

  /// What was asked, as keys of [ManageRadarr.routes].
  List<String> get sent => [
    for (final request in server.requests) asked(request),
  ];

  ReleaseProvider get releases =>
      RadarrModule().capability<ReleaseProvider>(context) ??
      (throw TestFailure('Radarr has no ReleaseProvider'));

  CommandProvider get commands =>
      RadarrModule().capability<CommandProvider>(context) ??
      (throw TestFailure('Radarr has no CommandProvider'));
}

/// What is no movie of this instance, where only an item is named.
const foreignRefs = <String, ItemRef>{
  'a series': ItemRef(
    instanceId: instanceId,
    kind: MediaKind.series,
    remoteId: 1,
  ),
  'a movie of another instance': ItemRef(
    instanceId: 'i2',
    kind: MediaKind.movie,
    remoteId: 1,
  ),
};

/// Targets Radarr has nothing for.
final foreignTargets = <String, MediaTarget>{
  for (final MapEntry(:key, :value) in foreignRefs.entries)
    key: MediaTarget(value),
  'a season': MediaTarget(movieRef(1), seasonNumber: 1),
};

/// The failures a write can meet, as the core client classifies them.
const writeFailures = <(ServiceFailure, int?)>[
  (Unreachable(), null),
  (AuthFailed(), 401),
  (Forbidden(), 403),
  (NotFound(), 404),
  (Conflict(), 409),
  (Validation(['Example']), 400),
  (ServerError(), 500),
  (OutcomeUnknown(), null),
];
