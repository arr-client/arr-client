// A Bazarr that answers from recorded responses, and what the contract tests
// need to talk to it through the module.
//
// test/fixtures/1.6.2/ (the dev stack's image) and test/fixtures/1.5.0/ (the
// minimum) were recorded on 2026-11-26 from throwaway Bazarr servers connected
// to a throwaway Sonarr 4.0.20.3014 and Radarr 7.0.3.10918 with generated video
// files, and passed through tool/sanitize_fixture.dart, so titles, messages,
// provider names, tokens and paths are placeholders. The only provider was
// "embeddedsubtitles", which reads the video's own tracks. The languages
// profile wanted en, fr, de (hearing impaired), es and it (forced).
//
//   system_status
//   series, movies            the first page, everything on it
//   series_1                  `GET series?seriesid[]=1`
//   movie_3                   `GET movies?radarrid[]=3`, with an HI file
//   movies_embedded           (1.6.2) movie 2 with embedded tracks counted:
//                             they are listed with a null path
//   episodes_series_1         `GET episodes?seriesid[]=1`
//   episode_2                 `GET episodes?episodeid[]=2`
//   episodes_wanted, movies_wanted, episodes_history, movies_history
//                             history actions: 0 deleted, 1 downloaded,
//                             2 downloaded by hand, 5 synchronized
//   providers_episodes, providers_movies
//                             manual search of episode 1 and movie 2
//   unauthorized              (1.6.2) 401, a wrong key
//   not_found                 (1.6.2) 404, a manual search of no movie
//   delete_failed             (1.6.2) 500, a path the movie does not have
//   sync_failed               (1.6.2) 500, a file that is not there
//   invalid                   (1.6.2) 400, a download without its fields
//
// Seen on those servers or in their source, and not visible in the files:
// - Any other path, `api/v3/system/status` included, answers 200 with the web
//   UI's page, which on a server without a login holds the API key.
// - Writes answer 204 with no body. 1.5.0 answers a manual download with 200
//   and `null`.
// - 1.6 queues searches, manual downloads and synchronization: it answers 204
//   before doing them, also for a movie that does not exist or a token it does
//   not know, and a failure shows in its own log only. 1.5 does them before
//   answering: 404 for no such movie, 500 for a token it cannot read.
// - A delete answers when done on both.
// - A manual search token is a short id on 1.6 and a long base64 text with line
//   breaks on 1.5.
// - Sonarr and Radarr answer `api/system/status` with 401 to a key that is not
//   theirs, and with 404 to their own.

import 'dart:convert';
import 'dart:io';

import 'package:bazarr/bazarr_module.dart';
import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

const instanceId = 'i1';

/// The minimum, and the tested version.
const versions = ['1.5.0', '1.6.2'];

const latest = '1.6.2';

/// A recorded body as it stands.
String recorded(String name, [String version = latest]) =>
    File('test/fixtures/$version/$name.json').readAsStringSync();

/// A fresh copy of a recording, free to be changed by the test.
Map<String, Object?> fixture(String name, [String version = latest]) =>
    jsonDecode(recorded(name, version)) as Map<String, Object?>;

