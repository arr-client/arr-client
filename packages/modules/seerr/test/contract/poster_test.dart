// Posters: the instance's image proxy in both of its forms, or the public host
// (research R10).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';
import 'support.dart';

const _file = '/zqPoster.jpg';

Future<DiscoveryTitle> _found(
  Product product, {
  required bool cacheImages,
  String? version,
  String? posterPath = _file,
}) async {
  final page = recorded('search_requested', product);
  final first = results('search_requested', product).first;
  final http = FakeSeerr(product: product)
    ..set(
      'GET api/v1/settings/public',
      json(publicSettings(product: product, cacheImages: cacheImages)),
    )
    ..set(
      'GET api/v1/search',
      json({
        ...page,
        'results': [
          {...first, 'posterPath': posterPath},
        ],
      }),
    );
  return valueOf(await discovery(http, version: version).search('night'))
      .items
      .single;
}

void main() {
  // Seerr and later Jellyseerr name the source in the path.
  const named = 'imageproxy/tmdb/t/p/';
  const plain = 'imageproxy/t/p/';
  final forms = <(Product, String), String>{
    (Product.seerr, '3.5.2'): named,
    (Product.seerr, '3.0.0'): named,
    (Product.jellyseerr, '2.7.3'): named,
    (Product.jellyseerr, '2.6.0'): named,
    (Product.jellyseerr, '2.5.2'): plain,
    (Product.jellyseerr, '2.0.0'): plain,
    (Product.overseerr, '1.35.0'): plain,
    (Product.overseerr, '1.34.0'): plain,
  };

  for (final MapEntry(key: (product, version), value: prefix)
      in forms.entries) {
    test('goes through the proxy of ${product.label} $version', () async {
      final found = await _found(product, cacheImages: true, version: version);

      final poster = found.poster!;
      expect(poster.type, MediaImageType.poster);
      // One segment for the size.
      expect(
        poster.instancePath,
        matches('^${RegExp.escape(prefix)}[^/]+${RegExp.escape(_file)}\$'),
      );
      expect(
        allowList.permits(ServiceRequest(HttpMethod.get, poster.instancePath!)),
        isTrue,
      );
    });
  }

  for (final product in Product.values) {
    test('comes from the public host of ${product.label}', () async {
      final found = await _found(product, cacheImages: false);

      final poster = found.poster!;
      expect(poster.instancePath, isNull);
      expect(poster.remoteUrl?.scheme, 'https');
      expect(poster.remoteUrl?.host, 'image.tmdb.org');
      expect(
        poster.remoteUrl?.path,
        matches('^/t/p/[^/]+${RegExp.escape(_file)}\$'),
      );
    });

    test('is absent where ${product.label} has none', () async {
      final found = await _found(product, cacheImages: true, posterPath: null);

      expect(found.poster, isNull);
    });
  }
}
