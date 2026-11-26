/// The per-instance HTTP client: authentication, headers and request encoding
/// over plain HTTP (research R4, data-model.md Instance and Credential).
///
/// The network tests are written before the code (T022). The API they expect,
/// exported by `package:core/core.dart`:
///
/// ```dart
/// // lib/src/network/connection_settings.dart
/// final class ConnectionSettings {
///   const ConnectionSettings({
///     required Uri url, // the instance's address, maybe with a sub-path
///     required AuthKind authKind,
///     Credential credential = const Credential(),
///     String? certPin,
///     String? customCa,
///   });
/// }
///
/// // lib/src/network/client.dart (T023; trust.dart, T024, is used by it)
/// final class InstanceHttpClient implements ServiceHttpClient {
///   // Settings of the caller's choosing: the add and edit form's unsaved ones.
///   InstanceHttpClient({
///     required Future<ConnectionSettings?> Function() settings,
///     required ApiKeyHeader? apiKeyHeader, // the module descriptor's
///     required DiagnosticLog log,
///     required LocalNetworkPermission localNetwork,
///     Duration timeout = const Duration(seconds: 30), // of one attempt
///   });
///
///   // The settings of a saved instance.
///   InstanceHttpClient.saved({
///     required ProfileRepository profiles,
///     required String instanceId,
///     required ApiKeyHeader? apiKeyHeader,
///     required DiagnosticLog log,
///     required LocalNetworkPermission localNetwork,
///     Duration timeout = const Duration(seconds: 30),
///   });
///
///   void close();
/// }
/// ```
///
/// What the signatures do not show:
///
/// - The settings are loaded for every `send`, and are the only source of that
///   send's address, credential and trust. Nothing read for an earlier send is
///   used, including a pooled connection made under other trust.
/// - [InstanceHttpClient.saved] loads them with
///   `ProfileRepository.instanceWithCredential`, never by reading the instance
///   and the credential separately (settings_test.dart). No stored credential
///   is an empty one.
/// - If there are no settings (null, or no such instance), loading them throws,
///   or a header value cannot be sent, `send` returns an [Err] of any failure
///   and sends nothing.
/// - The API key is sent only with [AuthKind.apiKey], in `apiKeyHeader`. The
///   session cookie is sent whatever the kind, joined with `; ` to a `Cookie`
///   of the request. Basic authentication and custom headers are always sent.
///   `username` and `password` are not sent: signing in is T028's.
/// - Neither `Origin` nor `Referer` is sent.
/// - The client never prompts for the local network permission, and never
///   sets `Instance.authFailed` (T028).
///
/// Redirects are in redirect_test.dart, retries in retry_test.dart, failure
/// classification in failure_test.dart, redaction in redaction_test.dart and
/// certificates (T024) in trust_test.dart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('plain HTTP carries the key, basic auth and custom headers', () async {
    final server = await TestServer.start((_, response) {
      response.headers
        ..add('set-cookie', 'a=1')
        ..add('set-cookie', 'b=2');
      return reply(response, body: '{"ok":true}', headers: {'X-Server': 'yes'});
    });
    final client = clientFor(settingsFor(server.url('/radarr')));

    final response = expectOk(await client.send(get('api/v3/movie')));

    expect(response.statusCode, 200);
    expect(response.text, '{"ok":true}');
    expect(response.headers['x-server'], ['yes']);
    expect(response.headers['set-cookie'], ['a=1', 'b=2']);
    final received = server.requests.single;
    expect(received.method, 'GET');
    expect(received.target, '/radarr/api/v3/movie');
    expect(received.headers['host'], '127.0.0.1:${server.port}');
    expect(received.headers['x-api-key'], apiKey);
    expect(received.headers['authorization'], basicHeader);
    expect(received.headers['x-proxy-id'], customValue);
    expect(received.headers, isNot(contains('origin')));
    expect(received.headers, isNot(contains('referer')));
    expect(received.headers.values.join(), isNot(contains(password)));
  });

  test('the module chooses the header of the API key', () async {
    final server = await TestServer.start();
    final client = clientFor(
      settingsFor(server.url(), credential: const Credential(apiKey: apiKey)),
      header: const ApiKeyHeader('Authorization', prefix: 'Bearer '),
    );

    expectOk(await client.send(get()));

    final headers = server.requests.single.headers;
    expect(headers['authorization'], 'Bearer $apiKey');
    expect(headers, isNot(contains('x-api-key')));
    expect(headers, isNot(contains('cookie')));
  });

  for (final authKind in [
    AuthKind.userPassword,
    AuthKind.mediaServerAccount,
    AuthKind.none,
  ]) {
    test('${authKind.name} sends the session and no key or login', () async {
      final server = await TestServer.start();
      final client = clientFor(settingsFor(server.url(), authKind: authKind));

      expectOk(
        await client.send(
          ServiceRequest(
            HttpMethod.get,
            'api',
            headers: {'Cookie': '_csrf=abc', 'X-Extra': 'one'},
          ),
        ),
      );

      final received = server.requests.single;
      expect(
        received.headers['cookie']?.split('; '),
        unorderedEquals([sessionCookie, '_csrf=abc']),
      );
      expect(received.headers['x-extra'], 'one');
      expect(received.headers['authorization'], basicHeader);
      expect(received.headers, isNot(contains('x-api-key')));
      final sent = '${received.target}${received.headers}${received.body}';
      expect(sent, isNot(contains(apiKey)));
      expect(sent, isNot(contains(username)));
      expect(sent, isNot(contains(password)));
    });
  }

  test('a proxy of the environment gets nothing', () async {
    final proxy = await RawServer.start();
    final server = await TestServer.start();

    // What the environment variables would make `HttpClient` do by default.
    await HttpOverrides.runZoned(() async {
      final client = clientFor(
        settingsFor(server.url()),
        timeout: const Duration(seconds: 2),
      );
      expectOk(await client.send(get()));
    }, findProxyFromEnvironment: (_, _) => 'PROXY 127.0.0.1:${proxy.port}');

    expect(proxy.connections, 0);
    expect(server.requests, hasLength(1));
  });

  // A pin says which certificate to expect, and there is none.
  for (final (name, customCa) in [
    ('', null),
    (' and an authority', 'a certificate'),
  ]) {
    test('a certificate pin$name over plain HTTP sends nothing', () async {
      final server = await RawServer.start();
      final client = clientFor(
        settingsFor(server.url(), certPin: '0' * 64, customCa: customCa),
        timeout: const Duration(seconds: 2),
      );

      expectError(await client.send(get()));

      await pause();
      expect(server.bytes, isEmpty);
    });
  }

  // An authority only adds trust, so plain HTTP loses nothing without it. An
  // instance keeps it when its address is changed to http.
  test('a certificate authority is ignored over plain HTTP', () async {
    final server = await TestServer.start();
    final client = clientFor(settingsFor(server.url(), customCa: 'not read'));

    expectOk(await client.send(get()));

    expect(server.requests.single.headers['x-api-key'], apiKey);
  });

  test('the path and query are percent-encoded per RFC 3986', () async {
    final server = await TestServer.start();
    // A trailing slash of the address does not double.
    final client = clientFor(settingsFor(server.url('/sub/')));

    expectOk(
      await client.send(
        ServiceRequest(
          HttpMethod.get,
          'api/v1/a b',
          query: {
            'query': ["a b+c!'()*&=#?/é"],
            'id': ['1', '2'],
          },
        ),
      ),
    );

    expect(
      server.requests.single.target,
      '/sub/api/v1/a%20b'
      '?query=a%20b%2Bc%21%27%28%29%2A%26%3D%23%3F%2F%C3%A9&id=1&id=2',
    );
  });

  for (final method in writeMethods) {
    test('${method.name} sends a JSON body once', () async {
      final server = await TestServer.start(
        (_, response) => reply(response, status: 201),
      );
      final client = clientFor(settingsFor(server.url()));

      expect(expectOk(await client.send(request(method))).statusCode, 201);

      final received = server.requests.single;
      expect(received.method, method.name.toUpperCase());
      expect(received.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(received.body), {'id': 1});
      expect(received.headers['x-api-key'], apiKey);
    });
  }

  test('a form body is URL encoded', () async {
    final server = await TestServer.start();
    final client = clientFor(settingsFor(server.url()));
    const fields = {'username': 'a b', 'password': 'p&=+é'};

    expectOk(
      await client.send(
        ServiceRequest(HttpMethod.post, 'login', body: const FormBody(fields)),
      ),
    );

    final received = server.requests.single;
    expect(
      received.headers['content-type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    expect(Uri.splitQueryString(received.body), fields);
  });
}
