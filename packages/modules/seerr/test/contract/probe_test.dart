// The Seerr descriptor and probe against recorded answers (FR-007, FR-040,
// spec stories 1 and 9).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';

import 'support.dart';

Future<Result<ProbeResult, ServiceFailure>> _probe(
  FakeSeerr http, {
  AuthKind authKind = AuthKind.apiKey,
}) => SeerrModule().probe(context(http, of: instance(authKind: authKind)));

Future<Result<ProbeResult, ServiceFailure>> _probeVersion(String version) =>
    _probe(
      FakeSeerr()..set(
        'GET api/v1/status',
        json({...recorded('status'), 'version': version}),
      ),
    );

Future<ServiceFailure> _failure(Answer answer) async =>
    failureOf(await _probe(FakeSeerr.always(answer)));

void main() {
  group('descriptor', () {
    test('identifies Seerr', () {
      final module = SeerrModule();

      expect(module.id, 'seerr');
      expect(module.descriptor.displayName, 'Seerr');
      expect(module.descriptor.category, ModuleCategory.requests);
      expect(module.descriptor.defaultPort, 5055);
    });

    test('states the supported minimum and the tested version', () {
      final descriptor = SeerrModule().descriptor;

      expect(descriptor.minimumVersion, '3.0');
      expect(descriptor.testedVersion, '3.5.2');
    });

    test('takes a local account, a media server account or a key', () {
      final module = SeerrModule();

      expect(
        module.descriptor.authKinds,
        unorderedEquals([
          AuthKind.userPassword,
          AuthKind.mediaServerAccount,
          AuthKind.apiKey,
        ]),
      );
      expect(module.sessionHandler, isNotNull);
      expect(module.descriptor.apiKeyHeader?.name, 'X-Api-Key');
      expect(module.descriptor.apiKeyHeader?.prefix, isEmpty);
    });

    // A 403 also refuses a good key: no quota left, a blocklisted title, a
    // missing CSRF token.
    test('does not take every 403 for a rejected key', () {
      expect(SeerrModule().descriptor.apiKeyHeader?.rejectionStatus, isNull);
    });
  });

  group('success', () {
    for (final product in Product.values) {
      test('reports ${product.label} ${product.version}', () async {
        final http = FakeSeerr(product: product);

        final result = valueOf(await _probe(http));

        expect(result.product, product.label);
        expect(result.version, product.version);
        expect(result.newerThanTested, isFalse);
        expect(result.session, isNotNull);
      });
    }

    for (final authKind in [
      AuthKind.apiKey,
      AuthKind.userPassword,
      AuthKind.mediaServerAccount,
    ]) {
      test('only reads, with ${authKind.name}', () async {
        final http = FakeSeerr();

        valueOf(await _probe(http, authKind: authKind));

        expect(http.writes, isEmpty);
        // The status is public: it is no test of the credential.
        expect(http.reads('status'), isNotEmpty);
        expect(http.reads('auth/me'), isNotEmpty);
      });
    }

    test('offers discovery and requests to any identity', () async {
      final module = SeerrModule();
      for (final product in Product.values) {
        for (final name in ['auth_me_admin', 'auth_me_member']) {
          final http = FakeSeerr(product: product)
            ..set('GET api/v1/auth/me', ok(fixture(name, product)));
          final result = valueOf(await _probe(http));

          expect(module.capabilitiesFor(result, result.session), {
            CapabilityKind.discovery,
            CapabilityKind.request,
          });
        }
      }
    });

    test('provides both without a request', () {
      final http = FakeSeerr();
      final module = SeerrModule();

      expect(module.capability<DiscoveryProvider>(contextOf(http)), isNotNull);
      expect(module.capability<RequestProvider>(contextOf(http)), isNotNull);
      expect(module.capability<LibraryProvider>(contextOf(http)), isNull);
      expect(http.requests, isEmpty);
    });
  });

  group('version', () {
    // The minimum of each product, told apart by the major version.
    final accepted = {
      '3.0.0': 'Seerr',
      '3.4.1': 'Seerr',
      '2.0.0': 'Jellyseerr',
      '2.5.2': 'Jellyseerr',
      '1.34.0': 'Overseerr',
    };
    for (final MapEntry(key: version, value: product) in accepted.entries) {
      test('accepts $product $version', () async {
        final result = valueOf(await _probeVersion(version));

        expect(result.product, product);
        expect(result.version, version);
        expect(result.newerThanTested, isFalse);
      });
    }

    // 1.9.2 is the last Jellyseerr 1.x, which the Overseerr minimum must not
    // admit: compared part by part, 9 is below 34.
    for (final version in ['1.33.2', '1.9.2', '0.9.0']) {
      test('refuses $version as too old', () async {
        expect(
          failureOf(await _probeVersion(version)),
          isA<UnsupportedVersion>().having(
            (failure) => failure.version,
            'version',
            version,
          ),
        );
      });
    }

    for (final version in [
      '3.5.3',
      '3.10.0',
      '4.0.0',
      '10.0.0',
      '2.8.0',
      '1.36.0',
    ]) {
      test('accepts $version with the newer-than-tested notice', () async {
        final result = valueOf(await _probeVersion(version));

        expect(result.newerThanTested, isTrue);
      });
    }
  });

  group('wrong service', () {
    test('recognises a server without the interface', () async {
      expect(
        await _failure(answered(404, '{"message":"Not Found"}')),
        isA<WrongService>(),
      );
    });

    final strangers = {
      'an empty object': '{}',
      'a list': '[]',
      'a number for a version': '{"version":3}',
      'a version that is none': '{"version":"soon"}',
      'plain text': 'OK',
    };
    for (final MapEntry(key: name, value: body) in strangers.entries) {
      test('recognises $name', () async {
        expect(
          await _failure(ok(body)),
          anyOf(isA<WrongService>(), isA<MalformedResponse>()),
        );
      });
    }
  });

  group('authentication', () {
    // A wrong key gets the same 403 as a missing permission, but auth/me
    // needs none.
    test('reports a rejected API key', () async {
      final http = FakeSeerr()
        ..set('GET api/v1/auth/me', answered(403, fixture('auth_me_rejected')));

      expect(failureOf(await _probe(http)), isA<AuthFailed>());
      expect(http.reads('auth/me'), hasLength(1));
    });

    // Without a key or cookie the answer is a 401.
    test('reports a request taken for anonymous', () async {
      final http = FakeSeerr()
        ..set(
          'GET api/v1/auth/me',
          answered(401, fixture('auth_me_anonymous')),
        );

      expect(failureOf(await _probe(http)), isA<AuthFailed>());
    });

    // What a session reports when the login was rejected or is latched.
    test('passes on a rejected login', () async {
      expect(await _failure(unsent(const AuthFailed())), isA<AuthFailed>());
    });
  });

  group('proxy page', () {
    const page = '<!DOCTYPE html><html><body>Sign in</body></html>';

    test('recognises a login page served as success', () async {
      expect(
        await _failure(answered(200, page, type: 'text/html')),
        isA<ProxyInterception>(),
      );
    });

    test('recognises a page without a content type', () async {
      expect(
        await _failure(answered(200, page, type: null)),
        anyOf(isA<ProxyInterception>(), isA<WrongService>()),
      );
    });
  });

  group('other failures of the client', () {
    for (final failure in <ServiceFailure>[
      const Unreachable(),
      const DnsFailure(),
      const Redirected(host: 'login.test'),
      const PermissionDenied(),
      const ServerError(statusCode: 500),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await _failure(unsent(failure)), same(failure));
      });
    }
  });
}
