import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('is located under its instance', () {
    const route = ModuleRoute(instanceId: 'i1', path: 'radarr/movies/7');

    expect(route.location, '/instances/i1/radarr/movies/7');
  });

  test('encodes the query', () {
    const route = ModuleRoute(
      instanceId: 'i1',
      path: 'seerr/request/7',
      query: {'variant': '4k', 'q': 'a&b'},
    );

    expect(route.location, '/instances/i1/seerr/request/7?variant=4k&q=a%26b');
  });

  test('does not let a path start a query', () {
    const route = ModuleRoute(instanceId: 'i1', path: 'radarr/a?b');

    expect(route.location, '/instances/i1/radarr/a%3Fb');
  });
}
