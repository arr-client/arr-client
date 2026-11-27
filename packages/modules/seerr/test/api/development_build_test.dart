// A build of the development branch, which has no version number.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';

import '../contract/support.dart';

const _version = 'develop-0123456789abcdef0123456789abcdef01234567';

void main() {
  for (final product in [Product.seerr, Product.overseerr]) {
    test('of ${product.label} is accepted as newer than tested', () async {
      final http = FakeSeerr(product: product)
        ..set(
          'GET api/v1/status',
          json({...recorded('status', product), 'version': _version}),
        );

      final result = valueOf(await SeerrModule().probe(context(http)));

      expect(result.product, product.label);
      expect(result.version, _version);
      expect(result.newerThanTested, isTrue);
    });
  }

  test('is not any other name', () async {
    final http = FakeSeerr()
      ..set('GET api/v1/status', json({'version': 'develop-'}));

    expect(
      failureOf(await SeerrModule().probe(context(http))),
      isA<WrongService>(),
    );
  });
}
