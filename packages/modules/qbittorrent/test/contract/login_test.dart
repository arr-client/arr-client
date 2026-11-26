// The sign-in qBittorrent's session handler does for the core (upstream-apis.md,
// login responses by version).

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbittorrent/qbittorrent_module.dart';

import '../allow_list.dart';
import 'support.dart';

const _account = Credential(username: 'zq-user', password: 'zq p&ss=1');

SessionHandler get _handler => QbittorrentModule().sessionHandler!;

Future<Result<String, ServiceFailure>> _login(FakeHttp http) => _handler.login(
  authKind: AuthKind.userPassword,
  credential: _account,
  http: AllowListClient(allowList, http),
);

/// The answer of an accepted login on [version].
Answer _accepted(String version, {List<String>? cookies}) => Ok(
  response(
    // 5.2 and later answer without a body.
    version == '5.3.1' ? 204 : 200,
    fixture(version, 'login_ok.txt'),
    cookies: cookies ?? [setCookies[version]!],
  ),
);

/// Why the login fails against a server that gives [answer], asked once.
Future<ServiceFailure> _refused(Answer answer) async {
  final http = FakeHttp.always(answer);

  final failure = failureOf(await _login(http));

  expect(http.requests, hasLength(1));
  return failure;
}

void main() {
  test('posts the account as a form, and nothing else', () async {
    final http = FakeHttp.always(_accepted('5.3.1'));

    await _login(http);

    final request = http.requests.single;
    expect(request.method, HttpMethod.post);
    expect(request.path, 'api/v2/auth/login');
    expect(request.query, isEmpty);
    // The client encodes it; the module hands over the values as they are.
    expect(
      request.body,
      isA<FormBody>().having((body) => body.fields, 'fields', {
        'username': 'zq-user',
        'password': 'zq p&ss=1',
      }),
    );
    expect(request.headers, isEmpty);
    expectNoOrigin(request);
  });

  group('accepted', () {
    final sessions = {
      '4.4.5': 'SID=zqSession445',
      '5.1.4': 'SID=zqSession514',
      '5.3.1': 'QBT_SID_8080=zqSession531',
    };
    for (final MapEntry(key: version, value: session) in sessions.entries) {
      test('keeps the session cookie of $version', () async {
        final http = FakeHttp.always(_accepted(version));

        expect(valueOf(await _login(http)), session);
      });
    }

    // The port in the name is the one qBittorrent listens on, which need not
    // be the one in the instance's address.
    test('keeps a session cookie named after another port', () async {
      final http = FakeHttp.always(
        _accepted('5.3.1', cookies: ['QBT_SID_9999=abc; HttpOnly; path=/']),
      );

      expect(valueOf(await _login(http)), 'QBT_SID_9999=abc');
    });

    test('keeps a session cookie that was renamed', () async {
      final http = FakeHttp.always(
        _accepted('5.3.1', cookies: ['torrents=abc; HttpOnly; path=/']),
      );

      expect(valueOf(await _login(http)), 'torrents=abc');
    });

    test('finds the session beside a cookie of a proxy', () async {
      final http = FakeHttp.always(
        _accepted(
          '5.1.4',
          cookies: ['route=node1; path=/', 'SID=abc; HttpOnly; path=/'],
        ),
      );

      expect(valueOf(await _login(http)).split('; '), contains('SID=abc'));
    });
  });

  // AuthFailed latches the instance in the core, so nothing is tried again.
  group('rejected', () {
    for (final version in ['4.4.5', '5.1.4']) {
      test('takes the "Fails." of $version for a wrong password', () async {
        final failure = await _refused(ok(fixture(version, 'login_wrong.txt')));

        expect(failure, isA<AuthFailed>());
      });
    }

    // Also what a rejected host name looks like, and basic authentication in
    // front of 5.2 and later.
    test('takes the 401 of 5.2 and later, naming other causes', () async {
      final failure = await _refused(
        error(
          const AuthFailed(),
          status: 401,
          body: fixture('5.3.1', 'login_wrong.txt'),
        ),
      );

      expect(failure, isAuthFailedWithHint);
    });

    // Trying again would keep the address banned.
    for (final version in versions) {
      test('stops at the ban of $version', () async {
        final failure = await _refused(
          error(
            const Forbidden(),
            status: 403,
            body: fixture(version, 'login_banned.txt'),
          ),
        );

        expect(failure, isA<AuthFailed>());
      });
    }
  });

  group('no session', () {
    for (final failure in <ServiceFailure>[
      const Unreachable(),
      const DnsFailure(),
      const OutcomeUnknown(),
      const ServerError(statusCode: 500),
      const HostRejected(),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await _refused(error(failure)), same(failure));
      });
    }

    test('does not take the cookie of a proxy page', () async {
      final failure = await _refused(
        Ok(
          response(
            200,
            loginPage,
            type: null,
            cookies: ['proxy_session=abc; path=/'],
          ),
        ),
      );

      expect(failure, isA<ProxyInterception>());
    });

    test('keeps the classification of a proxy page', () async {
      final failure = await _refused(
        error(
          const ProxyInterception(),
          status: 200,
          body: loginPage,
          type: 'text/html',
        ),
      );

      expect(failure, isA<ProxyInterception>());
    });

    // Not a rejection: it must not latch the instance.
    test('does not blame the account for a missing cookie', () async {
      final failure = await _refused(ok('Ok.'));

      expect(failure, isNot(isA<AuthFailed>()));
    });
  });

  group('expired session', () {
    // Recorded: a session qBittorrent does not know gets 403 on every version.
    for (final version in versions) {
      test('is a 403 on $version', () {
        final answer = response(403, fixture(version, 'forbidden.txt'));

        expect(_handler.isSessionExpired(answer), isTrue);
      });
    }

    // A 401 is about the host name, which signing in again does not mend.
    for (final status in [200, 204, 401, 404, 500]) {
      test('is not a $status', () {
        expect(_handler.isSessionExpired(response(status, '')), isFalse);
      });
    }
  });
}
