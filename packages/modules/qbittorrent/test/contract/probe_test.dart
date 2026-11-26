// The qBittorrent descriptor and probe against recorded answers (FR-007, spec
// stories 1 and 7).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbittorrent/qbittorrent_module.dart';

import 'support.dart';

Future<Result<ProbeResult, ServiceFailure>> _probe(
  FakeHttp http, {
  AuthKind authKind = AuthKind.userPassword,
}) => QbittorrentModule().probe(context(http, authKind: authKind));

/// Probes a server whose version reads as [appVersion].
Future<Result<ProbeResult, ServiceFailure>> _probeVersion(String appVersion) =>
    _probe(FakeHttp.server('5.3.1', appVersion: appVersion));

/// Why a probe of a server that always gives [answer] fails.
Future<ServiceFailure> _failure(
  Answer answer, {
  AuthKind authKind = AuthKind.userPassword,
}) async =>
    failureOf(await _probe(FakeHttp.always(answer), authKind: authKind));

void main() {
  group('descriptor', () {
    final module = QbittorrentModule();
    final descriptor = module.descriptor;

    test('identifies qBittorrent', () {
      expect(module.id, 'qbittorrent');
      expect(descriptor.displayName, 'qBittorrent');
      expect(descriptor.category, ModuleCategory.downloadClient);
      expect(descriptor.defaultPort, 8080);
    });

    test('states the supported minimum and the tested version', () {
      expect(descriptor.minimumVersion, '4.4');
      expect(descriptor.testedVersion, '5.3.1');
    });

    test('takes an API key, sent as a bearer token, or a login', () {
      expect(
        descriptor.authKinds,
        unorderedEquals([AuthKind.apiKey, AuthKind.userPassword]),
      );
      expect(descriptor.apiKeyHeader?.name, 'Authorization');
      expect(descriptor.apiKeyHeader?.prefix, 'Bearer ');
      expect(module.sessionHandler, isNotNull);
    });

    // Spec, Edge Cases: with a key, basic authentication needs the same header;
    // with a login, 5.2 and later reads that header as its own.
    for (final authKind in [AuthKind.apiKey, AuthKind.userPassword]) {
      test('warns about basic authentication with ${authKind.name}', () {
        expect(
          descriptor.authNotes.where(
            (note) => note.authKind == authKind && note.onlyWithBasicAuth,
          ),
          isNotEmpty,
        );
      });
    }
  });

  group('success', () {
    for (final version in versions) {
      test('reports qBittorrent $version', () async {
        final result = valueOf(await _probe(FakeHttp.server(version)));

        expect(result.product, 'qBittorrent');
        // Recorded as "v$version".
        expect(result.version, version);
        expect(result.newerThanTested, isFalse);
        expect(result.session, isNull);
      });
    }

    for (final authKind in [AuthKind.apiKey, AuthKind.userPassword]) {
      test('only reads, with ${authKind.name}', () async {
        final http = FakeHttp.server('5.3.1');

        valueOf(await _probe(http, authKind: authKind));

        expect(
          http.requests.map((request) => request.path),
          contains('api/v2/app/version'),
        );
        for (final request in http.requests) {
          expect(request.method, HttpMethod.get);
          expect(request.query, isEmpty);
          expect(request.body, isNull);
          expectNoOrigin(request);
        }
      });
    }
  });

  group('version', () {
    // 4.4.3.1 is a real release with four numbers.
    for (final version in [
      '4.4.0',
      '4.4.3.1',
      '4.6.7',
      '4.10.0',
      '5.0.0',
      '5.2.0',
    ]) {
      test('accepts $version', () async {
        final result = valueOf(await _probeVersion('v$version'));

        expect(result.version, version);
        expect(result.newerThanTested, isFalse);
      });
    }

    test('accepts a release candidate', () async {
      final result = valueOf(await _probeVersion('v5.0.0rc1'));

      expect(result.version, startsWith('5.0.0'));
    });

    for (final version in ['4.3.9', '4.1.9.1', '3.3.16']) {
      test('refuses $version as too old', () async {
        expect(
          failureOf(await _probeVersion('v$version')),
          isA<UnsupportedVersion>().having(
            (failure) => failure.version,
            'version',
            version,
          ),
        );
      });
    }

    // 10.0.0 sorts before 5 as text.
    for (final version in ['5.4.0', '6.0.0', '10.0.0']) {
      test('accepts $version with the newer-than-tested notice', () async {
        final result = valueOf(await _probeVersion('v$version'));

        expect(result.version, version);
        expect(result.newerThanTested, isTrue);
      });
    }
  });

  group('wrong service', () {
    test('recognises a server without the interface', () async {
      final failure = await _failure(
        error(const NotFound(), status: 404, body: 'Not Found'),
      );

      expect(failure, isA<WrongService>());
    });

    final strangers = {
      'an object': ('{"version":"5.3.1"}', 'application/json'),
      'a list': ('[]', 'application/json'),
      'some other text': ('OK', textType),
    };
    for (final MapEntry(key: name, value: (body, type)) in strangers.entries) {
      test('recognises $name', () async {
        expect(await _failure(ok(body, type: type)), isA<WrongService>());
      });
    }

    test('does not take an empty answer for a version', () async {
      expect(
        await _failure(ok('')),
        anyOf(isA<WrongService>(), isA<MalformedResponse>()),
      );
    });
  });

  group('authentication', () {
    // The key is wrong or was replaced: 403, which the core client calls
    // Forbidden. Recorded from 5.3.1.
    test('reports a rejected API key', () async {
      final http = FakeHttp.always(
        error(
          const Forbidden(),
          status: 403,
          body: fixture('5.3.1', 'forbidden.txt'),
        ),
      );

      final result = await _probe(http, authKind: AuthKind.apiKey);

      expect(failureOf(result), isA<AuthFailed>());
      expect(http.requests, hasLength(1));
    });

    // With a login, a 403 on a read that is still there after the session was
    // renewed is not about the password.
    test('keeps a refusal of a signed-in account', () async {
      final failure = await _failure(
        error(const Forbidden(), status: 403, body: 'Forbidden'),
      );

      expect(failure, isA<Forbidden>());
    });

    // What a session reports when the login was rejected, or when the instance
    // is already latched.
    test('passes on a rejected login', () async {
      final http = FakeHttp.always(error(const AuthFailed()));

      final result = await _probe(http);

      expect(failureOf(result), isA<AuthFailed>());
      expect(http.requests, hasLength(1));
    });
  });

  // A bare 401 is a rejected host name, or basic authentication that 5.2 and
  // later took for its own. The recording is the same on all versions.
  group('401', () {
    for (final version in versions) {
      for (final authKind in [AuthKind.apiKey, AuthKind.userPassword]) {
        test(
          'names the host name on $version with ${authKind.name}, once',
          () async {
            final http = FakeHttp.always(
              error(
                const AuthFailed(),
                status: 401,
                body: fixture(version, 'host_rejected.txt'),
              ),
            );

            final result = await _probe(http, authKind: authKind);

            expect(failureOf(result), isUnauthorized);
            expect(http.requests, hasLength(1));
          },
        );
      }
    }

    test('keeps a host name the client found rejected', () async {
      final failure = await _failure(error(const HostRejected(), status: 421));

      expect(failure, isA<HostRejected>());
    });
  });

  group('proxy page', () {
    test('recognises a login page served as success', () async {
      final failure = await _failure(
        ok(loginPage, type: 'text/html; charset=utf-8'),
      );

      expect(failure, isA<ProxyInterception>());
    });

    test('recognises a page without a content type', () async {
      final failure = await _failure(ok('\n  $loginPage', type: null));

      expect(failure, isA<ProxyInterception>());
    });

    test('keeps the classification of the client', () async {
      final failure = await _failure(
        error(
          const ProxyInterception(),
          status: 200,
          body: loginPage,
          type: 'text/html',
        ),
      );

      expect(failure, isA<ProxyInterception>());
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
      const ServerError(statusCode: 500),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await _failure(error(failure)), same(failure));
      });
    }
  });
}
