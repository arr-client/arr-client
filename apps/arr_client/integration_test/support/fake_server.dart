/// Servers on the device's loopback interface, which the app under test reaches
/// as it would any other: over real sockets, over http or https.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'certificates.dart';

/// A request a [FakeServer] received.
typedef ReceivedRequest = ({
  String method,
  String path,
  Map<String, List<String>> query,
  Map<String, String> headers,
});

/// What a [FakeServer] answers.
final class Reply {
  const Reply(
    this.status, {
    this.body = '',
    this.contentType = 'text/plain',
    this.headers = const {},
  });

  Reply.json(Object? value, {int status = 200})
    : this(status, body: jsonEncode(value), contentType: 'application/json');

  const Reply.webPage(String body, {int status = 200})
    : this(status, body: body, contentType: 'text/html');

  Reply.redirect(String location) : this(302, headers: {'location': location});

  final int status;
  final String body;
  final String contentType;
  final Map<String, String> headers;
}

/// How a server answers. Called for every request.
typedef Handler = Reply Function(ReceivedRequest request);

/// One server on 127.0.0.1, on a port the system chooses.
final class FakeServer {
  FakeServer._(this._server, this._secure, this.handler);

  /// With a [certificate] the server speaks https.
  static Future<FakeServer> start(
    Handler handler, {
    TestCertificate? certificate,
  }) async {
    final fake = FakeServer._(
      await _bind(0, certificate),
      certificate != null,
      handler,
    );
    fake._listen();
    return fake;
  }

  HttpServer _server;
  final bool _secure;

  /// Replaced to change how the server answers from now on.
  Handler handler;

  /// Every request received, oldest first.
  final requests = <ReceivedRequest>[];

  int get port => _server.port;

  /// The address as the user types it.
  String get address => '${_secure ? 'https' : 'http'}://127.0.0.1:$port';

  /// Comes back on the same port with [certificate], dropping every connection.
  Future<void> present(TestCertificate certificate) async {
    final port = this.port;
    await _server.close(force: true);
    _server = await _bind(port, certificate);
    _listen();
  }

  Future<void> close() => _server.close(force: true);

  static Future<HttpServer> _bind(int port, TestCertificate? certificate) {
    if (certificate == null) {
      return HttpServer.bind(InternetAddress.loopbackIPv4, port);
    }
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(certificate.chain))
      ..usePrivateKeyBytes(utf8.encode(certificate.key));
    return HttpServer.bindSecure(InternetAddress.loopbackIPv4, port, context);
  }

  void _listen() => _server.listen(
    (request) => unawaited(_answer(request)),
    // A handshake that the app gives up, as it does with a certificate that it
    // does not accept.
    onError: (Object _) {},
  );

  Future<void> _answer(HttpRequest request) async {
    try {
      await request.drain<void>();
      final headers = <String, String>{};
      request.headers.forEach((name, values) => headers[name] = values.join());
      final received = (
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParametersAll,
        headers: headers,
      );
      requests.add(received);
      final reply = handler(received);
      request.response
        ..statusCode = reply.status
        ..headers.set('content-type', reply.contentType);
      reply.headers.forEach(request.response.headers.set);
      request.response.write(reply.body);
      await request.response.close();
    } on IOException {
      // The app closed the connection.
    }
  }
}
