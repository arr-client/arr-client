// A Prowlarr that answers from recorded responses, and what the contract tests
// need to talk to it through the module.
//
// test/fixtures/3.1.0.5799/ was recorded on 2026-11-26 from a throwaway
// Prowlarr 3.1.0.5799 in the dev stack's image, and passed through
// tool/sanitize_fixture.dart, so titles, names, messages, paths and addresses
// are placeholders. It had a made-up Torznab indexer (id 1) and Newznab indexer
// (id 2), served by a web server beside it, and a torrent blackhole as its
// download client.
//
//   system_status, indexer, indexer_categories
//   search              `GET search` for a term, one category, both indexers:
//                       two torrents of indexer 1, one Usenet of indexer 2
//   indexerstatus       after indexer 2 failed a search
//   health              the same, after a health check
//   grab                `POST search`, accepted: 200 and a bare release
//   grab_expired        404, a release the server no longer remembers (it
//                       keeps them for 30 minutes)
//   grab_indexer_failed 409, the indexer did not give the download
//   grab_no_client      500, no download client for the protocol
//   grab_invalid        400, a body without guid and indexer
//   search_unavailable  400, every indexer asked for is unavailable
//
// Seen on that server, and not visible in the sanitized files:
// - `GET search` answers with the indexers' own addresses, their passkeys
//   included, in `guid`, `infoUrl` and `commentUrl`, and with Prowlarr's own
//   API key in `downloadUrl` and `magnetUrl` (its download proxy).
// - The answer to a grab repeats the `guid`.
// - A rejected key gets 401 with no body, and `api/v3/...` 404.
// - An indexer that fails a search is left out of the results without a word.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prowlarr/prowlarr_module.dart';

import '../allow_list.dart';

const instanceId = 'i1';

/// A fresh copy of a recording, free to be changed by the test.
Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/3.1.0.5799/$name.json').readAsStringSync());

List<Map<String, Object?>> records(Object? list) =>
    (list! as List<Object?>).cast<Map<String, Object?>>().toList();

ServiceResponse response(int status, String body, {String? type}) =>
    ServiceResponse(
      statusCode: status,
      bytes: utf8.encode(body),
      headers: {
        if (type != null) 'content-type': [type],
      },
    );

const _jsonType = 'application/json; charset=utf-8';

/// A success whose body is [body] as it stands.
Result<ServiceResponse, HttpError> textAnswer(String body) =>
    Ok(response(200, body, type: _jsonType));

Result<ServiceResponse, HttpError> jsonAnswer(Object? value) =>
    textAnswer(jsonEncode(value));

/// What the core client returns for a request that did not succeed.
Result<ServiceResponse, HttpError> failedAnswer(
  ServiceFailure failure, {
  int? status,
  String body = '',
  String? type,
}) => Err(
  HttpError(
    failure,
    response: status == null ? null : response(status, body, type: type),
  ),
);

/// Prowlarr, as far as the module needs it. A success is [Ok] and anything
/// else a classified [Err], as `ServiceHttpClient` says.
class FakeProwlarr implements ServiceHttpClient {
  FakeProwlarr() {
    for (final (route, name) in const [
      ('GET system/status', 'system_status'),
      ('GET health', 'health'),
      ('GET indexer', 'indexer'),
      ('GET indexer/categories', 'indexer_categories'),
      ('GET indexerstatus', 'indexerstatus'),
      ('GET search', 'search'),
      ('POST search', 'grab'),
    ]) {
      routes[route] = jsonAnswer(fixture(name));
    }
  }

  /// The answers, by method and path below `api/v1/`.
  final routes = <String, Result<ServiceResponse, HttpError>>{};

  /// Answers every request instead, as when the server cannot be reached.
  Result<ServiceResponse, HttpError>? down;

  /// What was asked.
  final requests = <ServiceRequest>[];

  /// [requests] as `GET indexer`.
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

/// `GET indexer` for a request.
String asked(ServiceRequest request) =>
    '${request.method.name.toUpperCase()} '
    '${request.path.replaceFirst('api/v1/', '')}';

/// The JSON a request sends, as it would arrive.
Object? sentBody(ServiceRequest request) =>
    jsonDecode(jsonEncode((request.body! as JsonBody).value));

/// Keeps all that is written to the diagnostic log.
class RecordingLogger implements Logger {
  final lines = <String>[];

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => lines.add('$message $error $stackTrace');
}

/// Counts every use of the instance's cache, which is what a module can
/// persist through, and refuses it.
class UnusedCache implements CacheScope {
  final used = <String>[];

  @override
  Object? noSuchMethod(Invocation invocation) {
    used.add('${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

/// The module's capabilities for one instance of [server], behind the Prowlarr
/// allow-list. Create it inside the test.
class Harness {
  Harness({FakeProwlarr? server}) : server = server ?? FakeProwlarr() {
    context = InstanceContext(
      instance: Instance(
        id: instanceId,
        profileId: 'p1',
        name: 'Home',
        serviceType: 'prowlarr',
        url: Uri.parse('http://server.test/prowlarr'),
        authKind: AuthKind.apiKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      http: AllowListClient(allowList, this.server),
      artwork: _FakeArtwork(),
      navigator: _FakeNavigator(),
      cache: cache,
      logger: logger,
    );
  }

  final FakeProwlarr server;
  final cache = UnusedCache();
  final logger = RecordingLogger();
  late final InstanceContext context;

  IndexerSearchProvider get indexers =>
      ProwlarrModule().capability<IndexerSearchProvider>(context) ??
      (throw TestFailure('Prowlarr has no IndexerSearchProvider'));

  HealthProvider get health =>
      ProwlarrModule().capability<HealthProvider>(context) ??
      (throw TestFailure('Prowlarr has no HealthProvider'));
}

/// The value of an operation that must succeed.
Future<T> succeed<T>(ServiceResult<T> operation) async =>
    switch (await operation) {
      Ok(:final value) => value,
      Err(:final error) => fail('Expected success, got $error'),
    };

/// The failure of an operation that must fail.
Future<ServiceFailure> failureOf<T>(ServiceResult<T> operation) async =>
    switch (await operation) {
      Ok() => fail('Expected a failure'),
      Err(:final error) => error,
    };
