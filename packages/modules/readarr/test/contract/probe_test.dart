// The Readarr connection test (FR-007) and what a probed server offers, for
// Readarr and its fork Bookshelf, which both say they are `Readarr`.
//
// The status bodies were recorded from Readarr 0.4.18.2805 and Bookshelf
// 0.4.21.182 and passed tool/sanitize_fixture.dart; the other versions and
// products are the first with the field changed. The rejected host and proxy
// pages are those ASP.NET Core and the dev stack's login proxy answer with.
//
// Readarr is retired upstream, so 0.4 is the last of it and later versions are
// Bookshelf's.

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readarr/readarr_module.dart';

import '../allow_list.dart';
import 'support.dart';

const _json = 'application/json; charset=utf-8';
const _html = 'text/html';

// ASP.NET Core's host filtering, which answers before Readarr sees the request
// when `AllowedHosts` does not name the host.
const _rejectedHost =
    '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"'
    '"http://www.w3.org/TR/html4/strict.dtd">\r\n'
    '<HTML><HEAD><TITLE>Bad Request</TITLE>\r\n'
    '<META HTTP-EQUIV="Content-Type" Content="text/html; charset=us-ascii">'
    '</ HEAD >\r\n'
    '<BODY><h2>Bad Request - Invalid Hostname</h2>\r\n'
    '<hr><p>HTTP Error 400. The request hostname is invalid.</p>\r\n'
    '</BODY></HTML>';

