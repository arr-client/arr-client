/// Loopback servers that record what reaches them, and the client under test.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

// None of these looks like a secret to the log unless it was registered.
const apiKey = 'zq-alpha-111';
const basicUser = 'zq-bravo-222';
const basicPassword = 'zq-pässword-333';
const sessionCookie = 'SID=zq-delta-444';
const customValue = 'zq-echo-555';
const username = 'zq-foxtrot-666';
const password = 'zq-golf-777';

const credential = Credential(
  apiKey: apiKey,
  username: username,
  password: password,
  basicUser: basicUser,
  basicPassword: basicPassword,
  sessionCookie: sessionCookie,
  customHeaders: {'X-Proxy-Id': customValue},
);

const secretValues = [
  apiKey,
  basicUser,
  basicPassword,
  'zq-delta-444',
  customValue,
  username,
  password,
];

final basicHeader =
    'Basic ${base64Encode(utf8.encode('$basicUser:$basicPassword'))}';

const apiKeyHeader = ApiKeyHeader('X-Api-Key');

/// Long enough for an unwanted retry or redirect to arrive on loopback.
Future<void> pause() => Future<void>.delayed(const Duration(milliseconds: 300));

ConnectionSettings settingsFor(
  Uri url, {
  AuthKind authKind = AuthKind.apiKey,
  Credential credential = credential,
  String? certPin,
  String? customCa,
}) => ConnectionSettings(
  url: url,
  authKind: authKind,
  credential: credential,
  certPin: certPin,
  customCa: customCa,
);

/// A client with fixed settings, closed after the test.
InstanceHttpClient clientFor(
  ConnectionSettings settings, {
  ApiKeyHeader? header = apiKeyHeader,
  DiagnosticLog? log,
  FakePermission? permission,
  Duration timeout = const Duration(seconds: 10),
}) => loadingClient(
  () async => settings,
  header: header,
  log: log,
  permission: permission,
  timeout: timeout,
);

/// A client that loads its settings with [settings], closed after the test.
InstanceHttpClient loadingClient(
  Future<ConnectionSettings?> Function() settings, {
  ApiKeyHeader? header = apiKeyHeader,
  DiagnosticLog? log,
  FakePermission? permission,
  Duration timeout = const Duration(seconds: 10),
}) {
  final client = InstanceHttpClient(
    settings: settings,
    apiKeyHeader: header,
    log: log ?? DiagnosticLog(),
    localNetwork: permission ?? FakePermission(),
    timeout: timeout,
  );
  addTearDown(client.close);
  return client;
}

ServiceRequest get([String path = 'api']) =>
    ServiceRequest(HttpMethod.get, path);

/// A request of any method, with a body if it is a write.
ServiceRequest request(HttpMethod method, [String path = 'api']) =>
    ServiceRequest(
      method,
      path,
      body: method == HttpMethod.get ? null : const JsonBody({'id': 1}),
    );

const writeMethods = [
  HttpMethod.post,
  HttpMethod.put,
  HttpMethod.patch,
  HttpMethod.delete,
];

ServiceResponse expectOk(Result<ServiceResponse, HttpError> result) =>
    switch (result) {
      Ok(:final value) => value,
      Err(:final error) => fail('failed: ${error.failure}'),
    };

HttpError expectError(Result<ServiceResponse, HttpError> result) =>
    switch (result) {
      Ok(:final value) => fail('succeeded: ${value.statusCode}'),
      Err(:final error) => error,
    };

F expectFailure<F extends ServiceFailure>(
  Result<ServiceResponse, HttpError> result,
) {
  final failure = expectError(result).failure;
  expect(failure, isA<F>());
  return failure as F;
}

/// Answers [LocalNetworkPermission.status] and records the hosts asked about.
class FakePermission implements LocalNetworkPermission {
  FakePermission([this.state = LocalNetworkPermissionState.notRequired]);

  final LocalNetworkPermissionState state;
  final hosts = <String>[];

  @override
  Future<LocalNetworkPermissionState> status(String host) async {
    hosts.add(host);
    return state;
  }

  @override
  Future<LocalNetworkPermissionState> request(String host) =>
      fail('The client must never prompt');
}

/// One request as a server saw it.
class Received {
  Received(this.method, this.target, this.headers, this.body);

  final String method;

  /// Path and query as sent, still encoded.
  final String target;

  /// Names are lower case; repeated values are joined with a comma.
  final Map<String, String> headers;
  final String body;
}

/// A plain HTTP server on loopback.
class TestServer {
  TestServer._(this._server);

  final HttpServer _server;
  final requests = <Received>[];

  int get port => _server.port;

  Uri url([String path = '']) => Uri.parse('http://127.0.0.1:$port$path');

