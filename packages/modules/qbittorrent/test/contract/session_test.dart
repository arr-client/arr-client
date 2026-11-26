// The module inside the core's InstanceSession (T028), against a server on the
// loopback interface that answers as qBittorrent was recorded to: what is
// really sent, and that a rejection latches the instance with no retry.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbittorrent/qbittorrent_module.dart';

import '../allow_list.dart';
import 'support.dart';

const _user = 'zq-user';
const _password = 'zq-pass';
const _apiKey = 'qbt_zqzqzqzqzqzqzqzqzqzqzqzqzqzq';
const _account = Credential(username: _user, password: _password);

typedef _Received = ({
  String method,
  String path,
  Map<String, String> headers,
  String body,
});

/// A qBittorrent of one version with one account and one API key.
class _Server {
  _Server._(this.version, this._server);

  static Future<_Server> start(String version) async {
    final server = _Server._(
      version,
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._answer);
    return server;
  }

  final String version;
  final HttpServer _server;
  final requests = <_Received>[];
  final sessions = <String>{};
  var banned = false;
  var _issued = 0;

  bool get _is52 => version == '5.3.1';

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  List<_Received> get logins => [
    for (final request in requests)
      if (request.path == '/api/v2/auth/login') request,
  ];

  Future<void> close() => _server.close(force: true);

  Future<void> _answer(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    final received = (
      method: request.method,
      path: request.uri.path,
      headers: headers,
      body: await utf8.decodeStream(request),
    );
    requests.add(received);

    final response = request.response;
    final (status, body) = _decide(received, response.headers);
    response.statusCode = status;
    if (body.isNotEmpty) {
      response.headers.set(
        'content-type',
        body.startsWith('[') ? 'application/json' : textType,
      );
      response.write(body);
    }
    await response.close();
  }

  (int, String) _decide(_Received request, HttpHeaders headers) {
    final authorization = request.headers['authorization'];
    final basic = authorization?.startsWith('Basic ') ?? false;
    final login = request.path == '/api/v2/auth/login';
    if (banned) {
      return (403, login ? fixture(version, 'login_banned.txt') : 'Forbidden');
    }
    if (login) {
      final form = Uri.splitQueryString(request.body);
      final right = form['username'] == _user && form['password'] == _password;
      // 5.2 reads a basic header as its own login before anything else.
      if (_is52 && (!right || basic)) return (401, 'Unauthorized');
      if (!right) return (200, fixture(version, 'login_wrong.txt'));
      final name = _is52 ? 'QBT_SID_8080' : 'SID';
      final session = '$name=zq-session-${++_issued}';
      sessions.add(session);
      headers.add('set-cookie', '$session; HttpOnly; path=/');
      return _is52 ? (204, '') : (200, fixture(version, 'login_ok.txt'));
    }
    final signedIn =
        authorization == 'Bearer $_apiKey' ||
        sessions.contains(request.headers['cookie']);
    if (!signedIn) return (403, fixture(version, 'forbidden.txt'));
    return switch (request.path) {
      '/api/v2/app/version' => (200, fixture(version, 'app_version.txt')),
      '/api/v2/app/webapiVersion' => (
        200,
        fixture(version, 'app_webapi_version.txt'),
      ),
      '/api/v2/torrents/info' => (200, fixture(version, 'torrents_info.json')),
      _ => (404, 'Not Found'),
    };
  }
}

/// Checks the login too, which the session sends past the context's client.
class _CheckedHandler implements SessionHandler {
  _CheckedHandler(this._inner);

  final SessionHandler _inner;

  @override
  ServiceResult<String> login({
    required AuthKind authKind,
    required Credential credential,
    required ServiceHttpClient http,
  }) => _inner.login(
    authKind: authKind,
    credential: credential,
    http: AllowListClient(allowList, http),
  );

  @override
  bool isSessionExpired(ServiceResponse response) =>
      _inner.isSessionExpired(response);
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

/// A saved instance of [server] and the module working in its session.
class _Setup {
  _Setup._(
    this.module,
    this.server,
    this.profiles,
    this.instance,
    this.session,
  );

  static Future<_Setup> start(
    String version, {
    AuthKind authKind = AuthKind.userPassword,
    Credential credential = _account,
  }) async {
    final module = QbittorrentModule();
    final server = await _Server.start(version);
    addTearDown(server.close);
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
      _draft(server.url, authKind),
      credential: credential,
    );
    final instance = (added as Ok<Instance, RuleViolation>).value;
    final session = InstanceSession(
      profiles: profiles,
      instanceId: instance.id,
      handler: _CheckedHandler(module.sessionHandler!),
      apiKeyHeader: module.descriptor.apiKeyHeader,
      log: log,
      localNetwork: _NoPermissionNeeded(),
      timeout: const Duration(seconds: 10),
    );
    addTearDown(session.close);
    return _Setup._(module, server, profiles, instance, session);
  }

  final QbittorrentModule module;
  final _Server server;
  final ProfileRepository profiles;
  final Instance instance;
  final InstanceSession session;

  InstanceContext get _context =>
      context(session, instance: instance, session: session);

  Future<Result<ProbeResult, ServiceFailure>> probe() => module.probe(_context);

  Future<Result<List<DownloadProgress>, ServiceFailure>> progress() =>
      module.capability<DownloadProgressProvider>(_context)!.progress();

