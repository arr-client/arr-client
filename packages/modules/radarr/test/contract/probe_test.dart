// The Radarr probe against recorded answers (FR-007, spec story 1).
//
// test/fixtures/7.0.3.10918/system_status.json and the rejected-host, 401 and
// 404 answers below were recorded from the dev stack's Radarr 7.0.3.10918; the
// JSON went through tool/sanitize_fixture.dart. The core client does not exist
// in these tests: a fake answers as `ServiceHttpClient` says it does, with
// success statuses as `Ok` and the rest as a classified `HttpError`.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import '../allow_list.dart';

// What Radarr answers with 400 when its allowed hosts do not include the
// request's host name (ASP.NET Core host filtering).
const _invalidHostPage =
    '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"'
    '"http://www.w3.org/TR/html4/strict.dtd">\r\n'
    '<HTML><HEAD><TITLE>Bad Request</TITLE>\r\n'
    '<META HTTP-EQUIV="Content-Type" Content="text/html; charset=us-ascii">'
    '</ HEAD >\r\n'
    '<BODY><h2>Bad Request - Invalid Hostname</h2>\r\n'
    '<hr><p>HTTP Error 400. The request hostname is invalid.</p>\r\n'
    '</BODY></HTML>';

// As tool/devstack/proxy/login.conf serves it.
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

final Map<String, Object?> _status = jsonDecode(
  File('test/fixtures/7.0.3.10918/system_status.json').readAsStringSync(),
) as Map<String, Object?>;

ServiceResponse _response(int statusCode, String body, {String? type}) =>
    ServiceResponse(
      statusCode: statusCode,
      bytes: utf8.encode(body),
      headers: {
        if (type != null) 'content-type': [type],
      },
    );

Result<ServiceResponse, HttpError> _ok(String body, {String? type}) =>
    Ok(_response(200, body, type: type));

Result<ServiceResponse, HttpError> _json(Object? value) =>
    _ok(jsonEncode(value), type: 'application/json; charset=utf-8');

Result<ServiceResponse, HttpError> _statusWith(Map<String, Object?> changes) =>
    _json({..._status, ...changes});

Result<ServiceResponse, HttpError> _error(
  ServiceFailure failure, {
  int? status,
  String body = '',
  String? type,
}) => Err(
  HttpError(
    failure,
    response: status == null ? null : _response(status, body, type: type),
  ),
);

/// Answers every request with the same result and records what was asked.
class _FakeHttp implements ServiceHttpClient {
  _FakeHttp(this.answer);

  final Result<ServiceResponse, HttpError> answer;
  final requests = <ServiceRequest>[];

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    return answer;
  }
}

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

class _FakeCache extends Fake implements CacheScope {}

class _SilentLogger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

