// What the signed-in identity may do, and how much it may still request (spec
// story 9, scenario 1; research R16).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';

import 'support.dart';

const _movies = ServicePermission.requestMovies;
const _series = ServicePermission.requestSeries;
const _movies4k = ServicePermission.request4kMovies;
const _series4k = ServicePermission.request4kSeries;
const _manage = ServicePermission.manageRequests;
const _report = ServicePermission.reportIssues;
const _view = ServicePermission.viewIssues;
const _resolve = ServicePermission.manageIssues;

FakeSeerr _server(
  int permissions, {
  Product product = Product.seerr,
  bool movie4k = true,
  bool series4k = true,
}) => FakeSeerr(product: product)
  ..set(
    'GET api/v1/auth/me',
    json({...recorded('auth_me_member', product), 'permissions': permissions}),
  )
  ..set(
    'GET api/v1/settings/public',
    json(
      publicSettings(product: product, movie4k: movie4k, series4k: series4k),
    ),
  );

Future<Set<ServicePermission>> _granted(FakeSeerr http) async =>
    valueOf(await SeerrModule().probe(contextOf(http))).session!.permissions;

void main() {
  group('permission bits', () {
    // server/lib/permissions.ts, and what its routes ask for.
    final cases = <String, (int, Set<ServicePermission>)>{
      'none': (0, {}),
      'administrator': (Bits.admin, {...ServicePermission.values}),
      'request': (Bits.request, {_movies, _series}),
      'request movies': (Bits.requestMovie, {_movies}),
      'request series': (Bits.requestTv, {_series}),
      '4K': (Bits.request4k, {_movies4k, _series4k}),
      '4K movies': (Bits.request4kMovie, {_movies4k}),
      '4K series': (Bits.request4kTv, {_series4k}),
      // Approving others does not let one request.
      'manage requests': (Bits.manageRequests, {_manage}),
      'create issues': (Bits.createIssues, {_report, _view}),
      'view issues': (Bits.viewIssues, {_view}),
      'manage issues': (Bits.manageIssues, {_report, _view, _resolve}),
      'bits the app has no use for': (
        Bits.manageUsers |
            Bits.autoApprove |
            Bits.requestAdvanced |
            Bits.requestView,
        {},
      ),
      'several': (
        Bits.request | Bits.request4kTv | Bits.createIssues,
        {_movies, _series, _series4k, _report, _view},
      ),
    };
    for (final MapEntry(key: name, value: (bits, expected)) in cases.entries) {
      test('map $name', () async {
        expect(await _granted(_server(bits)), expected);
      });
    }

    for (final product in Product.values) {
      test('of an administrator of ${product.label}', () async {
        final http = _server(Bits.admin, product: product);

        expect(await _granted(http), {...ServicePermission.values});
      });
    }
  });

  // The servers' web interfaces offer 4K only with a 4K server set up.
  group('4K', () {
    test('is not offered for movies without a 4K server', () async {
      final granted = await _granted(_server(Bits.admin, movie4k: false));

      expect(granted, isNot(contains(_movies4k)));
      expect(granted, containsAll([_movies, _series4k]));
    });

    test('is not offered for series without a 4K server', () async {
      final granted = await _granted(_server(Bits.admin, series4k: false));

      expect(granted, isNot(contains(_series4k)));
      expect(granted, containsAll([_series, _movies4k]));
    });
  });

  group('session', () {
    for (final product in Product.values) {
      test('reads the identity from ${product.label}', () async {
        final me = recorded('auth_me_member', product);
        final http = FakeSeerr(product: product)
          ..set('GET api/v1/auth/me', json(me))
          ..set(
            'GET api/v1/user/${me['id']}/quota',
            ok(fixture('quota_used', product)),
          );

        final user = valueOf(await requests(http).session());

        expect(user.id, me['id']);
        expect(user.name, me['displayName']);
        // Recorded as request and create issues.
        expect(user.permissions, {_movies, _series, _report, _view});
        expect(http.writes, isEmpty);
      });
    }
  });

  group('quota', () {
    FakeSeerr server(Product product, Map<String, Object?> quota) {
      final id = recorded('auth_me_member', product)['id'];
      return FakeSeerr(product: product)
        ..set('GET api/v1/auth/me', ok(fixture('auth_me_member', product)))
        ..set('GET api/v1/user/$id/quota', json(quota));
    }

    for (final product in Product.values) {
      test('of the signed-in user of ${product.label}', () async {
        final http = server(product, recorded('quota_used', product));

        final quota = valueOf(await requests(http).quota());

        expect(quota.movies?.used, 2);
        expect(quota.movies?.limit, 2);
        expect(quota.movies?.days, 7);
        expect(quota.series?.used, 2);
        expect(quota.series?.limit, 3);
        expect(quota.series?.days, 7);
      });
    }

    // Unlimited is a missing or zero limit.
    test('without a limit', () async {
      final http = server(Product.seerr, {
        'movie': {'used': 0, 'restricted': false},
        'tv': {'limit': 0, 'used': 0, 'restricted': false},
      });

      final quota = valueOf(await requests(http).quota());

      expect(quota.movies?.limit, isNull);
      expect(quota.series?.limit, isNull);
    });
  });
}
