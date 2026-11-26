// ApiKeyCheck: finding out whether a service rejected the key, where its answer
// alone does not say.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _refusal = '{"error":"not allowed"}';

final _header = ApiKeyHeader(
  'X-Api-Key',
  check: ApiKeyCheck(
    path: 'me',
    refuses: (response) =>
        response.statusCode == 403 && response.text == _refusal,
  ),
);

typedef _Answer = ({int status, String body});

const _ok = (status: 200, body: '{}');
const _refused = (status: 403, body: _refusal);
const _otherRefusal = (status: 403, body: '{"message":"no quota"}');
const _unauthorized = (status: 401, body: '{"message":"not yours"}');
const _broken = (status: 500, body: '{}');

/// A server that answers by path, and the requests it got.
Future<(TestServer, InstanceHttpClient)> _start(
  Map<String, _Answer> answers, {
  AuthKind authKind = AuthKind.apiKey,
}) async {
  final server = await TestServer.start((received, response) {
    final answer = answers[received.target.substring(1)] ?? _ok;
    return reply(response, status: answer.status, body: answer.body);
  });
  return (
    server,
    clientFor(settingsFor(server.url(), authKind: authKind), header: _header),
  );
}

List<String> _calls(TestServer server) => [
  for (final received in server.requests)
    '${received.method} ${received.target}',
];

void main() {
  for (final method in [HttpMethod.get, ...writeMethods]) {
    final name = method.name.toUpperCase();

    for (final MapEntry(key: what, value: answer) in {
      'a refusal': _refused,
      'a 401': _unauthorized,
    }.entries) {
      test('$what of a $name is a rejection if the check says so', () async {
        final (server, client) = await _start({'item': answer, 'me': _refused});

        final error = expectError(await client.send(request(method, 'item')));

        expect(error.failure, isA<AuthFailed>());
        // The request's own answer, not the check's.
        expect(error.response!.statusCode, answer.status);
        expect(error.response!.text, answer.body);
        expect(_calls(server), ['$name /item', 'GET /me']);
        expect(server.requests.last.headers['x-api-key'], apiKey);
      });

      test('$what of a $name is forbidden if the key reads', () async {
        final (server, client) = await _start({'item': answer});

        final error = expectError(await client.send(request(method, 'item')));

        expect(error.failure, isA<Forbidden>());
        expect(error.response!.statusCode, answer.status);
        expect(_calls(server), ['$name /item', 'GET /me']);
      });
    }
  }

  test('a check answering 401 is a rejection', () async {
    final (_, client) = await _start({'item': _refused, 'me': _unauthorized});

    expectFailure<AuthFailed>(await client.send(get('item')));
  });

  for (final MapEntry(key: what, value: answer) in {
    'fails': _broken,
    'is refused otherwise': _otherRefusal,
  }.entries) {
    test('nothing is rejected when the check $what', () async {
      final (_, client) = await _start({'item': _unauthorized, 'me': answer});

      expectFailure<Forbidden>(await client.send(get('item')));
    });
  }

  for (final MapEntry(key: what, value: (answer, failure)) in {
    'a refusal': (_refused, isA<AuthFailed>()),
    'a 401': (_unauthorized, isA<AuthFailed>()),
    'another 403': (_otherRefusal, isA<Forbidden>()),
  }.entries) {
    test('$what of the checked read itself needs no second one', () async {
      final (server, client) = await _start({'me': answer});

      expect(expectError(await client.send(get('me'))).failure, failure);
      expect(_calls(server), ['GET /me']);
    });
  }

  test('a write to the checked path is checked by reading it', () async {
    final (server, client) = await _start({'me': _unauthorized});

    expectFailure<AuthFailed>(
      await client.send(request(HttpMethod.post, 'me')),
    );
    expect(_calls(server), ['POST /me', 'GET /me']);
  });

  test('another refusal or failure is not checked', () async {
    final (server, client) = await _start({'a': _otherRefusal, 'b': _broken});

    expectFailure<Forbidden>(await client.send(get('a')));
    expectFailure<ServerError>(await client.send(get('b')));
    expectOk(await client.send(get('c')));

    expect(_calls(server), ['GET /a', 'GET /b', 'GET /c']);
  });

  for (final authKind in [
    AuthKind.userPassword,
    AuthKind.mediaServerAccount,
    AuthKind.none,
  ]) {
    test('nothing is checked with ${authKind.name}', () async {
      final (server, client) = await _start({
        'a': _unauthorized,
        'b': _refused,
      }, authKind: authKind);

      expectFailure<AuthFailed>(await client.send(get('a')));
      expectFailure<Forbidden>(await client.send(get('b')));

      expect(_calls(server), ['GET /a', 'GET /b']);
    });
  }
}
