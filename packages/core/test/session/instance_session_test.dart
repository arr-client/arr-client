/// Sign-in, sessions and the authFailed latch (data-model.md Instance,
/// module-contract.md).
library;

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

import '../network/certificates.dart';
import '../network/support.dart';

const _user = 'zq-user-111';
const _password = 'zq-pass-222';
const _entered = Credential(username: _user, password: _password);

/// Refuses an account as qBittorrent 4.4 does, with a 200.
class _Handler implements SessionHandler {
  /// Runs after the answer to the login has arrived.
  Future<void> Function()? answered;

  /// What the login was given.
  final given = <Credential>[];

  @override
  ServiceResult<String> login({
    required AuthKind authKind,
    required Credential credential,
    required ServiceHttpClient http,
  }) async {
    given.add(credential);
    final result = await http.send(
      ServiceRequest(
        HttpMethod.post,
        'auth/login',
        body: FormBody({
          'username': credential.username ?? '',
          'password': credential.password ?? '',
        }),
      ),
    );
    await answered?.call();
    return switch (result) {
      Err(:final error) => Err(error.failure),
      Ok(:final value) when value.text == 'Fails.' => const Err(AuthFailed()),
      // An acceptance without a session.
      Ok(:final value) when value.text == 'Ok.' => const Ok(''),
      Ok(:final value) => Ok(
        value.headers['set-cookie']!.single.split(';').first,
      ),
    };
  }

  @override
  bool isSessionExpired(ServiceResponse response) => response.statusCode == 403;
}

/// A server with one account, whose sessions the test can end.
class _Service {
  late final TestServer server;

  String password = _password;
  final sessions = <String>{};
  var _issued = 0;

  /// Marks this server's sessions apart from another's.
  String name = 'zq-session';

  /// Paths answered with this status whatever the session.
  final fixed = <String, int>{};

  /// Answers logins in place of the account.
  Future<void> Function(HttpResponse response)? answerLogin;

  /// Runs before a request is answered.
  Future<void> Function(Received received)? before;

  List<Received> get logins => [
    for (final received in server.requests)
      if (received.target.endsWith('auth/login')) received,
  ];

  /// What arrived apart from logins.
  List<String> get calls => [
    for (final received in server.requests)
      if (!received.target.endsWith('auth/login'))
        '${received.method} ${received.target}',
  ];

  static Future<_Service> start() async {
    final service = _Service();
    service.server = await TestServer.start(service._answer);
    return service;
  }

  Future<void> _answer(Received received, HttpResponse response) async {
    await before?.call(received);
    final path = received.target.substring(1);
    if (fixed[path] case final status?) {
      return reply(response, status: status);
    }
    if (path.endsWith('auth/login')) {
      if (answerLogin case final answer?) return answer(response);
      if (Uri.splitQueryString(received.body)['password'] != password) {
        return reply(response, body: 'Fails.', contentType: 'text/plain');
      }
      final cookie = 'SID=$name-${++_issued}';
      sessions.add(cookie);
      return reply(response, headers: {'set-cookie': '$cookie; HttpOnly'});
    }
    return reply(
      response,
      status: sessions.contains(received.headers['cookie']) ? 200 : 403,
    );
  }
}

