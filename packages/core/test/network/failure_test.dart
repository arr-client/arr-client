/// How the client classifies every failure it can tell apart (FR-007,
/// SC-008, module contract rule 4). The API is described in client_test.dart.
///
/// Every [ServiceFailure] is covered:
///
/// - here: [Unreachable], [DnsFailure], [AuthFailed], [Forbidden],
///   [ProxyInterception], [HostRejected], [PermissionDenied], [NotFound],
///   [Conflict], [Validation], [ServerError], [MalformedResponse];
/// - redirect_test.dart: [Redirected]; retry_test.dart: [OutcomeUnknown];
///   trust_test.dart: [CertificateUntrusted], [CertificateChanged];
/// - [WrongService], [UnsupportedVersion] and [WritesRefused] need knowledge of
///   the service, so a module makes them from [HttpError.response]. The client
///   never does, and must pass the response on.
///
/// [HttpError.response] is the server's answer, and null if none arrived.
/// A 2xx answer of type `text/html` is a web page; no service sends one as
/// data. Statuses 502 and 504 to a write are in retry_test.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Sent by ASP.NET Core's host filtering, which the Servarr services run on, as
/// recorded from Radarr 7.0.3.10918 and Sonarr 4.0.20.3014.
const _invalidHostname =
    '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"'
    '"http://www.w3.org/TR/html4/strict.dtd">\r\n'
    '<HTML><HEAD><TITLE>Bad Request</TITLE>\r\n'
    '<META HTTP-EQUIV="Content-Type" Content="text/html; charset=us-ascii">'
    '</ HEAD >\r\n'
    '<BODY><h2>Bad Request - Invalid Hostname</h2>\r\n'
    '<hr><p>HTTP Error 400. The request hostname is invalid.</p>\r\n'
    '</BODY></HTML>';

const _page = '<html><body><form>Sign in</form></body></html>';

const _timeout = Duration(milliseconds: 500);

/// The error for one answer, after checking that the answer comes with it.
Future<HttpError> _answered(
  int status, {
  String body = '{}',
  String contentType = 'application/json',
  HttpMethod method = HttpMethod.get,
}) async {
  final server = await TestServer.start(
    (_, response) =>
        reply(response, status: status, body: body, contentType: contentType),
  );
  final client = clientFor(settingsFor(server.url()));
  final error = expectError(await client.send(request(method)));
  expect(error.response?.statusCode, status);
  expect(error.response?.text, body);
  expect(error.response?.headers['content-type'], [contentType]);
  return error;
}

/// An address on which nothing listens.
Future<Uri> _closedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return Uri.parse('http://127.0.0.1:$port');
}

// A label over 63 characters cannot be asked of any name server, so this fails
// without traffic.
final _unknownHost = Uri.parse('http://${'a' * 64}.invalid');