InstanceContext _context(ServiceHttpClient http) => InstanceContext(
  instance: Instance(
    id: 'i1',
    profileId: 'p1',
    name: 'Home',
    serviceType: 'radarr',
    url: Uri.parse('http://server.test/radarr'),
    authKind: AuthKind.apiKey,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  http: http,
  artwork: _FakeArtwork(),
  navigator: _FakeNavigator(),
  cache: _FakeCache(),
  logger: _SilentLogger(),
);

/// Probes a server that gives [answer], through the Radarr allow-list.
Future<Result<ProbeResult, ServiceFailure>> _probe(
  Result<ServiceResponse, HttpError> answer,
) => RadarrModule().probe(
  _context(AllowListClient(allowList, _FakeHttp(answer))),
);

Future<ProbeResult> _success(Result<ServiceResponse, HttpError> answer) async =>
    switch (await _probe(answer)) {
      Ok(:final value) => value,
      Err(:final error) => fail('Expected success, got $error'),
    };

Future<ServiceFailure> _failure(
  Result<ServiceResponse, HttpError> answer,
) async => switch (await _probe(answer)) {
  Ok(:final value) => fail(
    'Expected a failure, got ${value.product} ${value.version}',
  ),
  Err(:final error) => error,
};

void main() {
  group('descriptor', () {
    final module = RadarrModule();

    test('identifies Radarr', () {
      expect(module.id, 'radarr');
      expect(module.descriptor.displayName, 'Radarr');
      expect(module.descriptor.category, ModuleCategory.movies);
      expect(module.descriptor.defaultPort, 7878);
    });

    test('authenticates with an API key in X-Api-Key', () {
      expect(module.descriptor.authKinds, [AuthKind.apiKey]);
      expect(module.descriptor.apiKeyHeader?.name, 'X-Api-Key');
      expect(module.descriptor.apiKeyHeader?.prefix, '');
      expect(module.sessionHandler, isNull);
    });

    test('states the supported minimum version', () {
      expect(module.descriptor.minimumVersion, '5.6');
    });
  });

  group('success', () {
    test('asks for the system status, once', () async {
      final http = _FakeHttp(_json(_status));

      await RadarrModule().probe(_context(AllowListClient(allowList, http)));

      final request = http.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/system/status');
      // The key goes in a header, which the core client adds.
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });

    test('reports the product and version', () async {
      final result = await _success(_json(_status));

      expect(result.product, 'Radarr');
      expect(result.version, '7.0.3.10918');
      expect(result.newerThanTested, isFalse);
      expect(result.session, isNull);
    });

    test('ignores fields it does not know', () async {
      final result = await _success(
        _statusWith({
          'someFutureField': {'a': 1},
          'databaseType': 'someFutureDatabase',
        }),
      );

      expect(result.version, '7.0.3.10918');
    });
  });

  group('version', () {
    for (final version in [
      '5.6.0.8846',
      // Newer than 5.6, although it sorts before it as text.
      '5.10.4.9218',
      '6.4.4.10685',
    ]) {
      test('accepts $version', () async {
        final result = await _success(_statusWith({'version': version}));

        expect(result.version, version);
        expect(result.newerThanTested, isFalse);
      });
    }

    test('does not call the tested version newer than tested', () async {
      final tested = RadarrModule().descriptor.testedVersion;

      final result = await _success(_statusWith({'version': tested}));

      expect(result.newerThanTested, isFalse);
    });

    for (final version in ['5.5.3.8819', '4.7.5.7809', '3.2.2.5080']) {
      test('refuses $version as too old', () async {
        final failure = await _failure(_statusWith({'version': version}));

        expect(
          failure,
          isA<UnsupportedVersion>().having(
            (f) => f.version,
            'version',
            version,
          ),
        );
      });
    }

    // The tested line is the dev stack's 7.0.
    for (final version in [
      '7.1.0.10948',
      '8.0.0.11000',
      // Sorts before 7 as text.
      '10.0.0.12000',
    ]) {
      test('accepts $version with the newer-than-tested notice', () async {
        final result = await _success(_statusWith({'version': version}));

        expect(result.version, version);
        expect(result.newerThanTested, isTrue);
      });
    }

    final unreadable = <String, Map<String, Object?>>{
      'no version': {'appName': 'Radarr'},
      'an empty version': {'appName': 'Radarr', 'version': ''},
      'a version that is not text': {'appName': 'Radarr', 'version': 7},
      'a version that is not a number': {
        'appName': 'Radarr',
        'version': 'unknown',
      },
    };
    for (final MapEntry(key: name, value: body) in unreadable.entries) {
      test('cannot understand a status with $name', () async {
        expect(await _failure(_json(body)), isA<MalformedResponse>());
      });
    }
  });

  group('wrong service', () {
    test('recognises another service of the family', () async {
      // Sonarr serves the same path; its version is below Radarr's minimum,
      // which must not decide the answer.
      final failure = await _failure(
        _statusWith({'appName': 'Sonarr', 'version': '4.0.20.3014'}),
      );

      expect(failure, isA<WrongService>());
    });

    test('recognises a server without the v3 interface', () async {
      // Lidarr, Prowlarr and unrelated servers answer 404.
      final failure = await _failure(_error(const NotFound(), status: 404));

      expect(failure, isA<WrongService>());
    });

    final strangers = <String, Object?>{
      'an object without an application name': {'version': '7.0.3'},
      'a list': <Object?>[],
      'a bare text': 'ok',
    };
    for (final MapEntry(key: name, value: body) in strangers.entries) {
      test('recognises $name', () async {
        expect(await _failure(_json(body)), isA<WrongService>());
      });
    }

    test('cannot understand JSON that breaks off', () async {
      final failure = await _failure(
        _ok('{"appName":"Rad', type: 'application/json; charset=utf-8'),
      );

      expect(failure, isA<MalformedResponse>());
    });
  });

  group('authentication', () {
    test('reports a rejected key and does not try again', () async {
      // Radarr answers a wrong key with 401 and no body.
      final http = _FakeHttp(_error(const AuthFailed(), status: 401));

      final result = await RadarrModule().probe(
        _context(AllowListClient(allowList, http)),
      );

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

    test('reports a refused identity', () async {
      final failure = await _failure(_error(const Forbidden(), status: 403));

      expect(failure, isA<Forbidden>());
    });
  });

  group('proxy page', () {
    test('recognises a login page served as success', () async {
      final failure = await _failure(
        _ok(_loginPage, type: 'text/html; charset=utf-8'),
      );

      expect(failure, isA<ProxyInterception>());
    });

    test('recognises a page without a content type', () async {
      final failure = await _failure(
        _ok('\n  <!doctype html><html><body>Sign in</body></html>'),
      );

      expect(failure, isA<ProxyInterception>());
    });

    test('keeps the classification of the client', () async {
      final failure = await _failure(
        _error(
          const ProxyInterception(),
          status: 200,
          body: _loginPage,
          type: 'text/html',
        ),
      );

      expect(failure, isA<ProxyInterception>());
    });
  });

  group('rejected host name', () {
    // The contract does not say how the client classifies a 400, so the module
    // has to recognise Radarr's page whatever it was called.
    for (final failure in <ServiceFailure>[
      const ServerError(statusCode: 400),
      const Validation([]),
      const MalformedResponse(),
      const HostRejected(),
    ]) {
      test('recognises the page behind ${failure.runtimeType}', () async {
        final result = await _failure(
          _error(
            failure,
            status: 400,
            body: _invalidHostPage,
            type: 'text/html',
          ),
        );

        expect(result, isA<HostRejected>());
      });
    }

    test('does not take every 400 for a rejected host name', () async {
      const failure = Validation(['Bad request']);

      final result = await _failure(
        _error(
          failure,
          status: 400,
          body: '{"message":"Bad request"}',
          type: 'application/json',
        ),
      );

      expect(result, same(failure));
    });
  });

  group('other failures of the client', () {
    const certificate = CertificateInfo(
      sha256:
          '0000000000000000000000000000000000000000000000000000000000000000',
    );
    for (final failure in <ServiceFailure>[
      const Unreachable(),
      const DnsFailure(),
      const CertificateUntrusted(certificate),
      const CertificateChanged(certificate),
      const Redirected(host: 'login.test'),
      const PermissionDenied(),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await _failure(_error(failure)), same(failure));
      });
    }

    test('passes on a server error', () async {
      const failure = ServerError(statusCode: 502);

      final result = await _failure(
        _error(
          failure,
          status: 502,
          body: '<html><body>Bad Gateway</body></html>',
          type: 'text/html',
        ),
      );

      expect(result, same(failure));
    });
  });
}
