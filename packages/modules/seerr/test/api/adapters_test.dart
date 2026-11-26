// What the adapters decide beyond the recorded answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';

import '../contract/support.dart';

const _film = DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: 10331);

/// A server whose requested movie has [status] and [posterPath].
FakeSeerr _movie({
  Product product = Product.seerr,
  int status = 2,
  String? posterPath = '/zqPoster.jpg',
}) {
  final wire = recorded('movie_requested', product);
  return FakeSeerr(product: product)..set(
    'GET api/v1/movie/10331',
    json({
      ...wire,
      'posterPath': posterPath,
      'mediaInfo': {
        ...wire['mediaInfo']! as Map<String, Object?>,
        'status': status,
      },
    }),
  );
}

void main() {
  group('version', () {
    const develop = 'develop-0123456789abcdef0123456789abcdef01234567';
    final cases = <Product, Availability>{
      Product.seerr: Availability.deleted,
      Product.jellyseerr: Availability.deleted,
      // Overseerr never had a 7.
      Product.overseerr: Availability.unknown,
    };
    for (final MapEntry(key: product, value: expected) in cases.entries) {
      test('of a ${product.label} development build is the newest', () async {
        final http = _movie(product: product, status: 7);

        final found = valueOf(
          await discovery(http, version: develop).detail(_film),
        );

        expect(found.availability, expected);
      });
    }

    test('is taken for the newest Seerr before a probe', () async {
      final http = _movie(status: 7);

      final provider = SeerrModule().capability<DiscoveryProvider>(
        context(http, of: instance()),
      )!;

      expect(
        valueOf(await provider.detail(_film)).availability,
        Availability.deleted,
      );
    });
  });

  group('poster', () {
    test('is left out when the settings cannot be read', () async {
      final http = _movie()
        ..set('GET api/v1/settings/public', answered(500, '{}'));

      final found = valueOf(await discovery(http).detail(_film));

      expect(found.poster, isNull);
    });

    for (final path in ['/../api/v1/auth/me', '/a.jpg?x=1', '//host/a.jpg']) {
      test('is not made of $path', () async {
        final found = valueOf(
          await discovery(_movie(posterPath: path)).detail(_film),
        );

        expect(found.poster, isNull);
      });
    }
  });

  test('a blank search term sends nothing', () async {
    final http = FakeSeerr();

    expect(failureOf(await discovery(http).search(' ')), isA<Validation>());
    expect(http.requests, isEmpty);
  });

  group('a refused request says why', () {
    Future<ServiceFailure> refused(Answer answer) async {
      final http = FakeSeerr()..set('POST api/v1/request', answer);
      return failureOf(await requests(http).request(title(), is4k: false));
    }

    test('from a 403 with a message', () async {
      final failure = await refused(
        answered(403, fixture('request_over_quota')),
      );

      expect((failure as Validation).messages, [
        recorded('request_over_quota')['message'],
      ]);
    });

    test('but not where the permission is missing', () async {
      expect(await refused(answered(403, noPermission)), isA<Forbidden>());
    });

    test('from a 202', () async {
      final failure = await refused(
        json({'message': 'No seasons available to request'}, status: 202),
      );

      expect((failure as Validation).messages, [
        'No seasons available to request',
      ]);
    });
  });

  test('keeps the identity when the quota cannot be read', () async {
    final user = valueOf(await requests(FakeSeerr()).session());

    expect(user.quota, isNull);
    expect(user.permissions, contains(ServicePermission.manageRequests));
  });

  test('reads each title of a page of issues once', () async {
    final issue = results('issues').single;
    final http = FakeSeerr()
      ..set(
        'GET api/v1/issue',
        json({
          ...recorded('issues'),
          'results': [
            issue,
            {...issue, 'id': 5},
          ],
        }),
      )
      ..set('GET api/v1/movie/10331', ok(fixture('movie_requested')));

    final page = valueOf(await requests(http).issues());

    expect(page.items, hasLength(2));
    expect(http.reads('movie/10331'), hasLength(1));
  });

  test('routes lead to the screens of the instance', () {
    final http = FakeSeerr();
    final series = title(tmdbId: 1100, type: DiscoveryMediaType.series);

    expect(
      discovery(http).entryRoute().location,
      '/instances/i1/seerr/discover',
    );
    expect(
      discovery(http).detailRoute(title()).location,
      '/instances/i1/seerr/titles/movie/19',
    );
    expect(
      requests(http).requestRoute(series, is4k: true).location,
      '/instances/i1/seerr/titles/series/1100/request?is4k=true',
    );
    expect(
      requests(http).requestsRoute().location,
      '/instances/i1/seerr/requests',
    );
    expect(requests(http).issuesRoute().location, '/instances/i1/seerr/issues');
  });
}