void main() {
  Matcher serverError(int status) =>
      isA<ServerError>().having((f) => f.statusCode, 'statusCode', status);

  final byStatus = <int, Matcher>{
    401: isA<AuthFailed>(),
    403: isA<Forbidden>(),
    404: isA<NotFound>(),
    409: isA<Conflict>(),
    421: isA<HostRejected>(),
    418: serverError(418),
    429: serverError(429),
    500: serverError(500),
    502: serverError(502),
    503: serverError(503),
    504: serverError(504),
  };
  for (final MapEntry(key: status, value: matcher) in byStatus.entries) {
    test('status $status', () async {
      expect((await _answered(status)).failure, matcher);
    });
  }

  // The status says more than the web page that comes with it.
  for (final status in [401, 403, 404, 502]) {
    test('status $status with a web page', () async {
      final error = await _answered(
        status,
        body: _page,
        contentType: 'text/html',
      );
      expect(error.failure, byStatus[status]);
    });
  }

  for (final method in [HttpMethod.get, HttpMethod.post]) {
    test('${method.name} answered with a web page was intercepted', () async {
      final error = await _answered(
        200,
        body: _page,
        contentType: 'text/html; charset=utf-8',
        method: method,
      );
      expect(error.failure, isA<ProxyInterception>());
    });
  }

  for (final contentType in ['text/plain', 'image/jpeg']) {
    test('$contentType is not a web page', () async {
      final server = await TestServer.start(
        (_, response) => reply(response, body: 'Ok.', contentType: contentType),
      );
      final client = clientFor(settingsFor(server.url()));

      expectOk(await client.send(get()));
    });
  }

  test('a rejected host name', () async {
    final error = await _answered(
      400,
      body: _invalidHostname,
      contentType: 'text/html',
    );
    expect(error.failure, isA<HostRejected>());
  });

  for (final (status, body, messages) in <(int, Object, List<String>)>[
    (
      400,
      [
        {'propertyName': 'path', 'errorMessage': 'Path is taken'},
        {'propertyName': 'tags', 'errorMessage': 'Unknown tag'},
      ],
      ['Path is taken', 'Unknown tag'],
    ),
    (422, {'message': 'Season is required'}, ['Season is required']),
  ]) {
    test('status $status carries the server messages', () async {
      final error = await _answered(status, body: jsonEncode(body));
      expect(
        error.failure,
        isA<Validation>().having((f) => f.messages, 'messages', messages),
      );
    });
  }

  for (final method in [HttpMethod.get, HttpMethod.post]) {
    group('${method.name} that never connected', () {
      test('to a closed port is unreachable', () async {
        final client = clientFor(settingsFor(await _closedPort()));

        final error = expectError(await client.send(request(method)));

        expect(error.failure, isA<Unreachable>());
        expect(error.response, isNull);
      });

      test('to an unknown host is a name failure', () async {
        final client = clientFor(settingsFor(_unknownHost));

        final error = expectError(await client.send(request(method)));

        expect(error.failure, isA<DnsFailure>());
        expect(error.response, isNull);
      });
    });
  }

  // No TLS connection, so nothing was sent, whatever the method.
  for (final method in [HttpMethod.get, HttpMethod.post]) {
    test('${method.name} to a server that speaks no TLS', () async {
      final server = await TestServer.start();
      final client = clientFor(
        settingsFor(server.url().replace(scheme: 'https')),
      );

      expectFailure<Unreachable>(await client.send(request(method)));

      expect(server.requests, isEmpty);
    });

    test('${method.name} whose TLS handshake stalls', () async {
      final server = await RawServer.start();
      final client = clientFor(
        settingsFor(server.url().replace(scheme: 'https')),
        timeout: _timeout,
      );

      expectFailure<Unreachable>(await client.send(request(method)));
    });

    test('${method.name} over https to an unknown host', () async {
      final client = clientFor(
        settingsFor(_unknownHost.replace(scheme: 'https')),
      );

      expectFailure<DnsFailure>(await client.send(request(method)));
    });
  }

  for (final (name, lose) in <(String, void Function(Socket))>[
    ('closed without an answer', (socket) => socket.destroy()),
    ('left without an answer', (_) {}),
  ]) {
    test('a read $name is unreachable', () async {
      final server = await RawServer.start((socket, _) => lose(socket));
      final client = clientFor(settingsFor(server.url()), timeout: _timeout);

      final error = expectError(await client.send(get()));

      expect(error.failure, isA<Unreachable>());
      expect(error.response, isNull);
    });
  }

  for (final (name, answer) in [
    ('that is not HTTP', 'SSH-2.0-OpenSSH_9.9\r\n\r\n'),
    (
      'with two lengths',
      'HTTP/1.1 200 OK\r\ncontent-length: 1\r\ncontent-length: 2\r\n\r\n{}',
    ),
    (
      'whose chunks are broken',
      'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\nzz\r\n',
    ),
    (
      'whose compression is broken',
      'HTTP/1.1 200 OK\r\ncontent-encoding: gzip\r\n'
          'content-length: 9\r\nconnection: close\r\n\r\nnot gzip!',
    ),
  ]) {
    test('an answer $name is malformed', () async {
      final server = await RawServer.start((socket, _) {
        socket.write(answer);
        socket.flush().whenComplete(socket.destroy);
      });
      final client = clientFor(settingsFor(server.url()));

      expectFailure<MalformedResponse>(await client.send(get()));
    });
  }

  // A denied permission looks like a timeout (research R6).
  for (final method in [HttpMethod.get, HttpMethod.post]) {
    test('${method.name} timing out without permission', () async {
      final server = await RawServer.start();
      final permission = FakePermission(LocalNetworkPermissionState.denied);
      final client = clientFor(
        settingsFor(server.url()),
        permission: permission,
        timeout: _timeout,
      );

      expectFailure<PermissionDenied>(await client.send(request(method)));

      expect(permission.hosts, contains('127.0.0.1'));
    });
  }

  test('a timeout with permission is unreachable', () async {
    final server = await RawServer.start();
    final client = clientFor(
      settingsFor(server.url()),
      permission: FakePermission(LocalNetworkPermissionState.granted),
      timeout: _timeout,
    );

    expectFailure<Unreachable>(await client.send(get()));
  });

  // Each piece arrives within the limit of a step, but the answer never ends.
  for (final (method, matcher) in [
    (HttpMethod.get, isA<Unreachable>()),
    (HttpMethod.post, isA<OutcomeUnknown>()),
  ]) {
    test('${method.name} answered too slowly is given up', () async {
      final closed = Completer<void>();
      final server = await RawServer.start((socket, _) {
        socket.write('HTTP/1.1 200 OK\r\ncontent-length: 1000\r\n\r\n');
        final trickle = Timer.periodic(
          const Duration(milliseconds: 50),
          (_) => socket.write('x'),
        );
        socket.done.whenComplete(() {
          trickle.cancel();
          closed.complete();
        }).ignore();
        addTearDown(trickle.cancel);
      });
      final client = clientFor(
        settingsFor(server.url()),
        // Not asked: an answer is arriving.
        permission: FakePermission(LocalNetworkPermissionState.denied),
        timeout: const Duration(milliseconds: 200),
      );

      final error = expectError(await client.send(request(method)));

      expect(error.failure, matcher);
      await closed.future.timeout(const Duration(seconds: 5));
      expect(server.requests, hasLength(1));
    });
  }

  group('nothing is sent', () {
    test('without settings', () async {
      final client = loadingClient(() async => null);

      expectError(await client.send(get()));
    });

    test('when the settings cannot be read', () async {
      final client = loadingClient(
        () async => throw const FileSystemException('keystore'),
      );

      expectError(await client.send(get()));
    });

    // As a user might paste them.
    for (final (name, bad) in const [
      ('API key', Credential(apiKey: '$apiKey\nX-Other: 1')),
      ('custom header', Credential(customHeaders: {'X-Id': '$customValue\r'})),
    ]) {
      test('when the $name cannot be a header', () async {
        final server = await RawServer.start();
        final client = clientFor(settingsFor(server.url(), credential: bad));

        expectError(await client.send(get()));

        await pause();
        expect(server.bytes, isEmpty);
      });
    }
  });
}
