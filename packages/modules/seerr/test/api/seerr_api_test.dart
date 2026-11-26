// SeerrApi's writes inside the core's InstanceSession, against a server on the
// loopback interface that refuses as the servers were recorded to: what is
// latched, and what a write carries.

import 'dart:io';

import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';
import 'package:seerr/src/api/seerr_api.dart';

import '../contract/support.dart';

const _apiKey = 'zqApiKey';

class _Server {
  late final HttpServer _server;

  /// By `'METHOD /path'`: the status and body in place of the usual answer.
  final answers = <String, (int, String)>{};

  /// The API key it accepts.
  String apiKey = _apiKey;

  /// The sessions it knows.
  final sessions = <String>{};

  var csrf = false;

  var _issued = 0;

  final calls = <String>[];
  final headers = <HttpHeaders>[];

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_Server> start() async {
    final server = _Server();
    server._server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server._server.close(force: true));
    server._server.listen(server._answer);
    return server;
  }

  Future<void> _answer(HttpRequest request) async {
    await request.drain<void>();
    final route = '${request.method} ${request.uri.path}';
    calls.add(route);
    headers.add(request.headers);
    final response = request.response;
    var (status, body) = answers[route] ?? (200, '{}');
    if (route == 'POST /api/v1/auth/local') {
      final session = 'connect.sid=zqSession${++_issued}';
      sessions.add(session);
      response.headers.add('set-cookie', '$session; Path=/; HttpOnly');
    } else if (!_isPublic(request) && !_isSignedIn(request)) {
      (status, body) = (403, noPermission);
    } else if (csrf &&
        request.method != 'GET' &&
        request.headers.value('x-xsrf-token') != csrfToken) {
      (status, body) = (403, csrfRefusal);
    }
    if (csrf && request.method == 'GET') {
      response.headers
        ..add('set-cookie', secretCookie)
        ..add('set-cookie', tokenCookie);
    }
    response.statusCode = status;
    response.headers.set('content-type', jsonType);
    response.write(body);
    await response.close();
  }

  static bool _isPublic(HttpRequest request) =>
      request.uri.path == '/api/v1/settings/public';

  bool _isSignedIn(HttpRequest request) =>
      request.headers.value('x-api-key') == apiKey ||
      sessions.any(
        (session) =>
            request.headers.value('cookie')?.contains(session) ?? false,
      );
}

class _Secrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _NoPermissionNeeded implements LocalNetworkPermission {
  @override
  Future<LocalNetworkPermissionState> status(String host) async =>
      LocalNetworkPermissionState.notRequired;

  @override
  Future<LocalNetworkPermissionState> request(String host) => status(host);
}

typedef _Setup = ({SeerrApi api, Future<bool> Function() latched});

Future<_Setup> _setUp(
  _Server server, {
  AuthKind authKind = AuthKind.apiKey,
}) async {
  final module = SeerrModule();
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final log = DiagnosticLog();
  final profiles = ProfileRepository(
    database: database,
    secrets: _Secrets(),
    log: log,
    preferences: PreferencesRepository(database),
    modules: [module],
  );
  await profiles.ensureDefaultProfile();
  final added = await profiles.addInstance(
    (await profiles.profiles()).first.id,
    InstanceDraft(
      name: 'Requests',
      serviceType: 'seerr',
      url: server.url,
      authKind: authKind,
    ),
    credential: authKind == AuthKind.apiKey
        ? const Credential(apiKey: _apiKey)
        : const Credential(username: 'zq@user.test', password: 'zq-pass'),
  );
  final instance = (added as Ok<Instance, RuleViolation>).value;
  final session = InstanceSession(
    profiles: profiles,
    instanceId: instance.id,
    handler: module.sessionHandler,
    apiKeyHeader: module.descriptor.apiKeyHeader,
    log: log,
    localNetwork: _NoPermissionNeeded(),
    timeout: const Duration(seconds: 10),
  );
  addTearDown(session.close);
  return (
    api: SeerrApi(context(session, of: instance, session: session)),
    latched: () async => (await profiles.instance(instance.id))!.authFailed,
  );
}

Future<ServiceFailure> _failure(Future<Result<Object?, HttpError>> sent) async {
  final result = await sent;
  return switch (result) {
    Ok() => fail('Expected a failure'),
    Err(:final error) => error.failure,
  };
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('with an API key', () {
    test('a rejected key latches the instance', () async {
      final server = await _Server.start()
        ..apiKey = 'another';
      final setup = await _setUp(server);

      expect(
        await _failure(setup.api.read('request/count')),
        isA<AuthFailed>(),
      );

      expect(await setup.latched(), isTrue);
      expect(server.calls, [
        'GET /api/v1/request/count',
        'GET /api/v1/auth/me',
      ]);
      expect(
        await _failure(setup.api.read('request/count')),
        isA<AuthFailed>(),
      );
      expect(server.calls, hasLength(2));
    });

    for (final MapEntry(key: name, value: answer) in {
      'a refused delete': (401, fixture('delete_refused')),
      'a missing permission': (403, noPermission),
      'a used up quota': (403, fixture('request_over_quota')),
    }.entries) {
      test('$name does not latch', () async {
        final server = await _Server.start()
          ..answers['DELETE /api/v1/request/9'] = answer;
        final setup = await _setUp(server);

        expect(
          await _failure(setup.api.write(HttpMethod.delete, 'request/9')),
          isA<Forbidden>(),
        );

        expect(await setup.latched(), isFalse);
      });
    }
  });

  for (final authKind in [AuthKind.apiKey, AuthKind.userPassword]) {
    group('a write with ${authKind.name}', () {
      test('carries the CSRF token', () async {
        final server = await _Server.start()
          ..csrf = true;
        final setup = await _setUp(server, authKind: authKind);

        expect(
          await setup.api.write(HttpMethod.post, 'request/9/retry'),
          isA<Ok<ServiceResponse, HttpError>>(),
        );

        final sent = server.headers.last;
        expect(sent.value('x-xsrf-token'), csrfToken);
        expect(cookiesOf(sent.value('cookie'))['_csrf'], csrfSecret);
        expect(
          cookiesOf(sent.value('cookie'))['connect.sid'],
          authKind == AuthKind.apiKey ? isNull : 'zqSession1',
        );
      });

      test('refused for its token is writes refused', () async {
        final server = await _Server.start()
          ..answers['POST /api/v1/request/9/retry'] = (403, csrfRefusal);
        final setup = await _setUp(server, authKind: authKind);

        expect(
          await _failure(setup.api.write(HttpMethod.post, 'request/9/retry')),
          isA<WritesRefused>(),
        );

        expect(await setup.latched(), isFalse);
        expect(
          server.calls.where((call) => call.endsWith('retry')),
          hasLength(1),
        );
      });
    });
  }

  test('a write after the session ended signs in first', () async {
    final server = await _Server.start();
    final setup = await _setUp(server, authKind: AuthKind.userPassword);
    await setup.api.read('auth/me');
    server.sessions.clear();
    server.calls.clear();

    expect(
      await setup.api.write(HttpMethod.post, 'request/9/retry'),
      isA<Ok<ServiceResponse, HttpError>>(),
    );

    expect(server.calls, [
      'GET /api/v1/auth/me',
      'GET /api/v1/settings/public',
      'POST /api/v1/auth/local',
      'GET /api/v1/auth/me',
      'POST /api/v1/request/9/retry',
    ]);
  });
}
