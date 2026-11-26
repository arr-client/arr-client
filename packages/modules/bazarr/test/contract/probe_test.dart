// The Bazarr descriptor and probe against recorded answers (FR-007, spec
// stories 1 and 10).

import 'package:bazarr/bazarr_module.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

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

Result<ServiceResponse, HttpError> _statusWith(Map<String, Object?> changes) =>
    jsonAnswer({
      'data': {
        ...fixture('system_status')['data']! as Map<String, Object?>,
        ...changes,
      },
    });

/// A server that gives [answer] to everything.
Harness _serving(Result<ServiceResponse, HttpError> answer) =>
    Harness()..server.down = answer;

Future<ProbeResult> _success(Result<ServiceResponse, HttpError> answer) =>
    succeed(BazarrModule().probe(_serving(answer).context));

Future<ServiceFailure> _failure(Result<ServiceResponse, HttpError> answer) =>
    failureOf(BazarrModule().probe(_serving(answer).context));

void main() {
  group('descriptor', () {
    test('identifies Bazarr', () {
      final module = BazarrModule();

      expect(module.id, 'bazarr');
      expect(module.descriptor.displayName, 'Bazarr');
      expect(module.descriptor.category, ModuleCategory.subtitles);
      expect(module.descriptor.defaultPort, 6767);
    });

    test('authenticates with an API key in X-API-KEY', () {
      final module = BazarrModule();

      expect(module.descriptor.authKinds, [AuthKind.apiKey]);
      expect(module.descriptor.apiKeyHeader?.name, 'X-API-KEY');
      expect(module.descriptor.apiKeyHeader?.prefix, '');
      expect(module.sessionHandler, isNull);
    });

    test('states the supported minimum and the tested version', () {
      final module = BazarrModule();

      expect(module.descriptor.minimumVersion, '1.5');
      expect(module.descriptor.testedVersion, '1.6.2');
    });

    test('offers subtitles, and nothing else', () {
      final module = BazarrModule();

      expect(
        module.capabilitiesFor(
          const ProbeResult(product: 'Bazarr', version: '1.6.2'),
          null,
        ),
        {CapabilityKind.subtitle},
      );

      final harness = Harness();
      for (final kind in CapabilityKind.values) {
        expect(
          kind.of(module, harness.context),
          kind == CapabilityKind.subtitle ? isNotNull : isNull,
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

      await succeed(BazarrModule().probe(harness.context));

      final request = harness.server.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/system/status');
      // The key goes in a header, which the core client adds.
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });

    for (final version in versions) {
      test('reports Bazarr $version', () async {
        final result = await succeed(
          BazarrModule().probe(Harness(version).context),
        );

        expect(result.product, 'Bazarr');
        expect(result.version, version);
        expect(result.newerThanTested, isFalse);
        expect(result.session, isNull);
      });
    }

    // Without Sonarr and Radarr, or while they do not answer.
    test('does not need a connected library', () async {
      final result = await _success(
        _statusWith({'sonarr_version': '', 'radarr_version': 'unknown'}),
      );

      expect(result.version, '1.6.2');
    });
  });

  group('version', () {
    for (final version in ['1.5.0', '1.5.6', '1.5.7-beta.3', '1.6.0']) {
      test('accepts $version', () async {
        final result = await _success(_statusWith({'bazarr_version': version}));

        expect(result.version, version);
        expect(result.newerThanTested, isFalse);
      });
    }

    for (final version in ['1.4.5', '1.4.6-beta.1', '1.1.0', '0.9.11']) {
      test('refuses $version as too old', () async {
        expect(
          await _failure(_statusWith({'bazarr_version': version})),
          isA<UnsupportedVersion>().having(
            (f) => f.version,
            'version',
            version,
          ),
        );
      });
    }

    // 10.0.0 sorts before 1.6 as text.
    for (final version in ['1.6.3', '1.7.0', '2.0.0', '10.0.0']) {
      test('accepts $version with the newer-than-tested notice', () async {
        final result = await _success(_statusWith({'bazarr_version': version}));

        expect(result.version, version);
        expect(result.newerThanTested, isTrue);
      });
    }

    // A source install without its version file says "unknown".
    for (final version in <Object?>['unknown', '', 3, null]) {
      test('cannot understand the version "$version"', () async {
        expect(
          await _failure(_statusWith({'bazarr_version': version})),
          isA<MalformedResponse>(),
        );
      });
    }
  });

  group('wrong service', () {
    test('recognises a server without the interface', () async {
      // Sonarr and Radarr answer this to their own key.
      expect(
        await _failure(failedAnswer(const NotFound(), status: 404)),
        isA<WrongService>(),
      );
    });

    final strangers = <String, Object?>{
      'a Servarr status': {'appName': 'Sonarr', 'version': '4.0.20.3014'},
      'a Seerr status': {'version': '3.5.2', 'commitTag': 'v3.5.2'},
      'data of something else': {
        'data': {'version': '1.6.2'},
      },
      'data that is a list': {'data': <Object?>[]},
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
        await _failure(textAnswer('{"data":{"bazarr_ver')),
        isA<MalformedResponse>(),
      );
    });
  });

  group('authentication', () {
    test('reports a rejected key and does not try again', () async {
      final harness = _serving(
        failedAnswer(
          const AuthFailed(),
          status: 401,
          body: recorded('unauthorized'),
        ),
      );

      expect(
        await failureOf(BazarrModule().probe(harness.context)),
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
        await _failure(Ok(response(200, '\n  $_loginPage'))),
        isA<ProxyInterception>(),
      );
    });

    // What a wrong URL base gets from Bazarr itself.
    test('keeps the classification of the client', () async {
      expect(
        await _failure(
          failedAnswer(
            const ProxyInterception(),
            status: 200,
            body: '<!doctype html><title>Bazarr</title>',
            type: 'text/html; charset=utf-8',
          ),
        ),
        isA<ProxyInterception>(),
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
      const HostRejected(),
      const PermissionDenied(),
      const ServerError(statusCode: 502),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await _failure(failedAnswer(failure)), same(failure));
      });
    }
  });
}
