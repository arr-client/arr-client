// The module inside the core's InstanceSession (T028), against a server on the
// loopback interface that answers as the servers were recorded to: what is
// really sent, how the cookies come back over HTTP, and when an instance is
// latched.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';

import '../allow_list.dart';
import 'support.dart';

const _user = 'zq@user.test';
const _password = 'zq-pass';
const _apiKey = 'zqApiKey';
const _account = Credential(username: _user, password: _password);

typedef _Received = ({
  String method,
  String path,
  String query,
  Map<String, String> headers,
  String body,
});

/// A Seerr with one account and one API key.
class _Server {
  _Server._(this._server, {required this.csrf});

  static Future<_Server> start({required bool csrf}) async {
    final server = _Server._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      csrf: csrf,
    );
    server._server.listen(server._answer);
    return server;
  }

  final bool csrf;
  final HttpServer _server;
  final requests = <_Received>[];
  final sessions = <String>{};
  var _issued = 0;

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  List<_Received> get logins => [
    for (final request in requests)
      if (request.path.startsWith('/api/v1/auth/') && request.method == 'POST')
        request,
  ];

  Future<void> close() => _server.close(force: true);

  Future<void> _answer(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    final received = (
      method: request.method,
      path: request.uri.path,
      query: request.uri.query,
      headers: headers,
      body: await utf8.decodeStream(request),
    );
    requests.add(received);

    final response = request.response;
    final cookies = cookiesOf(headers['cookie']);
    final refused =
        csrf &&
        received.method != 'GET' &&
        (cookies['_csrf'] != csrfSecret ||
            headers['x-xsrf-token'] != csrfToken);
    final (status, body) = refused
        ? (403, csrfRefusal)
        : _decide(received, cookies, response.headers);
    if (csrf && received.method == 'GET') {
      if (cookies['_csrf'] == null) {
        response.headers.add('set-cookie', secretCookie);
      }
      response.headers.add('set-cookie', tokenCookie);
    }
    response.statusCode = status;
    if (body.isNotEmpty) {
      response.headers.set('content-type', jsonType);
      response.write(body);
    }
    await response.close();
  }

  (int, String) _decide(
    _Received request,
    Map<String, String> cookies,
    HttpHeaders headers,
  ) {
    switch (request.path) {
      case '/api/v1/status':
        return (200, fixture('status'));
      case '/api/v1/settings/public':
        return (200, fixture('settings_public'));
      case '/api/v1/auth/local' || '/api/v1/auth/jellyfin':
        final local = request.path.endsWith('local');
        final sent = jsonDecode(request.body) as Map<String, Object?>;
        if (sent[local ? 'email' : 'username'] != _user ||
            sent['password'] != _password) {
          return local
              ? (403, fixture('auth_local_wrong'))
              : (401, fixture('auth_jellyfin_wrong'));
        }
        final session = 'zqSession${++_issued}';
        sessions.add(session);
        headers.add(
          'set-cookie',
          'connect.sid=$session; Path=/; HttpOnly; SameSite=Strict',
        );
        return (200, fixture('auth_local'));
    }
    final signedIn =
        request.headers['x-api-key'] == _apiKey ||
        sessions.contains(cookies['connect.sid']);
    if (!signedIn) {
      return cookies.containsKey('connect.sid') ||
              request.headers.containsKey('x-api-key')
          ? (403, noPermission)
          : (401, fixture('auth_me_anonymous'));
    }
    return switch ((request.method, request.path)) {
      ('GET', '/api/v1/auth/me') => (200, fixture('auth_me_member')),
      ('GET', '/api/v1/search') => (200, fixture('search')),
      ('POST', '/api/v1/request') => (201, fixture('request_created_movie')),
      // Someone else's request.
      ('DELETE', '/api/v1/request/9') => (401, fixture('delete_refused')),
      ('POST', '/api/v1/request/9/approve') => (403, noPermission),
      _ => (404, '{"message":"not found"}'),
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

  static Future<_Setup> start({
    AuthKind authKind = AuthKind.userPassword,
    Credential credential = _account,
    bool csrf = false,
  }) async {
    final module = SeerrModule();
    final server = await _Server.start(csrf: csrf);
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
      InstanceDraft(
        name: 'Requests',
        serviceType: 'seerr',
        url: server.url,
        authKind: authKind,
      ),
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

  final SeerrModule module;
  final _Server server;
  final ProfileRepository profiles;
  final Instance instance;
  final InstanceSession session;

  InstanceContext get _context =>
      context(session, of: instance, session: session);

  Future<Result<ProbeResult, ServiceFailure>> probe() => module.probe(_context);

  DiscoveryProvider get discover =>
      module.capability<DiscoveryProvider>(_context)!;

  RequestProvider get requests => module.capability<RequestProvider>(_context)!;

  Future<bool> latched() async =>
      (await profiles.instance(instance.id))!.authFailed;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final csrf in [false, true]) {
    group(csrf ? 'with CSRF protection' : 'without CSRF protection', () {
      for (final authKind in [
        AuthKind.userPassword,
        AuthKind.mediaServerAccount,
      ]) {
        test('signs in once with ${authKind.name} and writes', () async {
          final setup = await _Setup.start(authKind: authKind, csrf: csrf);

          valueOf(await setup.probe());
          valueOf(await setup.requests.request(title(), is4k: false));

          expect(setup.server.logins, hasLength(1));
          final write = setup.server.requests.last;
          expect(write.method, 'POST');
          expect(write.path, '/api/v1/request');
          final cookies = cookiesOf(write.headers['cookie']);
          expect(cookies['connect.sid'], 'zqSession1');
          // Returned over HTTP although marked Secure.
          expect(cookies['_csrf'], csrf ? csrfSecret : isNull);
          expect(write.headers['x-xsrf-token'], csrf ? csrfToken : isNull);
          expect(write.headers, isNot(contains('x-api-key')));
        });
      }

      test('writes with an API key', () async {
        final setup = await _Setup.start(
          authKind: AuthKind.apiKey,
          credential: const Credential(apiKey: _apiKey),
          csrf: csrf,
        );

        valueOf(await setup.requests.request(title(), is4k: false));

        expect(setup.server.logins, isEmpty);
        final write = setup.server.requests.last;
        expect(write.headers['x-api-key'], _apiKey);
        expect(write.headers['x-xsrf-token'], csrf ? csrfToken : isNull);
      });
    });
  }

  for (final authKind in [AuthKind.userPassword, AuthKind.mediaServerAccount]) {
    test('latches on a wrong ${authKind.name} password', () async {
      final setup = await _Setup.start(
        authKind: authKind,
        credential: const Credential(username: _user, password: 'wrong'),
      );

      expect(failureOf(await setup.probe()), isA<AuthFailed>());

      expect(await setup.latched(), isTrue);
      expect(setup.server.logins, hasLength(1));
      final count = setup.server.requests.length;
      expect(failureOf(await setup.requests.list()), isA<AuthFailed>());
      expect(setup.server.requests, hasLength(count));
    });
  }

  test('signs in again for a read whose session expired', () async {
    final setup = await _Setup.start();
    valueOf(await setup.probe());
    setup.server.sessions.clear();

    valueOf(await setup.discover.search('night'));

    expect(setup.server.logins, hasLength(2));
    expect(await setup.latched(), isFalse);
  });

  test('keeps the account when a delete is refused with a 401', () async {
    final setup = await _Setup.start();
    valueOf(await setup.probe());

    expect(failureOf<void>(await setup.requests.delete(9)), isA<Forbidden>());

    expect(await setup.latched(), isFalse);
    expect(
      setup.server.requests.where((request) => request.method == 'DELETE'),
      hasLength(1),
    );
  });

  test('keeps the account when a write is not permitted', () async {
    final setup = await _Setup.start();
    valueOf(await setup.probe());

    expect(failureOf<void>(await setup.requests.approve(9)), isA<Forbidden>());

    expect(await setup.latched(), isFalse);
  });

  test('reports a rejected API key', () async {
    final setup = await _Setup.start(
      authKind: AuthKind.apiKey,
      credential: const Credential(apiKey: 'wrong'),
    );

    expect(failureOf(await setup.probe()), isA<AuthFailed>());
  });

  // Seerr refuses reserved characters in a query value with 400.
  test('percent-encodes a search term completely', () async {
    final setup = await _Setup.start(
      authKind: AuthKind.apiKey,
      credential: const Credential(apiKey: _apiKey),
    );

    valueOf(await setup.discover.search("a b+c!'()*&d=e#f?g/h:i%é"));

    final query = setup.server.requests
        .singleWhere((request) => request.path == '/api/v1/search')
        .query;
    expect(
      query.split('&'),
      contains(
        'query=a%20b%2Bc%21%27%28%29%2A%26d%3De%23f%3Fg%2Fh%3Ai%25%C3%A9',
      ),
    );
    expect(query, isNot(contains('+')));
  });
}
