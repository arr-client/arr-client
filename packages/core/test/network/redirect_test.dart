/// Redirects (research R4, FR-070). The client follows them itself: only for a
/// read, only to the same scheme, host and port, and a bounded number of
/// times. Anything else is [Redirected], which for another origin names the
/// target's host. A write is not sent on to the target of any redirect, as that
/// would send it a second time. The API is described in client_test.dart.
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _statuses = [301, 302, 303, 307, 308];

/// Redirects `/start` to [location] and answers anything else.
Future<TestServer> _redirecting(
  String Function(TestServer server) location, {
  int status = 302,
}) async {
  late final TestServer server;
  server = await TestServer.start(
    (received, response) => received.target == '/start'
        ? reply(
            response,
            status: status,
            headers: {'location': location(server)},
          )
        : reply(response, body: '{"moved":true}'),
  );
  return server;
}

/// Targets that differ from the server's origin in one respect, and the host
/// each names.
final _elsewhere = <String, (String Function(int own, int other), String)>{
  'port': ((_, other) => 'http://127.0.0.1:$other/steal', '127.0.0.1'),
  'host name': ((own, _) => 'http://localhost:$own/steal', 'localhost'),
  'host without a scheme': (
    (_, other) => '//localhost:$other/steal',
    'localhost',
  ),
  'scheme': ((own, _) => 'https://127.0.0.1:$own/steal', '127.0.0.1'),
};

void main() {
  for (final status in _statuses) {
    test('a read follows $status to the same origin', () async {
      final server = await _redirecting((_) => '/moved?x=1', status: status);
      final client = clientFor(settingsFor(server.url()));

      final response = expectOk(await client.send(get('start')));

      expect(response.text, '{"moved":true}');
      expect(server.requests.map((r) => r.target), ['/start', '/moved?x=1']);
      expect(server.requests.last.method, 'GET');
      expect(server.requests.last.headers['x-api-key'], apiKey);
      expect(server.requests.last.headers['authorization'], basicHeader);
    });
  }

  for (final (name, location) in <(String, String Function(TestServer))>[
    ('relative', (_) => 'moved'),
    ('absolute', (server) => '${server.url('/moved')}'),
  ]) {
    test('a $name target of the same origin is followed', () async {
      final server = await _redirecting(location);
      final client = clientFor(settingsFor(server.url()));

      expectOk(await client.send(get('start')));

      expect(server.requests.last.target, '/moved');
    });
  }

  for (final MapEntry(key: name, value: (location, host))
      in _elsewhere.entries) {
    for (final method in HttpMethod.values) {
      test('${method.name} to another $name is not followed', () async {
        final target = await RawServer.start();
        final server = await _redirecting(
          (server) => location(server.port, target.port),
        );
        final client = clientFor(settingsFor(server.url()));

        final failure = expectFailure<Redirected>(
          await client.send(request(method, 'start')),
        );

        expect(failure.host, host);
        await pause();
        expect(target.connections, 0);
        expect(server.requests, hasLength(1));
      });
    }
  }

  test('a later hop to another origin is not followed', () async {
    final target = await RawServer.start();
    final server = await TestServer.start(
      (received, response) => reply(
        response,
        status: 302,
        headers: {
          'location': received.target == '/start'
              ? '/next'
              : '${target.url('/steal')}',
        },
      ),
    );
    final client = clientFor(settingsFor(server.url()));

    expectFailure<Redirected>(await client.send(get('start')));

    await pause();
    expect(target.connections, 0);
    expect(server.requests, hasLength(2));
  });

  test('a redirect loop ends', () async {
    final server = await _redirecting((_) => '/start');
    final client = clientFor(settingsFor(server.url()));

    expectFailure<Redirected>(await client.send(get('start')));

    // At most 20 followed, and a read may be retried once.
    expect(server.requests.length, lessThanOrEqualTo(42));
  });

  for (final method in writeMethods) {
    for (final status in _statuses) {
      test('${method.name} is not sent on after $status', () async {
        final server = await _redirecting((_) => '/moved', status: status);
        final client = clientFor(settingsFor(server.url()));

        expectFailure<Redirected>(await client.send(request(method, 'start')));

        await pause();
        expect(server.requests, hasLength(1));
      });
    }
  }
}
