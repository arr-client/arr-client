/// A write is never sent twice (FR-073, module contract rule 5): not after a
/// lost answer, a timeout or an error status. What may or may not have been
/// done is [OutcomeUnknown]. A read may be retried once. The API is described
/// in client_test.dart.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _timeout = Duration(milliseconds: 500);

/// What can happen to a request that reached the server.
final _losses = <String, void Function(Socket socket)>{
  'the connection closes without an answer': (socket) => socket.destroy(),
  'the answer stops in its headers': (socket) {
    socket.write('HTTP/1.1 200 OK\r\ncontent-ty');
    socket.flush().whenComplete(socket.destroy);
  },
  'no answer comes in time': (_) {},
};

void main() {
  for (final MapEntry(key: name, value: lose) in _losses.entries) {
    for (final method in writeMethods) {
      test('${method.name}: $name', () async {
        final server = await RawServer.start((socket, _) => lose(socket));
        final client = clientFor(settingsFor(server.url()), timeout: _timeout);

        expectFailure<OutcomeUnknown>(await client.send(request(method)));

        await pause();
        expect(server.requests, hasLength(1));
      });
    }

    test('a read is tried at most twice when $name', () async {
      final server = await RawServer.start((socket, _) => lose(socket));
      final client = clientFor(settingsFor(server.url()), timeout: _timeout);

      expectError(await client.send(get()));

      await pause();
      expect(server.requests.length, inInclusiveRange(1, 2));
    });
  }

  for (final method in writeMethods) {
    test('${method.name} is not repeated on a reused connection', () async {
      final server = await RawServer.start((socket, request) {
        if (request.startsWith('GET')) {
          socket.write('HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n');
        } else {
          socket.destroy();
        }
      });
      final client = clientFor(settingsFor(server.url()));
      expectOk(await client.send(get()));

      expectFailure<OutcomeUnknown>(await client.send(request(method)));

      await pause();
      expect(server.requests, hasLength(2));
    });

    // A gateway cannot say whether the server behind it did the work.
    for (final (status, matcher) in [
      (401, isA<AuthFailed>()),
      (500, isA<ServerError>()),
      (502, isA<OutcomeUnknown>()),
      (503, isA<ServerError>()),
      (504, isA<OutcomeUnknown>()),
    ]) {
      test('${method.name} is sent once when answered $status', () async {
        final server = await TestServer.start(
          (_, response) => reply(response, status: status),
        );
        final client = clientFor(settingsFor(server.url()));

        final error = expectError(await client.send(request(method)));

        expect(error.failure, matcher);
        expect(error.response?.statusCode, status);
        await pause();
        expect(server.requests, hasLength(1));
      });
    }
  }
}
