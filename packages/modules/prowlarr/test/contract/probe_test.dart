// The Prowlarr probe against recorded answers (FR-007, spec story 1).
//
// system_status.json and the rejected-host, 401 and 404 answers below were
// recorded from a Prowlarr 3.1.0.5799 (see support.dart); the host name was
// refused after its allowed hosts were set.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prowlarr/prowlarr_module.dart';

import 'support.dart';

// What Prowlarr answers with 400 when its allowed hosts do not include the
// request's host name.
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

Map<String, Object?> get _status =>
    fixture('system_status')! as Map<String, Object?>;

Result<ServiceResponse, HttpError> _statusWith(Map<String, Object?> changes) =>
    jsonAnswer({..._status, ...changes});

/// A server that gives [answer] to everything.
Harness _serving(Result<ServiceResponse, HttpError> answer) =>
    Harness()..server.down = answer;

Future<ProbeResult> _success(Result<ServiceResponse, HttpError> answer) =>
    succeed(ProwlarrModule().probe(_serving(answer).context));

Future<ServiceFailure> _failure(Result<ServiceResponse, HttpError> answer) =>
    failureOf(ProwlarrModule().probe(_serving(answer).context));

void main() {
  group('descriptor', () {
    final module = ProwlarrModule();

    test('identifies Prowlarr', () {
      expect(module.id, 'prowlarr');
      expect(module.descriptor.displayName, 'Prowlarr');
      expect(module.descriptor.category, ModuleCategory.indexers);
      expect(module.descriptor.defaultPort, 9696);
    });

    test('authenticates with an API key in X-Api-Key', () {
      expect(module.descriptor.authKinds, [AuthKind.apiKey]);
      expect(module.descriptor.apiKeyHeader?.name, 'X-Api-Key');
      expect(module.descriptor.apiKeyHeader?.prefix, '');
      expect(module.sessionHandler, isNull);
    });

    test('states the supported minimum and the tested version', () {
      expect(module.descriptor.minimumVersion, '1.0');
      expect(module.descriptor.testedVersion, '3.1.0.5799');
    });

    test('offers indexer search and health, and nothing else', () {
      expect(
        module.capabilitiesFor(
          const ProbeResult(product: 'Prowlarr', version: '3.1.0.5799'),
          null,
        ),
        {CapabilityKind.indexerSearch, CapabilityKind.health},
      );

      final harness = Harness();
      for (final kind in CapabilityKind.values) {
        final offered =
            kind == CapabilityKind.indexerSearch ||
            kind == CapabilityKind.health;
        expect(
          kind.of(module, harness.context),
          offered ? isNotNull : isNull,
          reason: kind.name,
        );
      }
      // Building them asks nothing, so that screens open offline.
      expect(harness.server.requests, isEmpty);
    });
  });

  group('success', () {
    test('asks for the system status, once', () async {
      final harness = Harness();

      await succeed(ProwlarrModule().probe(harness.context));

      final request = harness.server.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v1/system/status');
      // The key goes in a header, which the core client adds.
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });

    test('reports the product and version', () async {
      final result = await _success(jsonAnswer(_status));

      expect(result.product, 'Prowlarr');
      expect(result.version, '3.1.0.5799');
      expect(result.newerThanTested, isFalse);
      expect(result.session, isNull);
    });

    test('ignores fields it does not know', () async {
      final result = await _success(
        _statusWith({
          'someFutureField': {'a': 1},
        }),
      );

      expect(result.version, '3.1.0.5799');
    });
  });

  group('version', () {
    for (final version in ['1.0.0.2171', '1.37.0.5076', '2.0.0.5094']) {
      test('accepts $version', () async {
        final result = await _success(_statusWith({'version': version}));

        expect(result.version, version);
        expect(result.newerThanTested, isFalse);
      });
    }

    for (final version in ['0.4.12.1218', '0.1.0.1']) {
      test('refuses $version as too old', () async {
        expect(
          await _failure(_statusWith({'version': version})),
          isA<UnsupportedVersion>().having(
            (f) => f.version,
            'version',
            version,
          ),
        );
      });
    }

    for (final version in [
      '3.2.0.5900',
      '4.0.0.6000',
      // Sorts before 3 as text.
      '10.0.0.7000',
    ]) {
      test('accepts $version with the newer-than-tested notice', () async {
        final result = await _success(_statusWith({'version': version}));

        expect(result.version, version);
        expect(result.newerThanTested, isTrue);
      });
    }

    final unreadable = <String, Map<String, Object?>>{
      'no version': {'appName': 'Prowlarr'},
      'an empty version': {'appName': 'Prowlarr', 'version': ''},
      'a version that is not text': {'appName': 'Prowlarr', 'version': 3},
      'a version that is not a number': {
        'appName': 'Prowlarr',
        'version': 'unknown',
      },
    };
    for (final MapEntry(key: name, value: body) in unreadable.entries) {
      test('cannot understand a status with $name', () async {
        expect(await _failure(jsonAnswer(body)), isA<MalformedResponse>());
      });
    }
  });

  group('wrong service', () {
    // Lidarr and Readarr serve the same path.
    for (final (name, version) in const [
      ('Lidarr', '3.1.6.5079'),
      ('Readarr', '0.4.18.2805'),
      ('Radarr', '7.0.3.10918'),
    ]) {
      test('recognises $name', () async {
        expect(
          await _failure(_statusWith({'appName': name, 'version': version})),
          isA<WrongService>(),
        );
      });
    }

    test('recognises a server without the v1 interface', () async {
      // Sonarr, Radarr and unrelated servers answer 404.
      expect(
        await _failure(failedAnswer(const NotFound(), status: 404)),
        isA<WrongService>(),
      );
    });

    final strangers = <String, Object?>{
      'an object without an application name': {'version': '3.1.0'},
      'a list': <Object?>[],
      'a bare text': 'ok',
    };
    for (final MapEntry(key: name, value: body) in strangers.entries) {
      test('recognises $name', () async {
        expect(await _failure(jsonAnswer(body)), isA<WrongService>());
      });
    }

    test('cannot understand JSON that breaks off', () async {
      expect(
        await _failure(textAnswer('{"appName":"Prow')),
        isA<MalformedResponse>(),
      );
    });
  });

  group('authentication', () {
    test('reports a rejected key and does not try again', () async {
      // Prowlarr answers a wrong key with 401 and no body.
      final harness = _serving(failedAnswer(const AuthFailed(), status: 401));

      expect(
        await failureOf(ProwlarrModule().probe(harness.context)),
        isA<AuthFailed>(),
      );
      expect(harness.server.requests, hasLength(1));
    });

    test('reports a refused identity', () async {
      expect(
        await _failure(failedAnswer(const Forbidden(), status: 403)),
        isA<Forbidden>(),
      );
    });
  });

  group('proxy page', () {
    test('recognises a login page served as success', () async {
      expect(
        await _failure(
          Ok(response(200, _loginPage, type: 'text/html; charset=utf-8')),
        ),
        isA<ProxyInterception>(),
      );
    });

    test('recognises a page without a content type', () async {
      expect(
        await _failure(
          Ok(response(200, '\n  <!doctype html><html>Sign in</html>')),
        ),
        isA<ProxyInterception>(),
      );
    });
  });

  group('rejected host name', () {
    // The client calls a 400 `Validation`; the module has to recognise the
    // page whatever it was called.
    for (final failure in <ServiceFailure>[
      const Validation([]),
      const ServerError(statusCode: 400),
      const MalformedResponse(),
      const HostRejected(),
    ]) {
      test('recognises the page behind ${failure.runtimeType}', () async {
        expect(
          await _failure(
            failedAnswer(
              failure,
              status: 400,
              body: _invalidHostPage,
              type: 'text/html',
            ),
          ),
          isA<HostRejected>(),
        );
      });
    }

    test('does not take every 400 for a rejected host name', () async {
      const failure = Validation(['Bad request']);

      expect(
        await _failure(
          failedAnswer(
            failure,
            status: 400,
            body: '{"message":"Bad request"}',
            type: 'application/json',
          ),
        ),
        same(failure),
      );
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
      const ProxyInterception(),
      const PermissionDenied(),
      const ServerError(statusCode: 502),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await _failure(failedAnswer(failure)), same(failure));
      });
    }
  });
}
