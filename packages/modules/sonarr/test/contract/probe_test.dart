// The Sonarr connection test (FR-007).
//
// The status, 401 and rejected host answers are those of Sonarr 4.0.20.3014 in
// the dev stack's image. The status body passed tool/sanitize_fixture.dart; the
// other versions and products are that recording with the field changed.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarr/sonarr_module.dart';

import '../allow_list.dart';

const _json = 'application/json; charset=utf-8';
const _html = 'text/html';

// ASP.NET Core's host filtering, which answers before Sonarr sees the request
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

Map<String, Object?> _status() => jsonDecode(
  File('test/fixtures/4.0.20.3014/system_status.json').readAsStringSync(),
) as Map<String, Object?>;

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
    _ok(jsonEncode({..._status(), ...changes}));

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

class _FakeCache extends Fake implements CacheScope {}

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
    SonarrModule().probe(
      InstanceContext(
        instance: Instance(
          id: 'i1',
          profileId: 'p1',
          name: 'Home',
          serviceType: 'sonarr',
          url: Uri.parse('http://server.test/sonarr'),
          authKind: AuthKind.apiKey,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        http: AllowListClient(allowList, server),
        artwork: _FakeArtwork(),
        navigator: _FakeNavigator(),
        cache: _FakeCache(),
        logger: _FakeLogger(),
      ),
    );

Future<ProbeResult> _found(Result<ServiceResponse, HttpError> answer) async {
  final result = await _probe(_FakeHttp(answer));
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => fail('probe failed with $error'),
  };
}

Future<ServiceFailure> _failure(
  Result<ServiceResponse, HttpError> answer,
) async {
  final result = await _probe(_FakeHttp(answer));
  return switch (result) {
    Ok(:final value) => fail('probe accepted version ${value.version}'),
    Err(:final error) => error,
  };
}

void main() {
  test('describes how to reach Sonarr', () {
    final module = SonarrModule();
    final descriptor = module.descriptor;

    expect(module.id, 'sonarr');
    expect(descriptor.displayName, 'Sonarr');
    expect(descriptor.category, ModuleCategory.series);
    expect(descriptor.authKinds, [AuthKind.apiKey]);
    expect(descriptor.apiKeyHeader?.name, 'X-Api-Key');
    expect(descriptor.apiKeyHeader?.prefix, '');
    expect(descriptor.defaultPort, 8989);
    expect(descriptor.minimumVersion, startsWith('4.0'));
    expect(module.sessionHandler, isNull);
  });

  group('success', () {
    test('reads the status once and reports product and version', () async {
      final http = _FakeHttp(_statusWith({}));

      final result = await _probe(http);

      expect(
        result,
        isA<Ok<ProbeResult, ServiceFailure>>()
            .having((ok) => ok.value.product, 'product', 'Sonarr')
            .having((ok) => ok.value.version, 'version', '4.0.20.3014')
            .having((ok) => ok.value.newerThanTested, 'newer', isFalse)
            .having((ok) => ok.value.session, 'session', isNull),
      );
      final request = http.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/system/status');
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });
  });

  group('wrong service', () {
    test('another product of the family', () async {
      final answer = _statusWith({
        'appName': 'Radarr',
        'version': '7.0.3.10918',
      });

      expect(await _failure(answer), isA<WrongService>());
    });

    // The product is judged before the version.
    test('another product with a version below the minimum', () async {
      final answer = _statusWith({'appName': 'Lidarr', 'version': '2.0.0.0'});

      expect(await _failure(answer), isA<WrongService>());
    });

    // What a service without a v3 API answers.
    test('no status resource', () async {
      final answer = _err(const NotFound(), _response(404, ''));

      expect(await _failure(answer), isA<WrongService>());
    });

    for (final body in [
      '{"status": "ok"}',
      '{"appName": null, "version": "4.0.20.3014"}',
      '[]',
    ]) {
      test('JSON that is no status: $body', () async {
        expect(await _failure(_ok(body)), isA<WrongService>());
      });
    }
  });

  group('authentication', () {
    test('a rejected key is reported and not tried again', () async {
      // Sonarr sends no body and no version header with it.
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
      ('a rejected host', const HostRejected()),
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
    // Sonarr 3 answers this path with the same fields.
    test('older than supported is refused, naming the version', () async {
      final answer = _statusWith({'version': '3.0.9.1549'});

      expect(
        await _failure(answer),
        isA<UnsupportedVersion>().having(
          (failure) => failure.version,
          'version',
          '3.0.9.1549',
        ),
      );
    });

    test('the first release of the minimum is accepted', () async {
      final found = await _found(_statusWith({'version': '4.0.0.741'}));

      expect(found.newerThanTested, isFalse);
    });

    test('the newest tested version carries no notice', () async {
      final tested = SonarrModule().descriptor.testedVersion;

      final found = await _found(_statusWith({'version': tested}));

      expect(found.newerThanTested, isFalse);
    });

    // The tested line is the dev stack's 4.0. 5 is the v5 beta through the v3
    // API; 10 sorts before 4 as text.
    for (final version in ['4.1.0.0', '5.0.0.100', '10.0.0.1']) {
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
    ]) {
      test('${failure.runtimeType} is passed on', () async {
        expect(await _failure(_err(failure)), same(failure));
      });
    }

    test('Sonarr still starting is a server error', () async {
      const failure = ServerError(statusCode: 503);
      final answer = _err(
        failure,
        _response(
          503,
          '{"errorMessage": "Sonarr is starting up, please try again later"}',
          contentType: 'application/json',
        ),
      );

      expect(await _failure(answer), same(failure));
    });

    test('a bad gateway page is a server error', () async {
      const failure = ServerError(statusCode: 502);
      final answer = _err(
        failure,
        _response(
          502,
          '<html><body>Bad Gateway</body></html>',
          contentType: _html,
        ),
      );

      expect(await _failure(answer), same(failure));
    });

    for (final (name, body) in [
      ('cut off', '{"appName": "Sonarr", "vers'),
      ('without a version', '{"appName": "Sonarr"}'),
      ('with a number for a version', '{"appName": "Sonarr", "version": 4}'),
      ('with an empty version', '{"appName": "Sonarr", "version": ""}'),
      ('with a word for a version', '{"appName": "Sonarr", "version": "x"}'),
    ]) {
      test('a status $name is malformed', () async {
        expect(await _failure(_ok(body)), isA<MalformedResponse>());
      });
    }
  });
}