  Future<bool> latched() async =>
      (await profiles.instance(instance.id))!.authFailed;
}

InstanceDraft _draft(Uri url, AuthKind authKind) => InstanceDraft(
  name: 'Downloads',
  serviceType: 'qbittorrent',
  url: url,
  authKind: authKind,
);

/// Nothing the app sends may name where it came from (upstream-apis.md).
void _expectNoOriginSent(_Server server) {
  expect(server.requests, isNotEmpty);
  for (final request in server.requests) {
    expect(request.headers, isNot(contains('origin')), reason: request.path);
    expect(request.headers, isNot(contains('referer')), reason: request.path);
  }
}

/// The rejection latched the instance after the [sent] requests, and nothing
/// follows them.
Future<void> _expectLatched(_Setup setup, {required int sent}) async {
  expect(await setup.latched(), isTrue);
  expect(setup.server.requests, hasLength(sent));

  expect(failureOf(await setup.probe()), isA<AuthFailed>());
  expect(failureOf(await setup.progress()), isA<AuthFailed>());

  expect(setup.server.requests, hasLength(sent));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('user name and password', () {
    for (final version in versions) {
      test('signs in once and reads $version', () async {
        final setup = await _Setup.start(version);

        expect(valueOf(await setup.probe()).version, version);
        expect(valueOf(await setup.progress()), hasLength(6));

        expect(setup.server.logins, hasLength(1));
        for (final request in setup.server.requests) {
          expect(request.headers, isNot(contains('authorization')));
          if (request.path != '/api/v2/auth/login') {
            expect(request.method, 'GET');
            expect(request.headers['cookie'], isNotNull);
          }
        }
        _expectNoOriginSent(setup.server);
      });

      test('latches on a wrong password for $version', () async {
        final setup = await _Setup.start(
          version,
          credential: const Credential(username: _user, password: 'wrong'),
        );

        expect(failureOf(await setup.probe()), isA<AuthFailed>());

        await _expectLatched(setup, sent: 1);
      });

      test('latches on the ban of $version', () async {
        final setup = await _Setup.start(version);
        setup.server.banned = true;

        expect(failureOf(await setup.progress()), isA<AuthFailed>());

        await _expectLatched(setup, sent: 1);
      });
    }

    test('signs in again once when the session has ended', () async {
      final setup = await _Setup.start('5.3.1');
      valueOf(await setup.progress());
      setup.server.sessions.clear();

      expect(valueOf(await setup.progress()), hasLength(6));

      expect(setup.server.logins, hasLength(2));
      expect(setup.server.requests, hasLength(5));
      expect(await setup.latched(), isFalse);
    });
  });

  group('API key', () {
    const credential = Credential(apiKey: _apiKey);

    test('is sent as a bearer token, without the auth endpoints', () async {
      final setup = await _Setup.start(
        '5.3.1',
        authKind: AuthKind.apiKey,
        credential: credential,
      );

      valueOf(await setup.probe());
      expect(valueOf(await setup.progress()), hasLength(6));

      expect(setup.server.logins, isEmpty);
      for (final request in setup.server.requests) {
        expect(request.method, 'GET');
        expect(request.path, isNot(contains('/auth/')));
        expect(request.headers['authorization'], 'Bearer $_apiKey');
        expect(request.headers, isNot(contains('cookie')));
      }
      _expectNoOriginSent(setup.server);
    });

    // data-model.md Instance.authFailed: set by any rejected token. qBittorrent
    // rejects one with a 403, which the core client calls Forbidden, so the
    // core has to be told that this 403 is a rejection.
    test('latches when it is wrong', () async {
      final setup = await _Setup.start(
        '5.3.1',
        authKind: AuthKind.apiKey,
        credential: const Credential(apiKey: 'qbt_replaced'),
      );

      expect(failureOf(await setup.progress()), isA<AuthFailed>());

      await _expectLatched(setup, sent: 1);
    });

    // Both go in the Authorization header.
    test('cannot be saved with basic authentication', () async {
      final setup = await _Setup.start(
        '5.3.1',
        authKind: AuthKind.apiKey,
        credential: credential,
      );

      final result = await setup.profiles.updateInstance(
        setup.instance.id,
        _draft(setup.server.url, AuthKind.apiKey),
        credential: const Credential(
          apiKey: _apiKey,
          basicUser: 'proxy',
          basicPassword: 'zq-proxy',
        ),
      );

      expect(
        result,
        isA<Err<Instance, RuleViolation>>().having(
          (err) => err.error,
          'error',
          RuleViolation.basicAuthWithApiKey,
        ),
      );
    });
  });

  group('basic authentication with a login', () {
    const credential = Credential(
      username: _user,
      password: _password,
      basicUser: 'proxy',
      basicPassword: 'zq-proxy',
    );

    test('works before 5.2, which ignores the header', () async {
      final setup = await _Setup.start('5.1.4', credential: credential);

      expect(valueOf(await setup.progress()), hasLength(6));
    });

    // The header reached qBittorrent and counts towards a ban.
    test('is not retried when 5.2 refuses it', () async {
      final setup = await _Setup.start('5.3.1', credential: credential);

      expect(failureOf(await setup.progress()), isAuthFailedWithHint);
      expect(
        setup.server.logins.single.headers['authorization'],
        startsWith('Basic '),
      );

      await _expectLatched(setup, sent: 1);
    });
  });
}
