import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accepts a path under the address', () {
    for (final path in [
      '',
      'api/v3/movie',
      'api/v3/movie/7',
      'MediaCover/1/poster.jpg',
      'imageproxy/tmdb/t/p/w300/a.jpg',
      'api/a:b',
    ]) {
      test('"$path"', () {
        expect(ServiceRequest(HttpMethod.get, path).path, path);
      });
    }
  });

  // Each could send credentials elsewhere, or smuggle a query into the path.
  group('rejects', () {
    for (final path in [
      '/api',
      '//evil.test/api',
      'http://evil.test/api',
      'https:evil',
      r'\\evil.test',
      '..',
      'api/../../other',
      './api',
      'api?apikey=secret',
      'api#part',
    ]) {
      test('"$path"', () {
        expect(
          () => ServiceRequest(HttpMethod.get, path),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '$e',
              'message without the path',
              isNot(contains('secret')),
            ),
          ),
        );
      });
    }
  });
}
