import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _FakeLogger extends Fake implements Logger {}

class _FakeHealth implements HealthProvider {
  @override
  bool get providesDiskSpace => false;

  @override
  ServiceResult<List<HealthIssue>> health() async => const Ok([]);

  @override
  ServiceResult<List<DiskSpace>> diskSpace() async => const Ok([]);
}

/// A module that offers health only.
class _FakeModule extends Fake implements ServiceModule {
  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) async {
    final response = await context.http.send(
      ServiceRequest(HttpMethod.get, 'api/status'),
    );
    return switch (response) {
      Ok(:final value) => Ok(ProbeResult(product: 'Fake', version: value.text)),
      Err(:final error) => Err(error.failure),
    };
  }

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final health = _FakeHealth();
    return health is T ? health as T : null;
  }
}

InstanceContext _context(ServiceHttpClient http) => InstanceContext(
  instance: Instance(
    id: 'i1',
    profileId: 'p1',
    name: 'Home',
    serviceType: 'fake',
    url: Uri.parse('http://server.test/sub'),
    authKind: AuthKind.apiKey,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  http: http,
  artwork: _FakeArtwork(),
  navigator: _FakeNavigator(),
  cache: _FakeCache(),
  logger: _FakeLogger(),
);

void main() {
  final module = _FakeModule();

  group('CapabilityKind.of', () {
    final context = _context(_FakeHttp(Err(const HttpError(Unreachable()))));

    test('returns what the module offers', () {
      final HealthProvider? health = CapabilityKind.health.of(module, context);

      expect(health, isNotNull);
    });

    test('returns null for every capability the module lacks', () {
      for (final kind in CapabilityKind.values) {
        if (kind == CapabilityKind.health) continue;
        expect(kind.of(module, context), isNull, reason: kind.name);
      }
    });
  });

  group('probe through an InstanceContext', () {
    test('reports what the server answers', () async {
      final http = _FakeHttp(
        Ok(
          ServiceResponse(
            statusCode: 200,
            bytes: Uint8List.fromList('1.2.3'.codeUnits),
          ),
        ),
      );

      final result = await module.probe(_context(http));

      expect(http.requests.single.path, 'api/status');
      expect(
        result,
        isA<Ok<ProbeResult, ServiceFailure>>().having(
          (ok) => ok.value.version,
          'version',
          '1.2.3',
        ),
      );
    });

    test('returns the failure of the request without throwing', () async {
      final http = _FakeHttp(Err(const HttpError(AuthFailed())));

      final result = await module.probe(_context(http));

      expect(
        result,
        isA<Err<ProbeResult, ServiceFailure>>().having(
          (err) => err.error,
          'error',
          isA<AuthFailed>(),
        ),
      );
    });
  });

  // Renaming one of these would lose what users have stored.
  group('persisted names', () {
    List<String> names(List<Enum> values) => [for (final v in values) v.name];

    test('capabilities', () {
      expect(names(CapabilityKind.values), [
        'library',
        'lookup',
        'command',
        'release',
        'queue',
        'history',
        'wanted',
        'calendar',
        'health',
        'indexerSearch',
        'downloadProgress',
        'discovery',
        'request',
        'subtitle',
      ]);
    });

    test('authentication, link and item kinds', () {
      expect(names(AuthKind.values), [
        'apiKey',
        'userPassword',
        'mediaServerAccount',
        'none',
      ]);
      expect(names(InstanceLinkType.values), ['subtitlesFor']);
      expect(names(MediaKind.values), [
        'movie',
        'series',
        'episode',
        'artist',
        'album',
        'track',
        'author',
        'book',
      ]);
    });

    test('permissions', () {
      expect(names(ServicePermission.values), [
        'requestMovies',
        'requestSeries',
        'request4kMovies',
        'request4kSeries',
        'manageRequests',
        'reportIssues',
        'viewIssues',
        'manageIssues',
      ]);
    });
  });
}
