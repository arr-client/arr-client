/// [ServiceRequest.timeout]: a read the server takes long to answer says how
/// long to wait for it. A write keeps the client's own limit.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _clientTimeout = Duration(milliseconds: 200);
const _long = Duration(seconds: 5);

ServiceRequest _read([Duration? timeout]) =>
    ServiceRequest(HttpMethod.get, 'api', timeout: timeout);

/// A server that answers after [delay].
Future<TestServer> _slow(Duration delay) =>
    TestServer.start((_, response) async {
      await Future<void>.delayed(delay);
      // The client may be gone by then.
      await reply(response).catchError((Object _) {});
    });

InstanceHttpClient _client(Uri url, [Duration timeout = _clientTimeout]) =>
    clientFor(settingsFor(url), timeout: timeout);

void main() {
  test('a read waits for its answer as long as it says', () async {
    final server = await _slow(const Duration(milliseconds: 600));

    expectOk(await _client(server.url()).send(_read(_long)));

    expect(server.requests, hasLength(1));
  });

  test('and not only for that request', () async {
    final server = await _slow(const Duration(milliseconds: 600));
    final client = _client(server.url());
    expectOk(await client.send(_read(_long)));

    expectFailure<Unreachable>(await client.send(_read()));
  });

  test('a read waits as long at a pause in its answer', () async {
    final server = await RawServer.start((socket, _) async {
      socket.write('HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\n{');
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      socket.write('}');
    });

    final response = expectOk(await _client(server.url()).send(_read(_long)));

    expect(response.text, '{}');
  });

  test('a read may take longer than the limit of a whole attempt', () async {
    // The whole attempt is otherwise limited to ten times the client's.
    final server = await _slow(const Duration(milliseconds: 1500));
    final client = _client(server.url(), const Duration(milliseconds: 100));

    expectOk(await client.send(_read(_long)));

    expect(server.requests, hasLength(1));
  });

  test('a read gives up after its own time, and is not repeated', () async {
    final server = await RawServer.start();
    final client = _client(server.url(), _long);
    final elapsed = Stopwatch()..start();

    expectFailure<Unreachable>(
      await client.send(_read(const Duration(milliseconds: 300))),
    );

    expect(elapsed.elapsed, lessThan(_long));
    await pause();
    expect(server.requests, hasLength(1));
  });

  for (final method in writeMethods) {
    test('${method.name} ignores it', () async {
      final server = await RawServer.start((Socket _, String _) {});
      final client = _client(server.url());
      final elapsed = Stopwatch()..start();

      expectFailure<OutcomeUnknown>(
        await client.send(
          ServiceRequest(
            method,
            'api',
            body: const JsonBody({'id': 1}),
            timeout: _long,
          ),
        ),
      );

      expect(elapsed.elapsed, lessThan(_long));
      expect(server.requests, hasLength(1));
    });
  }
}