/// The entries of a recording's `data`.
List<Map<String, Object?>> records(String name, [String version = latest]) =>
    (fixture(name, version)['data']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList();

ServiceResponse response(int status, String body, {String? type}) =>
    ServiceResponse(
      statusCode: status,
      bytes: utf8.encode(body),
      headers: {
        if (type != null) 'content-type': [type],
      },
    );

const _jsonType = 'application/json';

/// A success whose body is [body] as it stands.
Result<ServiceResponse, HttpError> textAnswer(String body) =>
    Ok(response(200, body, type: _jsonType));

Result<ServiceResponse, HttpError> jsonAnswer(Object? value) =>
    textAnswer(jsonEncode(value));

/// What an accepted write gets.
Result<ServiceResponse, HttpError> noContent() =>
    Ok(response(204, '', type: _jsonType));

/// What the core client returns for a request that did not succeed.
Result<ServiceResponse, HttpError> failedAnswer(
  ServiceFailure failure, {
  int? status,
  String body = '',
  String? type = _jsonType,
}) => Err(
  HttpError(
    failure,
    response: status == null ? null : response(status, body, type: type),
  ),
);

/// Bazarr, as far as the module needs it. A success is [Ok] and anything else a
/// classified [Err], as `ServiceHttpClient` says.
class FakeBazarr implements ServiceHttpClient {
  FakeBazarr([String version = latest]) {
    for (final (route, name) in const [
      ('GET system/status', 'system_status'),
      ('GET series', 'series'),
      ('GET movies', 'movies'),
      ('GET episodes', 'episodes_series_1'),
      ('GET episodes/wanted', 'episodes_wanted'),
      ('GET movies/wanted', 'movies_wanted'),
      ('GET episodes/history', 'episodes_history'),
      ('GET movies/history', 'movies_history'),
      ('GET providers/episodes', 'providers_episodes'),
      ('GET providers/movies', 'providers_movies'),
    ]) {
      routes[route] = jsonAnswer(fixture(name, version));
    }
    for (final route in const [
      'PATCH episodes/subtitles',
      'PATCH movies/subtitles',
      'DELETE episodes/subtitles',
      'DELETE movies/subtitles',
      'POST providers/episodes',
      'POST providers/movies',
      'PATCH subtitles',
    ]) {
      routes[route] = noContent();
    }
  }

  /// The answers, by method and path below `api/`.
  final routes = <String, Result<ServiceResponse, HttpError>>{};

  /// Answers every request instead, as when the server cannot be reached.
  Result<ServiceResponse, HttpError>? down;

  /// What was asked.
  final requests = <ServiceRequest>[];

  /// What was asked, as [asked] writes it.
  List<String> get sent => requests.map(asked).toList();

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

/// `GET movies` for a request.
String asked(ServiceRequest request) =>
    '${request.method.name.toUpperCase()} '
    '${request.path.replaceFirst('api/', '')}';

/// The query of a request, each name given once.
Map<String, String> queryOf(ServiceRequest request) => {
  for (final MapEntry(:key, :value) in request.query.entries) key: value.single,
};

/// The form a request sends.
Map<String, String> formOf(ServiceRequest request) =>
    (request.body! as FormBody).fields;

class _SilentLogger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

class _FakeCache extends Fake implements CacheScope {}

/// The module for one instance of [server], behind the Bazarr allow-list.
/// Create it inside the test.
class Harness {
  Harness([String version = latest, FakeBazarr? server])
    : server = server ?? FakeBazarr(version) {
    context = InstanceContext(
      instance: Instance(
        id: instanceId,
        profileId: 'p1',
        name: 'Home',
        serviceType: 'bazarr',
        url: Uri.parse('http://server.test/bazarr'),
        authKind: AuthKind.apiKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      http: AllowListClient(allowList, this.server),
      artwork: _FakeArtwork(),
      navigator: _FakeNavigator(),
      cache: _FakeCache(),
      logger: _SilentLogger(),
    );
  }

  final FakeBazarr server;
  late final InstanceContext context;

  SubtitleProvider get subtitles =>
      BazarrModule().capability<SubtitleProvider>(context) ??
      (throw TestFailure('Bazarr has no SubtitleProvider'));
}

/// A language as one text, such as `de:hi`.
String tag(SubtitleLanguage language) =>
    '${language.code}${language.forced ? ':forced' : ''}'
    '${language.hi ? ':hi' : ''}';

/// A recorded language object as [tag] writes it.
String wireTag(Object? wire) {
  final language = wire! as Map<String, Object?>;
  return '${language['code2']}${language['forced'] == true ? ':forced' : ''}'
      '${language['hi'] == true ? ':hi' : ''}';
}

List<String> wireTags(Object? list) =>
    (list! as List<Object?>).map(wireTag).toList();

/// The value of an operation that must succeed.
Future<T> succeed<T>(ServiceResult<T> operation) async =>
    switch (await operation) {
      Ok(:final value) => value,
      Err(:final error) => fail('Expected success, got $error'),
    };

/// Waits for a write that must succeed.
Future<void> accepted(ServiceResult<void> operation) async {
  final result = await operation;
  if (result case Err(:final error)) fail('Expected success, got $error');
}

/// The failure of an operation that must fail.
Future<ServiceFailure> failureOf<T>(ServiceResult<T> operation) async =>
    switch (await operation) {
      Ok() => fail('Expected a failure'),
      Err(:final error) => error,
    };
