/// Nothing secret leaves the client through a failure or the diagnostic log
/// (constitution III, FR-065, coding standards). The API is described in
/// client_test.dart.
///
/// The client registers the credential of each send with the log before it
/// uses it. A [ServiceFailure] carries no secret, header or URL, even when the
/// server puts one in its messages. [HttpError.response] is the server's
/// answer as it is, for the module, and is not covered.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _queryValue = 'zq-hotel-888';

final _request = ServiceRequest(
  HttpMethod.get,
  'api',
  query: {
    'apikey': [_queryValue],
  },
);

/// The texts a failure can show.
String _texts(ServiceFailure failure) => switch (failure) {
  Redirected(:final host) => '$failure $host',
  Validation(:final messages) => '$failure ${messages.join(' ')}',
  _ => '$failure',
};

void _expectClean(String text) {
  for (final secret in [...secretValues, _queryValue]) {
    expect(text, isNot(contains(secret)));
  }
  expect(text, isNot(contains(basicHeader.split(' ').last)));
}

/// Sends [_request], which must fail, and checks the failure and the log.
Future<void> _check(Uri url, {Credential credential = credential}) async {
  final log = DiagnosticLog();
  final client = clientFor(
    settingsFor(url, credential: credential),
    log: log,
    timeout: const Duration(milliseconds: 500),
  );

  final error = expectError(await client.send(_request));

  _expectClean(_texts(error.failure));
  _expectClean('$error');
  _expectClean(log.export());
  expect(log.export(), isNot(contains('?apikey')));
}

void main() {
  test('the credential is registered with the log before use', () async {
    final log = DiagnosticLog();
    final server = await TestServer.start();
    final client = clientFor(settingsFor(server.url()), log: log);

    expectOk(await client.send(_request));
    log.clear();
    log.log(LogLevel.info, 'saw ${secretValues.join(' and ')}');

    expect(log.export(), contains(SecretRedactor.marker));
    for (final secret in secretValues) {
      expect(log.export(), isNot(contains(secret)));
    }
  });

  for (final status in [401, 404, 500]) {
    test('status $status', () async {
      final server = await TestServer.start(
        (_, response) => reply(response, status: status),
      );
      await _check(server.url());
    });
  }

  test('a redirect names the host only', () async {
    final server = await TestServer.start(
      (_, response) => reply(
        response,
        status: 302,
        headers: {
          'location':
              'http://$basicUser:$apiKey@localhost:1/login?token=$_queryValue',
        },
      ),
    );
    await _check(server.url());
  });

  test('server messages that repeat secrets', () async {
    final server = await TestServer.start(
      (_, response) => reply(
        response,
        status: 400,
        body: jsonEncode({
          'message':
              'Bad key $apiKey with $customValue and $basicPassword at '
              '/api?apikey=$_queryValue',
        }),
      ),
    );
    await _check(server.url());
  });

  test('an answer that is not HTTP and repeats a secret', () async {
    final server = await RawServer.start((socket, _) {
      socket.write('$apiKey $customValue\r\n\r\n');
      socket.flush().whenComplete(socket.destroy);
    });
    await _check(server.url());
  });

  test('a lost connection', () async {
    final server = await RawServer.start((socket, _) => socket.destroy());
    await _check(server.url());
  });

  test('a timeout', () async {
    final server = await RawServer.start();
    await _check(server.url());
  });

  test('a refused connection', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final url = Uri.parse('http://127.0.0.1:${socket.port}');
    await socket.close();
    await _check(url);
  });

  // dart:io quotes the value of a header it rejects.
  for (final (name, bad) in const [
    ('API key', Credential(apiKey: '$apiKey\n')),
    ('custom header', Credential(customHeaders: {'X-Id': '$customValue\r'})),
  ]) {
    test('a $name that cannot be sent', () async {
      final server = await TestServer.start();
      await _check(server.url(), credential: bad);
    });
  }
}