  /// [answer] writes and closes the response. Without it, every request gets
  /// `200 {}`.
  static Future<TestServer> start([
    Future<void> Function(Received received, HttpResponse response)? answer,
  ]) async {
    final server = TestServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(() => server._server.close(force: true));
    server._server.listen((request) async {
      final headers = <String, String>{};
      request.headers.forEach(
        (name, values) => headers[name] = values.join(','),
      );
      final received = Received(
        request.method,
        request.uri.toString(),
        headers,
        await utf8.decodeStream(request),
      );
      server.requests.add(received);
      await (answer == null
          ? reply(request.response)
          : answer(received, request.response));
    });
    return server;
  }
}

/// Answers with [body] in UTF-8.
Future<void> reply(
  HttpResponse response, {
  int status = 200,
  String body = '{}',
  String contentType = 'application/json',
  Map<String, String> headers = const {},
}) {
  response.statusCode = status;
  response.headers.set('content-type', contentType);
  headers.forEach(response.headers.set);
  response.add(utf8.encode(body));
  return response.close();
}

/// The length of the first HTTP request in [bytes], once all of it is there.
int? _requestLength(List<int> bytes) {
  final text = latin1.decode(bytes);
  final end = text.indexOf('\r\n\r\n');
  if (end < 0) return null;
  final length = RegExp(
    r'content-length: *(\d+)',
    caseSensitive: false,
  ).firstMatch(text.substring(0, end))?[1];
  final total = end + 4 + int.parse(length ?? '0');
  return bytes.length < total ? null : total;
}

/// A TCP server that leaves the answer, if any, to the test.
class RawServer {
  RawServer._(this._server);

  final ServerSocket _server;
  final _sockets = <Socket>[];

  /// Connections accepted, whether or not anything was sent on them.
  int connections = 0;

  /// Every byte received, on any connection.
  final bytes = <int>[];

  /// Complete requests, as text.
  final requests = <String>[];

  int get port => _server.port;

  Uri url([String path = '']) => Uri.parse('http://127.0.0.1:$port$path');

  static Future<RawServer> start([
    void Function(Socket socket, String request)? onRequest,
  ]) async {
    final server = RawServer._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(() async {
      for (final socket in server._sockets) {
        socket.destroy();
      }
      await server._server.close();
    });
    server._server.listen((socket) {
      server.connections++;
      server._sockets.add(socket);
      // A client that goes away must not fail the test from the server side.
      socket.done.ignore();
      final pending = <int>[];
      socket.listen((data) {
        server.bytes.addAll(data);
        pending.addAll(data);
        for (
          var length = _requestLength(pending);
          length != null;
          length = _requestLength(pending)
        ) {
          final text = latin1.decode(pending.sublist(0, length));
          pending.removeRange(0, length);
          server.requests.add(text);
          onRequest?.call(socket, text);
        }
      }, onError: (Object _) {});
    });
    return server;
  }
}

/// A TLS server that records the application bytes that reach it, which is
/// what proves that a refused certificate got nothing.
class TlsServer {
  TlsServer._(this._server);

  final ServerSocket _server;
  final _sockets = <Socket>[];
  final _closed = <Future<void>>[];

  /// TCP connections accepted, whether or not the handshake finished.
  int connections = 0;

  /// Every decrypted byte received, on any connection.
  final bytes = <int>[];

  String get received => latin1.decode(bytes);

  int get port => _server.port;

  Uri url([String path = '']) => Uri.parse('https://127.0.0.1:$port$path');

  /// Waits until the client has dropped every connection, so that whatever it
  /// sent has arrived. Fails if it keeps one open.
  Future<void> closedByClient() async {
    await pause();
    await Future.wait(_closed).timeout(const Duration(seconds: 5));
  }

  /// Every complete request gets [response], and the connection stays open.
  static Future<TlsServer> start(
    SecurityContext context, {
    String response =
        'HTTP/1.1 200 OK\r\n'
        'content-type: application/json\r\n'
        'content-length: 2\r\n'
        '\r\n'
        '{}',
  }) async {
    final server = TlsServer._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(() async {
      for (final socket in server._sockets) {
        socket.destroy();
      }
      await server._server.close();
    });
    server._server.listen((raw) {
      server.connections++;
      server._sockets.add(raw);
      final closed = Completer<void>();
      server._closed.add(closed.future);
      void close() {
        if (!closed.isCompleted) closed.complete();
      }

      unawaited(
        SecureSocket.secureServer(raw, context).then(
          (socket) {
            server._sockets.add(socket);
            socket.done.ignore();
            final pending = <int>[];
            socket.listen(
              (data) {
                server.bytes.addAll(data);
                pending.addAll(data);
                for (
                  var length = _requestLength(pending);
                  length != null;
                  length = _requestLength(pending)
                ) {
                  pending.removeRange(0, length);
                  socket.add(latin1.encode(response));
                }
              },
              onError: (Object _) => close(),
              onDone: close,
            );
          },
          // The client refused the handshake.
          onError: (Object _) => close(),
        ),
      );
    });
    return server;
  }
}