class _Module implements ServiceModule {
  @override
  String get id => 'qbittorrent';

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
    displayName: 'qBittorrent',
    icon: IconData(0),
    category: ModuleCategory.downloadClient,
    authKinds: [AuthKind.userPassword, AuthKind.apiKey],
    apiKeyHeader: apiKeyHeader,
    defaultPort: 80,
    minimumVersion: '1',
    testedVersion: '1',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Secrets implements SecretStore {
  final values = <String, String>{};

  /// Each runs before its operation; may throw to make it fail.
  FutureOr<void> Function()? beforeRead;
  FutureOr<void> Function()? beforeWrite;

  /// Runs once the value of a write is stored, before the write returns.
  FutureOr<void> Function()? afterWrite;

  @override
  Future<String?> read(String key) async {
    await beforeRead?.call();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call();
    values[key] = value;
    await afterWrite?.call();
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

InstanceDraft _draft(Uri url, {AuthKind authKind = AuthKind.userPassword}) =>
    InstanceDraft(
      name: 'Downloads',
      serviceType: 'qbittorrent',
      url: url,
      authKind: authKind,
    );

ServiceRequest _read([String path = 'torrents']) => get(path);

ServiceRequest _write() => request(HttpMethod.post, 'torrents');

void _expectSignedIn(Result<void, ServiceFailure> result) {
  if (result case Err(:final error)) fail('failed: $error');
}

F _refusal<F extends ServiceFailure>(Result<void, ServiceFailure> result) {
  final failure = switch (result) {
    Ok() => fail('signed in'),
    Err(:final error) => error,
  };
  expect(failure, isA<F>());
  return failure as F;
}

void main() {
  late _Service service;
  late _Handler handler;
  late _Secrets secrets;
  late DiagnosticLog log;
  late AppDatabase database;
  late ProfileRepository profiles;
  late Instance instance;
  late DateTime now;

  void wait(Duration time) => now = now.add(time);

  ProfileRepository open(AppDatabase database) => ProfileRepository(
    database: database,
    secrets: secrets,
    log: log,
    preferences: PreferencesRepository(database),
    modules: [_Module()],
  );

  InstanceSession session({
    ProfileRepository? through,
    ApiKeyHeader header = apiKeyHeader,
  }) {
    final session = InstanceSession(
      profiles: through ?? profiles,
      instanceId: instance.id,
      handler: handler,
      apiKeyHeader: header,
      log: log,
      localNetwork: FakePermission(),
      timeout: const Duration(seconds: 10),
      now: () => now,
    );
    addTearDown(session.close);
    return session;
  }

  Future<Instance> add(
    ProfileRepository repository, {
    Credential credential = _entered,
    AuthKind authKind = AuthKind.userPassword,
  }) async {
    await repository.ensureDefaultProfile();
    final profile = (await repository.profiles()).first;
    final result = await repository.addInstance(
      profile.id,
      _draft(service.server.url(), authKind: authKind),
      credential: credential,
    );
    return (result as Ok<Instance, RuleViolation>).value;
  }

  Future<void> edit({
    Uri? url,
    Credential? credential,
    AuthKind authKind = AuthKind.userPassword,
  }) async {
    final result = await profiles.updateInstance(
      instance.id,
      _draft(url ?? service.server.url(), authKind: authKind),
      credential: credential,
    );
    expect(result, isA<Ok<Instance, RuleViolation>>());
  }

  Future<bool> latched() async =>
      (await profiles.instance(instance.id))!.authFailed;

  Future<String?> storedCookie() async =>
      (await profiles.credential(instance.id))?.sessionCookie;

  setUp(() async {
    service = await _Service.start();
    handler = _Handler();
    now = DateTime(2026, 1, 2);
    secrets = _Secrets();
    log = DiagnosticLog();
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    profiles = open(database);
    instance = await add(profiles);
  });

  group('signing in', () {
    test('comes before the first request and is kept', () async {
      expectOk(await session().send(_read()));

      expect(service.logins, hasLength(1));
      expect(service.logins.single.headers['cookie'], isNull);
      expect(service.server.requests.last.headers['cookie'], isNotNull);
      expect(await storedCookie(), 'SID=zq-session-1');
    });

    test('is not repeated while the session holds', () async {
      expectOk(await session().send(_read()));
      // Another object, as after a restart.
      expectOk(await session().send(_read()));

      expect(service.logins, hasLength(1));
    });

    test('is shared by requests made at the same time', () async {
      final client = session();

      final results = await Future.wait([
        for (var i = 0; i < 5; i++) client.send(_read()),
      ]);

      results.forEach(expectOk);
      expect(service.logins, hasLength(1));
    });

    test('on demand replaces the session, which is not sent', () async {
      final client = session();
      _expectSignedIn(await client.login());
      _expectSignedIn(await client.login());

      expect(await storedCookie(), 'SID=zq-session-2');
      expect(service.logins.last.headers['cookie'], isNull);
      expect(handler.given.last.sessionCookie, isNull);
    });

    test('tries nothing without an account', () async {
      await edit(credential: const Credential());

      _refusal<AuthFailed>(await session().login());

      expect(service.server.requests, isEmpty);
      expect(await latched(), isFalse);
    });

    test('is not used with an API key', () async {
      await edit(
        authKind: AuthKind.apiKey,
        credential: const Credential(apiKey: apiKey),
      );
      service.fixed['torrents'] = 200;

      expectOk(await session().send(_read()));

      expect(service.logins, isEmpty);
      expect(service.server.requests.single.headers['x-api-key'], apiKey);
    });

    test('logs nothing secret', () async {
      final client = session();
      expectOk(await client.send(_read()));
      service.password = 'changed';
      service.sessions.clear();
      expectError(await client.send(_read()));
      log.log(LogLevel.info, 'saw $_user $_password zq-session-1');

      for (final secret in [_user, _password, 'zq-session-1']) {
        expect(log.export(), isNot(contains(secret)));
      }
    });
  });

  group('a rejected login', () {
    setUp(() => service.password = 'another');

    test('latches the instance and sends nothing else', () async {
      final client = session();

      expectFailure<AuthFailed>(await client.send(_read()));
      expectFailure<AuthFailed>(await client.send(_read()));
      expectFailure<AuthFailed>(await client.send(_write()));
      _refusal<AuthFailed>(await client.login());
      expectFailure<AuthFailed>(await session().send(_read()));

      expect(await latched(), isTrue);
      expect(service.server.requests, hasLength(1));
    });

    test('is tried once for requests made at the same time', () async {
      final client = session();

      final results = await Future.wait([
        for (var i = 0; i < 5; i++) client.send(_read()),
      ]);
      results.forEach(expectFailure<AuthFailed>);

      expect(service.logins, hasLength(1));
    });

    test('is tried again once the user retries', () async {
      final client = session();
      expectFailure<AuthFailed>(await client.send(_read()));
      service.password = _password;

      await profiles.retryAuth(instance.id);
      expectOk(await client.send(_read()));

      expect(service.logins, hasLength(2));
    });

    test('is tried again once the password is edited', () async {
      final client = session();
      expectFailure<AuthFailed>(await client.send(_read()));

      await edit(
        credential: const Credential(username: _user, password: 'another'),
      );
      expectOk(await client.send(_read()));
    });

    test('of an edited password does not latch the new one', () async {
      handler.answered = () => edit(
        credential: const Credential(username: _user, password: 'another'),
      );
      final client = session();

      expectFailure<AuthFailed>(await client.send(_read()));
      handler.answered = null;

      expect(await latched(), isFalse);
      expectOk(await client.send(_read()));
    });

    test('that cannot be recorded still stops further attempts', () async {
      await database.customStatement(
        'CREATE TRIGGER refuse BEFORE UPDATE ON instances '
        "BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );
      final client = session();

      expectFailure<AuthFailed>(await client.send(_read()));
      expectFailure<AuthFailed>(await client.send(_read()));
      expect(service.logins, hasLength(1));

      await database.customStatement('DROP TRIGGER refuse');
      expectFailure<AuthFailed>(await client.send(_read()));

      expect(await latched(), isTrue);
      expect(service.logins, hasLength(1));
    });
  });

  group('a login that is not a rejection', () {
    test('does not latch, and is not repeated for the request', () async {
      service.fixed['auth/login'] = 502;

      // The request itself was not sent, so its outcome is not unknown.
      expectFailure<Unreachable>(await session().send(_write()));

      expect(await latched(), isFalse);
      expect(service.logins, hasLength(1));
      expect(service.calls, isEmpty);
    });

    test('says its own outcome is unknown to who asked for it', () async {
      service.fixed['auth/login'] = 502;

      _refusal<OutcomeUnknown>(await session().login());
    });
  });

  group('a login that failed after it was sent', () {
    const interval = InstanceSession.reloginInterval;
    const second = Duration(seconds: 1);

    // What a request reports, and what a login asked for does.
    for (final (name, answer, reported, asked)
        in <(String, Future<void> Function(HttpResponse), Matcher, Matcher)>[
          (
            'with a server error',
            (response) => reply(response, status: 500),
            isA<ServerError>(),
            isA<ServerError>(),
          ),
          (
            'with an unknown outcome',
            (response) => reply(response, status: 502),
            isA<Unreachable>(),
            isA<OutcomeUnknown>(),
          ),
          (
            'as the host name is refused',
            (response) => reply(response, status: 421),
            isA<HostRejected>(),
            isA<HostRejected>(),
          ),
          (
            'at a proxy page',
            (response) => reply(response, contentType: 'text/html'),
            isA<ProxyInterception>(),
            isA<ProxyInterception>(),
          ),
          (
            'with a redirect',
            (response) => reply(
              response,
              status: 302,
              headers: {'location': '/elsewhere'},
            ),
            isA<Redirected>(),
            isA<Redirected>(),
          ),
          (
            'with an answer that is not understood',
            reply,
            isA<MalformedResponse>(),
            isA<MalformedResponse>(),
          ),
          (
            'as no session came with the acceptance',
            (response) =>
                reply(response, body: 'Ok.', contentType: 'text/plain'),
            isA<MalformedResponse>(),
            isA<MalformedResponse>(),
          ),
        ]) {
      test('$name is not sent again for an interval', () async {
        service.answerLogin = answer;
        final client = session();
        Future<void> fails(ServiceRequest request) async =>
            expect(expectError(await client.send(request)).failure, reported);

        for (final request in [_read(), _write(), _read('other'), _write()]) {
          await fails(request);
        }
        wait(interval - second);
        await fails(_read());

        expect(service.logins, hasLength(1));
        expect(service.calls, isEmpty);
        expect(await latched(), isFalse);

        wait(second);
        await fails(_read());
        await fails(_read());
        expect(service.logins, hasLength(2));

        final result = await client.login();
        expect(result, isA<Err<void, ServiceFailure>>());
        expect((result as Err<void, ServiceFailure>).error, asked);
        expect(service.logins, hasLength(3));
      });
    }

    late InstanceSession client;

    /// One request has failed to sign in, and the server has recovered.
    Future<void> failOnce() async {
      service.fixed['auth/login'] = 500;
      client = session();
      expectFailure<ServerError>(await client.send(_read()));
      service.fixed.clear();
    }

    test('is sent again when the interval has passed', () async {
      await failOnce();
      expectFailure<ServerError>(await client.send(_read()));

      wait(interval);
      expectOk(await client.send(_read()));

      expect(service.logins, hasLength(2));
    });

    test('is sent at once when the user asks', () async {
      await failOnce();

      _expectSignedIn(await client.login());
      expectOk(await client.send(_read()));

      expect(service.logins, hasLength(2));
    });

    test('is held back again when what the user asked for fails', () async {
      await failOnce();
      service.fixed['auth/login'] = 503;

      _refusal<ServerError>(await client.login());
      expectFailure<ServerError>(await client.send(_read()));

      expect(service.logins, hasLength(2));
    });

    for (final (name, change) in <(String, Future<void> Function())>[
      (
        'password',
        () => edit(
          credential: const Credential(username: _user, password: 'edited'),
        ),
      ),
      (
        'custom headers',
        () => edit(
          credential: const Credential(
            username: _user,
            password: _password,
            customHeaders: {'X-Proxy-Id': 'zq-proxy'},
          ),
        ),
      ),
      ('address', () => edit(url: service.server.url('/sub'))),
    ]) {
      test('is sent at once after an edit of the $name', () async {
        await failOnce();
        service.answerLogin = (response) => reply(response, status: 500);

        await change();
        expectFailure<ServerError>(await client.send(_read()));
        expectFailure<ServerError>(await client.send(_read()));

        expect(service.logins, hasLength(2));
      });
    }

    test('is still held back after an edit of nothing it uses', () async {
      await failOnce();

      await edit(credential: _entered);
      expectFailure<ServerError>(await client.send(_read()));

      expect(service.logins, hasLength(1));
    });

    test('does not keep a session another has got from use', () async {
      await failOnce();

      _expectSignedIn(await session().login());
      expectOk(await client.send(_read()));

      expect(service.logins, hasLength(2));
    });

    test('is not held longer by a clock set back', () async {
      await failOnce();

      wait(-interval);
      expectOk(await client.send(_read()));
    });

    test('is shared by requests made at the same time', () async {
      service.fixed['auth/login'] = 500;
      final client = session();

      final results = await Future.wait([
        for (var i = 0; i < 5; i++) client.send(_read()),
      ]);

      results.forEach(expectFailure<ServerError>);
      expect(service.logins, hasLength(1));
    });

    test('holds back writes after an expired session too', () async {
      final client = session();
      expectOk(await client.send(_read()));
      service.sessions.clear();
      service.fixed['auth/login'] = 502;
      // The read cannot renew, the write discards the session.
      expectFailure<Unreachable>(await client.send(_read()));
      expectFailure<Forbidden>(await client.send(_write()));

      expectFailure<Unreachable>(await client.send(_write()));
      expectFailure<Unreachable>(await client.send(_read()));

      expect(service.logins, hasLength(2));
    });

    test('as the session cannot be stored is held back too', () async {
      secrets.beforeWrite = () => throw const FileSystemException('locked');
      final client = session();

      expectFailure<Unreachable>(await client.send(_read()));
      expectFailure<Unreachable>(await client.send(_read()));

      expect(service.logins, hasLength(1));
    });
  });

  group('a login that was not sent is tried again at once', () {
    Future<void> triedTwice<F extends ServiceFailure>(Uri url) async {
      await edit(url: url);
      final client = session();

      expectFailure<F>(await client.send(_read()));
      expectFailure<F>(await client.send(_read()));

      expect(handler.given, hasLength(2));
    }

    test('with nothing listening', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();

      await triedTwice<Unreachable>(Uri.parse('http://127.0.0.1:$port'));
    });

    test('with an unknown host', () async {
      // Too long a label to be asked of any name server.
      await triedTwice<DnsFailure>(Uri.parse('http://${'a' * 64}.invalid'));
    });

    test('with an untrusted certificate', () async {
      final server = await TlsServer.start(
        TestCertificate.selfSigned.serverContext(),
      );

      await triedTwice<CertificateUntrusted>(server.url());

      expect(server.bytes, isEmpty);
    });
  });

  group('an expired session', () {
    late InstanceSession client;

    setUp(() async {
      client = session();
      expectOk(await client.send(_read()));
      service.server.requests.clear();
      service.sessions.clear();
    });

    test('is renewed for a read, which is sent once more', () async {
      expectOk(await client.send(_read()));

      expect(service.logins, hasLength(1));
      expect(service.calls, ['GET /torrents', 'GET /torrents']);
      expect(await storedCookie(), 'SID=zq-session-2');
    });

    test('is renewed once for reads made at the same time', () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) client.send(_read()),
      ]);

      results.forEach(expectOk);
      expect(service.logins, hasLength(1));
    });

    test('never has a write sent again', () async {
      expectFailure<Forbidden>(await client.send(_write()));

      expect(service.calls, ['POST /torrents']);
      expect(service.logins, isEmpty);
      expect(await storedCookie(), isNull);

      // The next one signs in first.
      expectOk(await client.send(_write()));
      expect(service.logins, hasLength(1));
      expect(service.calls, hasLength(2));
    });

    test('latches when the new login is rejected', () async {
      service.password = 'changed';

      expectFailure<AuthFailed>(await client.send(_read()));
      expectFailure<AuthFailed>(await client.send(_read()));

      expect(await latched(), isTrue);
      expect(service.server.requests, hasLength(2));
    });
  });

  group('a read the new session is refused too', () {
    const interval = InstanceSession.reloginInterval;
    const retry = InstanceSession.refusedRetryInterval;
    const second = Duration(seconds: 1);

    late InstanceSession client;

    setUp(() async {
      client = session();
      expectOk(await client.send(_read()));
      service.fixed['admin'] = 403;
      service.fixed['users'] = 403;
    });

    Future<void> refused(String path) async =>
        expectFailure<Forbidden>(await client.send(_read(path)));

    test('neither latches nor signs in over and over', () async {
      for (var i = 0; i < 10; i++) {
        await refused('admin');
      }

      // The first request's, and one to find that signing in does not help.
      expect(service.logins, hasLength(2));
      expect(await latched(), isFalse);
    });

    test('does not take turns with another such path', () async {
      for (var i = 0; i < 10; i++) {
        await refused('admin');
        await refused('users');
      }

      expect(service.logins, hasLength(2));
    });

    test('is tried rarely however long paths take turns', () async {
      // Half an hour of polling.
      for (var i = 0; i < 360; i++) {
        await refused(i.isEven ? 'admin' : 'users');
        wait(const Duration(seconds: 5));
      }

      // The first, then one for each path in each ten minutes.
      expect(service.logins, hasLength(7));
    });

    test('does not cost a sign-in for each of many paths', () async {
      for (var i = 0; i < 20; i++) {
        service.fixed['movie/$i'] = 403;
        await refused('movie/$i');
      }

      expect(service.logins, hasLength(2));
    });

    test('signs in once an interval while many paths are tried', () async {
      // Ten minutes, a path not seen before every five seconds.
      for (var i = 0; i < 120; i++) {
        service.fixed['movie/$i'] = 403;
        await refused('movie/$i');
        wait(const Duration(seconds: 5));
      }

      expect(service.logins, hasLength(11));
    });

    test('signs in once for paths refused at the same time', () async {
      await Future.wait([refused('admin'), refused('users')]);
      await Future.wait([refused('admin'), refused('users')]);

      expect(service.logins, hasLength(2));
    });

    test('is tried with a new session again much later', () async {
      await refused('admin');

      wait(retry - second);
      await refused('admin');
      expect(service.logins, hasLength(2));

      wait(second);
      await refused('admin');
      expect(service.logins, hasLength(3));
    });

    test('is forgotten once the path succeeds', () async {
      await refused('admin');
      wait(interval);
      service.fixed.remove('admin');
      expectOk(await client.send(_read('admin')));
      service.sessions.clear();

      expectOk(await client.send(_read('admin')));

      expect(service.logins, hasLength(3));
    });

    test('is not forgotten when the server fails instead', () async {
      await refused('admin');
      wait(interval);
      service.fixed['admin'] = 500;
      expectFailure<ServerError>(await client.send(_read('admin')));
      service.fixed['admin'] = 403;

      await refused('admin');

      expect(service.logins, hasLength(2));
    });

    test('delays the renewal of an expired session only briefly', () async {
      await refused('admin');
      service.sessions.clear();

      wait(interval - second);
      await refused('torrents');
      expect(service.logins, hasLength(2));

      wait(second);
      expectOk(await client.send(_read()));
      expect(service.logins, hasLength(3));
    });

    test('does not delay using a session another has just got', () async {
      await refused('admin');
      // While the request is on its way, as the other isolate would.
      service.before = (_) async {
        service.before = null;
        service.sessions.clear();
        _expectSignedIn(await session().login());
      };

      expectOk(await client.send(_read()));
      expect(service.logins, hasLength(3));
    });

    test('does not delay signing in without a session', () async {
      await refused('admin');
      service.fixed['torrents'] = 403;
      // A refused write discards the session.
      expectFailure<Forbidden>(await client.send(_write()));
      service.fixed.remove('torrents');

      expectOk(await client.send(_read()));
      expect(service.logins, hasLength(3));
    });
  });

  group('an expired session, time after time', () {
    test('is renewed each time, an interval apart', () async {
      final client = session();
      for (var i = 0; i < 4; i++) {
        expectOk(await client.send(_read()));
        service.sessions.clear();
        wait(InstanceSession.reloginInterval);
      }

      expect(service.logins, hasLength(4));
    });
  });

  group('a rejection of a request', () {
    test('with an API key latches the instance', () async {
      await edit(
        authKind: AuthKind.apiKey,
        credential: const Credential(apiKey: apiKey),
      );
      service.fixed['torrents'] = 401;
      final client = session();

      expectFailure<AuthFailed>(await client.send(_read()));
      expectFailure<AuthFailed>(await client.send(_read()));

      expect(await latched(), isTrue);
      expect(service.server.requests, hasLength(1));
    });

    for (final MapEntry(key: name, value: header) in {
      'latches where the service rejects keys so': const ApiKeyHeader(
        'Authorization',
        prefix: 'Bearer ',
        rejectionStatus: 403,
      ),
      'does not latch elsewhere': apiKeyHeader,
    }.entries) {
      test('with a wrong API key and a 403 $name', () async {
        await edit(
          authKind: AuthKind.apiKey,
          credential: const Credential(apiKey: apiKey),
        );
        final rejects = header.rejectionStatus != null;
        final client = session(header: header);

        final first = expectError(await client.send(_read()));
        final second = expectError(await client.send(_read()));

        expect(first.failure, rejects ? isA<AuthFailed>() : isA<Forbidden>());
        expect(first.response!.statusCode, 403);
        expect(second.failure, rejects ? isA<AuthFailed>() : isA<Forbidden>());
        expect(await latched(), rejects);
        expect(service.server.requests, hasLength(rejects ? 1 : 2));
      });
    }

    test('with a login ignores the status that rejects a key', () async {
      service.fixed['admin'] = 403;
      final client = session(
        header: const ApiKeyHeader('X-Api-Key', rejectionStatus: 403),
      );

      expectFailure<Forbidden>(await client.send(_read('admin')));

      expect(await latched(), isFalse);
    });

    test('that is not an expired session latches without a login', () async {
      final client = session();
      expectOk(await client.send(_read()));
      service.fixed['torrents'] = 401;

      expectFailure<AuthFailed>(await client.send(_read()));

      expect(await latched(), isTrue);
      expect(service.logins, hasLength(1));
    });
  });

  group('an edit while signing in', () {
    test('of the address keeps the session of the old one', () async {
      final other = await _Service.start()
        ..name = 'zq-other';
      handler.answered = () => edit(url: other.server.url());
      final client = session();

      expectFailure<Unreachable>(await client.send(_read()));
      handler.answered = null;

      expect(await storedCookie(), isNull);
      expect(other.server.requests, isEmpty);

      expectOk(await client.send(_read()));
      for (final received in other.server.requests) {
        expect(received.headers['cookie'], isNot('SID=zq-session-1'));
      }
      expect(service.calls, isEmpty);
    });

    test('of the password does not keep the old account', () async {
      handler.answered = () => edit(
        credential: const Credential(username: 'other', password: _password),
      );

      expectFailure<Unreachable>(await session().send(_read()));

      expect(await storedCookie(), isNull);
      expect(service.calls, isEmpty);
    });

    test('of nothing it uses keeps both', () async {
      handler.answered = () => edit(credential: _entered);

      expectOk(await session().send(_read()));
    });
  });

  group('saving the form', () {
    late Credential read;

    setUp(() async {
      _expectSignedIn(await session().login());
      read = (await profiles.credential(instance.id))!;
      // Renewed after the form read the credential.
      _expectSignedIn(await session().login());
    });

    test('keeps the newer session', () async {
      await edit(credential: read);

      expect(await storedCookie(), 'SID=zq-session-2');
    });

    test('with a new address takes no session along', () async {
      await edit(url: Uri.parse('http://other.test'), credential: read);

      expect(await storedCookie(), isNull);
    });

    test('with another authKind drops the session', () async {
      await edit(authKind: AuthKind.mediaServerAccount);

      expect(await storedCookie(), isNull);
    });
  });

  group('a secret store that fails', () {
    Never locked() => throw const FileSystemException('locked');

    test('to read sends nothing', () async {
      secrets.beforeRead = locked;

      expectFailure<Unreachable>(await session().send(_read()));

      expect(service.server.requests, isEmpty);
    });

    test('to write sends nothing without a stored session', () async {
      secrets.beforeWrite = locked;

      expectFailure<Unreachable>(await session().send(_read()));

      expect(service.calls, isEmpty);
      expect(await latched(), isFalse);
    });
  });

  group('the background isolate, with its own connection', () {
    late AppDatabase front;
    late AppDatabase back;
    late ProfileRepository background;

    setUp(() async {
      final directory = await Directory.systemTemp.createTemp('session');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/app.sqlite');
      // Two on purpose.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      // Each on a thread of its own, so that one can wait for the other.
      front = AppDatabase(NativeDatabase.createInBackground(file));
      profiles = open(front);
      instance = await add(profiles);
      back = AppDatabase(NativeDatabase.createInBackground(file));
      background = open(back);
      await background.instance(instance.id);
      addTearDown(front.close);
      addTearDown(back.close);
    });

    test('uses the session the app signed in with', () async {
      expectOk(await session().send(_read()));
      expectOk(await session(through: background).send(_read()));

      expect(service.logins, hasLength(1));
    });

    test('honours a latch set by the app', () async {
      final client = session(through: background);
      expectOk(await client.send(_read()));
      service.server.requests.clear();

      await profiles.markAuthFailed(instance.id);

      expectFailure<AuthFailed>(await client.send(_read()));
      expect(service.server.requests, isEmpty);
    });

    test('latches the app too', () async {
      service.password = 'another';

      expectFailure<AuthFailed>(
        await session(through: background).send(_read()),
      );
      expectFailure<AuthFailed>(await session().send(_read()));

      expect(service.logins, hasLength(1));
    });

    test('may try once while the app is trying', () async {
      service.password = 'another';
      final both = Completer<void>();
      service.before = (_) {
        if (service.logins.length == 2) both.complete();
        return both.future;
      };

      final results = await Future.wait([
        session().send(_read()),
        session(through: background).send(_read()),
      ]);
      results.forEach(expectFailure<AuthFailed>);
      expectFailure<AuthFailed>(await session().send(_read()));

      expect(service.logins, hasLength(2));
    });

    test('waits for an edit, and does not read in the middle of it', () async {
      final written = Completer<void>();
      final finish = Completer<void>();
      // The new password is stored, the new address is not yet committed.
      secrets.afterWrite = () {
        secrets.afterWrite = null;
        written.complete();
        return finish.future;
      };
      final editing = edit(
        url: Uri.parse('http://other.test'),
        credential: const Credential(username: _user, password: 'edited'),
      );
      await written.future;
      Timer(const Duration(milliseconds: 300), finish.complete);

      final read = (await background.instanceWithCredential(instance.id))!;
      await editing;

      expect(read.instance.url, Uri.parse('http://other.test'));
      expect(read.credential!.password, 'edited');
    });

    test('latches although the app is saving something', () async {
      final writing = Completer<void>();
      final finish = Completer<void>();
      final saving = front.transaction(() async {
        await profiles.createProfile('Away');
        writing.complete();
        await finish.future;
      });
      await writing.future;
      Timer(const Duration(milliseconds: 500), finish.complete);

      await background.markAuthFailed(instance.id);
      await saving;

      expect(await latched(), isTrue);
    });
  });
}
