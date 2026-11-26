/// The test of a connection against a server on the loopback interface, with
/// the real modules.
library;

import 'dart:io';

import 'package:arr_client/app/navigation/router_app_navigator.dart';
import 'package:arr_client/features/onboarding/connection_tester.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbittorrent/qbittorrent_module.dart';
import 'package:radarr/radarr_module.dart';

import '../../app/support.dart';

const key = 'zq-key-0123456789';

void main() {
  late HttpServer server;
  late int port;
  late AppDatabase database;
  late ArtworkCache artwork;
  late DiagnosticLog log;
  final requests = <(String, HttpHeaders)>[];
  late Future<void> Function(HttpRequest) answer;

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      requests.add((request.uri.path, request.headers));
      await answer(request);
      await request.response.close();
    });
    database = AppDatabase(NativeDatabase.memory());
    artwork = ArtworkCache(
      directory: () async => Directory('build/test-cache'),
      loadRemote: () => false,
    );
    log = DiagnosticLog();
  });

  tearDown(() async {
    await server.close(force: true);
    await artwork.close();
    await database.close();
  });

  Future<Result<ProbeResult, ServiceFailure>> run(
    ServiceModule module,
    AuthKind authKind,
    Credential credential, {
    LocalNetworkPermission? permission,
  }) => ConnectionTest(
    module: module,
    input: ConnectionInput(
      url: Uri.parse('http://127.0.0.1:$port/sub'),
      authKind: authKind,
      credential: credential,
    ),
    log: log,
    localNetwork: permission ?? FakePermission(),
    artwork: artwork,
    cache: CacheRepository(database),
    navigator: RouterAppNavigator(),
  ).run(() async => true);

  ServiceFailure failureOf(Result<ProbeResult, ServiceFailure> result) =>
      (result as Err<ProbeResult, ServiceFailure>).error;

  void json(HttpRequest request, String body) => request.response
    ..headers.contentType = ContentType.json
    ..write(body);

  test('sends the API key under the sub-path and reads the version', () async {
    answer = (request) async =>
        json(request, '{"appName":"Radarr","version":"5.6.0.1"}');

    final result = await run(
      RadarrModule(),
      AuthKind.apiKey,
      const Credential(apiKey: key),
    );

    expect(
      (result as Ok<ProbeResult, ServiceFailure>).value.version,
      '5.6.0.1',
    );
    expect(requests.single.$1, '/sub/api/v3/system/status');
    expect(requests.single.$2.value('x-api-key'), key);
  });

  test('a refused key, another service and a web page differ', () async {
    const credential = Credential(apiKey: key);
    Future<ServiceFailure> test() async =>
        failureOf(await run(RadarrModule(), AuthKind.apiKey, credential));

    answer = (request) async => request.response.statusCode = 401;
    expect(await test(), isA<AuthFailed>());

    answer = (request) async =>
        json(request, '{"appName":"Sonarr","version":"4.0.0.0"}');
    expect(await test(), isA<WrongService>());

    answer = (request) async => request.response
      ..headers.contentType = ContentType.html
      ..write('<html>Sign in</html>');
    expect(await test(), isA<ProxyInterception>());

    await server.close(force: true);
    expect(await test(), isA<Unreachable>());
  });

  test('signs in once and probes with the session', () async {
    answer = (request) async {
      if (request.uri.path.endsWith('/auth/login')) {
        request.response.headers.add('set-cookie', 'SID=abc123; HttpOnly');
        request.response.write('Ok.');
      } else {
        request.response.write('v5.3.1');
      }
    };

    final result = await run(
      QbittorrentModule(),
      AuthKind.userPassword,
      const Credential(username: 'admin', password: 'zq-pass-123456'),
    );

    expect(result, isA<Ok<ProbeResult, ServiceFailure>>());
    expect(
      [for (final (path, _) in requests) path],
      ['/sub/api/v2/auth/login', '/sub/api/v2/app/version'],
    );
    expect(requests.last.$2.value('cookie'), 'SID=abc123');
  });

  test('a refused sign-in sends nothing more', () async {
    answer = (request) async => request.response.write('Fails.');

    final result = await run(
      QbittorrentModule(),
      AuthKind.userPassword,
      const Credential(username: 'admin', password: 'zq-wrong-123456'),
    );

    expect(failureOf(result), isA<AuthFailed>());
    expect(requests, hasLength(1));
  });

  const account = Credential(username: 'admin', password: 'zq-pass-123456');

  // The sign-in is a POST, whose outcome the core calls unknown here. A test
  // changes nothing on the server, so it must not say that it may have.
  for (final status in [502, 504]) {
    test('a gateway error $status on sign-in is a server error', () async {
      answer = (request) async => request.response.statusCode = status;

      final result = await run(
        QbittorrentModule(),
        AuthKind.userPassword,
        account,
      );

      expect(
        failureOf(result),
        isA<ServerError>().having((e) => e.statusCode, 'statusCode', status),
      );
      expect(requests, hasLength(1));
    });
  }

  for (final MapEntry(key: name, value: reply) in {
    'dropped': '',
    'not HTTP': 'SSH-2.0-OpenSSH_9.9\r\n',
  }.entries) {
    test('a sign-in answered $name is no answer', () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      raw.listen((socket) async {
        await socket.first;
        socket.write(reply);
        await socket.flush();
        socket.destroy();
      });
      port = raw.port;

      final result = await run(
        QbittorrentModule(),
        AuthKind.userPassword,
        account,
      );

      expect(failureOf(result), isA<Unreachable>());
    });
  }

  test('neither key nor password reaches the log', () async {
    answer = (request) async => request.response.statusCode = 500;

    await run(RadarrModule(), AuthKind.apiKey, const Credential(apiKey: key));

    expect(log.entries, isNotEmpty);
    expect(
      log.entries.map((entry) => entry.message).join(),
      isNot(contains(key)),
    );
  });
}
