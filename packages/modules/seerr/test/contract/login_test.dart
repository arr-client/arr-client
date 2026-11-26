// Signing in with a local or a media server account, as recorded (research
// R16).

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';

import '../allow_list.dart';
import 'support.dart';

const _local = AuthKind.userPassword;
const _jellyfin = AuthKind.mediaServerAccount;
const _account = Credential(username: 'zq@user.test', password: 'zq-pass');
const _sessionCookie =
    'connect.sid=s%3AzqSession.zqSignature; Path=/; '
    'Expires=Sat, 26 Dec 2026 22:06:52 GMT; HttpOnly; SameSite=Lax';

String _path(AuthKind authKind) =>
    authKind == _local ? 'api/v1/auth/local' : 'api/v1/auth/jellyfin';

FakeSeerr _server(AuthKind authKind, Answer answer, {bool csrf = false}) =>
    FakeSeerr(csrf: csrf)..set('POST ${_path(authKind)}', answer);

Answer _accepted(AuthKind authKind) => answered(
  200,
  fixture(authKind == _local ? 'auth_local' : 'auth_jellyfin'),
  cookies: const [_sessionCookie],
);

Future<Result<String, ServiceFailure>> _login(
  AuthKind authKind,
  FakeSeerr http,
) => SeerrModule().sessionHandler!.login(
  authKind: authKind,
  credential: _account,
  http: AllowListClient(allowList, http),
);

void main() {
  const bodies = {
    _local: {'email': 'zq@user.test', 'password': 'zq-pass'},
    _jellyfin: {'username': 'zq@user.test', 'password': 'zq-pass'},
  };

  for (final authKind in [_local, _jellyfin]) {
    group(authKind.name, () {
      test('sends the recorded body and nothing else', () async {
        final http = _server(authKind, _accepted(authKind));

        final session = valueOf(await _login(authKind, http));

        expect(http.writes, hasLength(1));
        expect(http.writes.single.path, _path(authKind));
        expect(sent(http.writes.single), bodies[authKind]);
        expect(cookiesOf(session), {
          'connect.sid': 's%3AzqSession.zqSignature',
        });
      });

      // Signing in is a POST, which a protected server refuses without a
      // token.
      test('sends the CSRF token, and keeps only the session', () async {
        final http = _server(authKind, _accepted(authKind), csrf: true);

        final session = valueOf(await _login(authKind, http));

        final login = http.writes.single;
        expect(header(login, 'x-xsrf-token'), csrfToken);
        expect(cookiesOf(header(login, 'cookie'))['_csrf'], csrfSecret);
        expect(cookiesOf(session).keys, ['connect.sid']);
      });

      // Not a rejection: the password must not be latched for it.
      test('reports a refused token as writes refused', () async {
        final http = _server(authKind, answered(403, csrfRefusal));

        expect(failureOf(await _login(authKind, http)), isA<WritesRefused>());
        expect(http.writes, hasLength(1));
      });

      test('does not take an answer without a session', () async {
        final http = _server(authKind, ok(fixture('auth_local')));

        expect(
          failureOf(await _login(authKind, http)),
          isA<MalformedResponse>(),
        );
      });

      // As when this way of signing in is switched off.
      test('passes on a failure that is no rejection', () async {
        final http = _server(
          authKind,
          answered(500, '{"error":"Password sign-in is disabled."}'),
        );

        expect(failureOf(await _login(authKind, http)), isA<ServerError>());
        expect(http.writes, hasLength(1));
      });
    });
  }

  test('takes a wrong local password for a rejection', () async {
    final http = _server(_local, answered(403, fixture('auth_local_wrong')));

    expect(failureOf(await _login(_local, http)), isA<AuthFailed>());
  });

  test('takes a wrong media server password for a rejection', () async {
    final http = _server(
      _jellyfin,
      answered(401, fixture('auth_jellyfin_wrong')),
    );

    expect(failureOf(await _login(_jellyfin, http)), isA<AuthFailed>());
  });

  // A media server user who was never imported, with new sign-ins off.
  test('takes a refused media server account for a rejection', () async {
    final http = _server(
      _jellyfin,
      answered(403, '{"message":"Access denied."}'),
    );

    expect(failureOf(await _login(_jellyfin, http)), isA<AuthFailed>());
  });

  // Overseerr has no such sign-in; the password was not looked at.
  test('does not latch where there is no media server sign-in', () async {
    final failure = failureOf(await _login(_jellyfin, FakeSeerr()));

    expect(failure, isNot(isA<AuthFailed>()));
  });

  group('expired session', () {
    bool expired(int status, String body) =>
        SeerrModule().sessionHandler!.isSessionExpired(response(status, body));

    // A session the server does not know, and none at all.
    test('is what an unknown or missing session gets', () {
      expect(expired(403, fixture('auth_me_rejected')), isTrue);
      expect(expired(401, fixture('auth_me_anonymous')), isTrue);
    });

    // Deleting a request or resolving an issue that is not one's own is a 401.
    // Unless the session handler claims it, the core latches the instance.
    test('covers the 401 of a refused delete', () {
      expect(expired(401, fixture('delete_refused')), isTrue);
    });

    test('is not any other 403', () {
      for (final body in [
        csrfRefusal,
        fixture('request_over_quota'),
        fixture('request_no_4k'),
        fixture('request_blocklisted'),
        fixture('auth_local_wrong'),
      ]) {
        expect(expired(403, body), isFalse, reason: body);
      }
    });

    test('is not a success or another failure', () {
      expect(expired(200, fixture('auth_me_member')), isFalse);
      expect(expired(404, '{"message":"Request not found."}'), isFalse);
      expect(expired(500, '{"message":"x"}'), isFalse);
    });
  });
}