// The page of the dev stack's login proxy, tool/devstack/proxy/login.conf.
const _loginPage = '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Sign in</title></head>
<body>
<h1>Sign in to continue</h1>
<form method="post" action="/login">
<label>User name <input name="username"></label>
<label>Password <input name="password" type="password"></label>
<button type="submit">Sign in</button>
</form>
</body>
</html>
''';

ServiceResponse _response(int statusCode, String body, {String? contentType}) =>
    ServiceResponse(
      statusCode: statusCode,
      headers: {
        if (contentType != null) 'content-type': [contentType],
      },
      bytes: Uint8List.fromList(utf8.encode(body)),
    );

Result<ServiceResponse, HttpError> _ok(
  String body, {
  String contentType = _json,
}) => Ok(_response(200, body, contentType: contentType));

Result<ServiceResponse, HttpError> _statusWith(Map<String, Object?> changes) =>
    _ok(jsonEncode({...record('system_status'), ...changes}));

Result<ServiceResponse, HttpError> _err(
  ServiceFailure failure, [
  ServiceResponse? response,
]) => Err(HttpError(failure, response: response));

/// Answers every request with the same result and records what was asked.
class _FakeHttp implements ServiceHttpClient {
  _FakeHttp(this.result);

  final Result<ServiceResponse, HttpError> result;
  final requests = <ServiceRequest>[];

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    return result;
  }
}

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

class _FakeLogger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// Probes [server] through the allow-list.
Future<Result<ProbeResult, ServiceFailure>> _probe(_FakeHttp server) =>
    ReadarrModule().probe(
      InstanceContext(
        instance: Instance(
          id: instanceId,
          profileId: 'p1',
          name: 'Home',
          serviceType: 'readarr',
          url: Uri.parse('http://server.test/readarr'),
          authKind: AuthKind.apiKey,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        http: AllowListClient(allowList, server),
        artwork: _FakeArtwork(),
        navigator: _FakeNavigator(),
        cache: FakeCache(),
        logger: _FakeLogger(),
      ),
    );

Future<ProbeResult> _found(Result<ServiceResponse, HttpError> answer) async =>
    switch (await _probe(_FakeHttp(answer))) {
      Ok(:final value) => value,
      Err(:final error) => fail('probe failed with $error'),
    };

Future<ServiceFailure> _failure(
  Result<ServiceResponse, HttpError> answer,
) async => switch (await _probe(_FakeHttp(answer))) {
  Ok(:final value) => fail('probe accepted version ${value.version}'),
  Err(:final error) => error,
};

void main() {
  test('describes how to reach Readarr', () {
    final module = ReadarrModule();
    final descriptor = module.descriptor;

    expect(module.id, 'readarr');
    expect(descriptor.displayName, 'Readarr');
    expect(descriptor.category, ModuleCategory.books);
    expect(descriptor.authKinds, [AuthKind.apiKey]);
    expect(descriptor.apiKeyHeader?.name, 'X-Api-Key');
    expect(descriptor.apiKeyHeader?.prefix, '');
    expect(descriptor.defaultPort, 8787);
    expect(descriptor.minimumVersion, startsWith('0.4'));
    // The later of the two recorded, so that neither is called untested.
    expect(descriptor.testedVersion, bookshelfVersion);
    expect(module.sessionHandler, isNull);
  });

  test('offers every capability of the Servarr family', () {
    expect(
      ReadarrModule().capabilitiesFor(
        const ProbeResult(
          product: 'Readarr',
          version: recordedVersion,
          newerThanTested: false,
        ),
        null,
      ),
      {
        CapabilityKind.library,
        CapabilityKind.lookup,
        CapabilityKind.command,
        CapabilityKind.release,
        CapabilityKind.queue,
        CapabilityKind.history,
        CapabilityKind.calendar,
        CapabilityKind.wanted,
        CapabilityKind.health,
      },
    );
  });

  test('reads the status once and reports product and version', () async {
    final http = _FakeHttp(_statusWith({}));

    final result = await _probe(http);

    expect(
      result,
      isA<Ok<ProbeResult, ServiceFailure>>()
          .having((ok) => ok.value.product, 'product', 'Readarr')
          .having((ok) => ok.value.version, 'version', recordedVersion)
          .having((ok) => ok.value.newerThanTested, 'newer', isFalse)
          .having((ok) => ok.value.session, 'session', isNull),
    );
    final request = http.requests.single;
    expect(request.method, HttpMethod.get);
    expect(request.path, 'api/v1/system/status');
    expect(request.query, isEmpty);
    expect(request.body, isNull);
  });

  test('accepts Bookshelf, which says it is Readarr', () async {
    final status = record('system_status', bookshelfVersion);
    expect(status['appName'], 'Readarr');

    final found = await _found(
      _ok(jsonEncode({...status, 'version': bookshelfVersion})),
    );

    expect(found.product, 'Readarr');
    expect(found.version, bookshelfVersion);
    expect(found.newerThanTested, isFalse);
  });

  group('wrong service', () {
    test('another product of the family', () async {
      final answer = _statusWith({
        'appName': 'Lidarr',
        'version': '3.1.6.5079',
      });

      expect(await _failure(answer), isA<WrongService>());
    });

    // The product is judged before the version.
    test('another product with a newer version', () async {
      final answer = _statusWith({
        'appName': 'Radarr',
        'version': '7.0.3.10918',
      });

      expect(await _failure(answer), isA<WrongService>());
    });

    // What a service without a v1 API answers.
    test('no status resource', () async {
      final answer = _err(const NotFound(), _response(404, ''));

      expect(await _failure(answer), isA<WrongService>());
    });

    for (final body in [
      '{"status": "ok"}',
      '{"appName": null, "version": "0.4.18.2805"}',
      '[]',
    ]) {
      test('JSON that is no status: $body', () async {
        expect(await _failure(_ok(body)), isA<WrongService>());
      });
    }
  });

  test('a rejected key is reported and not tried again', () async {
    final http = _FakeHttp(_err(const AuthFailed(), _response(401, '')));

    final result = await _probe(http);

    expect(
      result,
      isA<Err<ProbeResult, ServiceFailure>>().having(
        (err) => err.error,
        'error',
        isA<AuthFailed>(),
      ),
    );
    expect(http.requests, hasLength(1));
  });

  group('proxy page', () {
    test('a login page instead of data', () async {
      final answer = _ok(_loginPage, contentType: 'text/html; charset=utf-8');

      expect(await _failure(answer), isA<ProxyInterception>());
    });

    test('a page without a content type', () async {
      final answer = Ok<ServiceResponse, HttpError>(
        _response(200, '\n  <!doctype html><html><body>Sign in</body></html>'),
      );

      expect(await _failure(answer), isA<ProxyInterception>());
    });
  });

  group('host rejected', () {
    // The core's own reading of a 400 is not settled, so none may matter.
    for (final (name, failure) in <(String, ServiceFailure)>[
      ('a validation failure', const Validation([])),
      ('a server error', const ServerError(statusCode: 400)),
      ('a malformed response', const MalformedResponse()),
    ]) {
      test('when the core calls the answer $name', () async {
        final answer = _err(
          failure,
          _response(400, _rejectedHost, contentType: _html),
        );

        expect(await _failure(answer), isA<HostRejected>());
      });
    }

    test('another bad request is not a rejected host', () async {
      const failure = Validation(['Invalid request']);
      final answer = _err(
        failure,
        _response(400, '{"message": "Invalid request"}', contentType: _json),
      );

      expect(await _failure(answer), same(failure));
    });
  });

  group('version', () {
    test('older than supported is refused, naming the version', () async {
      final answer = _statusWith({'version': '0.3.32.1587'});

      expect(
        await _failure(answer),
        isA<UnsupportedVersion>().having(
          (failure) => failure.version,
          'version',
          '0.3.32.1587',
        ),
      );
    });

    // The first release of the minimum, and one between the two recorded.
    for (final version in ['0.4.0.0', '0.4.20.130']) {
      test('$version is accepted', () async {
        final found = await _found(_statusWith({'version': version}));

        expect(found.version, version);
        expect(found.newerThanTested, isFalse);
      });
    }

    // 10 sorts before 4 as text.
    for (final version in ['0.4.21.183', '0.5.0.1', '10.0.0.1']) {
      test('$version is accepted as newer than tested', () async {
        final found = await _found(_statusWith({'version': version}));

        expect(found.version, version);
        expect(found.newerThanTested, isTrue);
      });
    }
  });

  group('other failures', () {
    for (final failure in <ServiceFailure>[
      const Unreachable(),
      const DnsFailure(),
      const CertificateUntrusted(CertificateInfo(sha256: '00')),
      const CertificateChanged(CertificateInfo(sha256: '00')),
      const Redirected(host: 'login.example.test'),
      const PermissionDenied(),
      const Forbidden(),
      const ProxyInterception(),
      const ServerError(statusCode: 503),
    ]) {
      test('${failure.runtimeType} is passed on', () async {
        expect(await _failure(_err(failure)), same(failure));
      });
    }

    for (final (name, body) in [
      ('cut off', '{"appName": "Readarr", "vers'),
      ('without a version', '{"appName": "Readarr"}'),
      ('with a number for a version', '{"appName": "Readarr", "version": 3}'),
      ('with a word for a version', '{"appName": "Readarr", "version": "x"}'),
    ]) {
      test('a status $name is malformed', () async {
        expect(await _failure(_ok(body)), isA<MalformedResponse>());
      });
    }
  });
}
